#!/usr/bin/env bash

set -u

OUTPUT_FILE="${OUTPUT_FILE:-/opt/status-page/api/status.json}"
WEBSITE_REPO_DIR="${WEBSITE_REPO_DIR:-/opt/beni-website}"
STATUS_REPO_DIR="${STATUS_REPO_DIR:-/opt/status-page}"

unknown_if_empty() {
  local value="${1:-}"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf 'unknown'
  fi
}

json_escape() {
  printf '%s' "${1:-}" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/	/\\t/g'
}

json_value() {
  printf '"%s"' "$(json_escape "$(unknown_if_empty "${1:-}")")"
}

first_line_or_unknown() {
  unknown_if_empty "$(printf '%s' "${1:-}" | awk 'NF { print; exit }')"
}

public_ip() {
  local value=""

  if command -v curl >/dev/null 2>&1; then
    value="$(curl -fsS --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  elif command -v wget >/dev/null 2>&1; then
    value="$(wget -qO- -T 3 https://api.ipify.org 2>/dev/null || true)"
  fi

  first_line_or_unknown "$value"
}

ubuntu_version() {
  local value=""

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    value="${PRETTY_NAME:-${VERSION_ID:-}}"
  elif command -v lsb_release >/dev/null 2>&1; then
    value="$(lsb_release -ds 2>/dev/null || true)"
  fi

  first_line_or_unknown "$value"
}

service_status() {
  first_line_or_unknown "$(systemctl is-active "$1" 2>/dev/null || true)"
}

git_branch() {
  local repo_dir="$1"
  if [ -d "$repo_dir/.git" ]; then
    first_line_or_unknown "$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  else
    printf 'unknown'
  fi
}

git_commit() {
  local repo_dir="$1"
  if [ -d "$repo_dir/.git" ]; then
    first_line_or_unknown "$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || true)"
  else
    printf 'unknown'
  fi
}

git_updated() {
  local repo_dir="$1"
  if [ -d "$repo_dir/.git" ]; then
    first_line_or_unknown "$(git -C "$repo_dir" log -1 --format=%cI 2>/dev/null || true)"
  else
    printf 'unknown'
  fi
}

certificate_status() {
  local domain="$1"
  local cert_file=""
  local caddy_cert_root="/var/lib/caddy/.local/share/caddy/certificates"

  if command -v openssl >/dev/null 2>&1 && [ -d "$caddy_cert_root" ]; then
    cert_file="$(find "$caddy_cert_root" -type f \( -name "${domain}.crt" -o -name "${domain}.pem" \) 2>/dev/null | head -n 1)"

    if [ -n "$cert_file" ]; then
      if openssl x509 -checkend 0 -noout -in "$cert_file" >/dev/null 2>&1; then
        if openssl x509 -checkend 1209600 -noout -in "$cert_file" >/dev/null 2>&1; then
          printf 'valid'
        else
          printf 'expiring'
        fi
      else
        printf 'expired'
      fi
      return
    fi
  fi

  printf 'unknown'
}

hostname_value="$(first_line_or_unknown "$(hostname 2>/dev/null || true)")"
local_ip="$(first_line_or_unknown "$(hostname -I 2>/dev/null | awk '{print $1}' || true)")"
uptime_value="$(first_line_or_unknown "$(uptime -p 2>/dev/null | sed 's/^up //' || true)")"
cpu_value="$(first_line_or_unknown "$(top -bn1 2>/dev/null | awk -F'id,' '/Cpu/ { split($1,a,","); gsub(/ /,"",a[length(a)]); printf "%.1f%%",100-a[length(a)] }' || true)")"
memory_value="$(first_line_or_unknown "$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 " / " $2}' || true)")"
disk_value="$(first_line_or_unknown "$(df -h / 2>/dev/null | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}' || true)")"
temperature_value="$(first_line_or_unknown "$(sensors 2>/dev/null | awk '/Package id 0:/ {print $4; exit}' || true)")"

mkdir -p "$(dirname "$OUTPUT_FILE")"

cat > "$OUTPUT_FILE" <<EOF
{
  "hostname": $(json_value "$hostname_value"),
  "ip": $(json_value "$local_ip"),
  "publicIp": $(json_value "$(public_ip)"),
  "ubuntuVersion": $(json_value "$(ubuntu_version)"),
  "kernel": $(json_value "$(uname -r 2>/dev/null || true)"),
  "uptime": $(json_value "$uptime_value"),
  "cpu": $(json_value "$cpu_value"),
  "memory": $(json_value "$memory_value"),
  "disk": $(json_value "$disk_value"),
  "temperature": $(json_value "$temperature_value"),
  "services": {
    "caddy": $(json_value "$(service_status caddy)"),
    "fail2ban": $(json_value "$(service_status fail2ban)"),
    "mingolfbot": $(json_value "$(service_status mingolfbot)"),
    "beniWebsite": $(json_value "$(service_status beni-website)")
  },
  "websiteGit": {
    "branch": $(json_value "$(git_branch "$WEBSITE_REPO_DIR")"),
    "commit": $(json_value "$(git_commit "$WEBSITE_REPO_DIR")"),
    "updated": $(json_value "$(git_updated "$WEBSITE_REPO_DIR")")
  },
  "statusGit": {
    "branch": $(json_value "$(git_branch "$STATUS_REPO_DIR")"),
    "commit": $(json_value "$(git_commit "$STATUS_REPO_DIR")"),
    "updated": $(json_value "$(git_updated "$STATUS_REPO_DIR")")
  },
  "certificates": {
    "beniconsulting.se": $(json_value "$(certificate_status beniconsulting.se)"),
    "status.beniconsulting.se": $(json_value "$(certificate_status status.beniconsulting.se)"),
    "golf.beniconsulting.se": $(json_value "$(certificate_status golf.beniconsulting.se)")
  },
  "updatedAt": $(json_value "$(date -Iseconds 2>/dev/null || true)")
}
EOF
