#!/usr/bin/env bash

cat > /opt/status-page/api/status.json <<EOF
{
  "hostname": "$(hostname)",
  "ip": "$(hostname -I | awk '{print $1}')",
  "uptime": "$(uptime -p | sed 's/^up //')",
  "cpu": "$(top -bn1 | awk -F'id,' '/Cpu/ { split($1,a,","); gsub(/ /,"",a[length(a)]); printf "%.1f%%",100-a[length(a)] }')",
  "memory": "$(free -h | awk '/^Mem:/ {print $3 " / " $2}')",
  "disk": "$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " used)"}')",
  "temperature": "$(sensors 2>/dev/null | awk '/Package id 0:/ {print $4; exit}')",
  "services": {
    "caddy": "$(systemctl is-active caddy)",
    "fail2ban": "$(systemctl is-active fail2ban)",
    "mingolfbot": "$(systemctl is-active mingolfbot)",
    "beniWebsite": "$(systemctl is-active beni-website)"
  },
  "updatedAt": "$(date -Iseconds)"
}
EOF
