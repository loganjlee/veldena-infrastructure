#!/bin/bash
# Weekly Security Report
# Runs Sunday 8AM UTC via cron - full security summary
# Reports: system health, security events, workflow activity, backup status

MAILTO="alerts@example.com"
HOSTNAME=$(hostname)
CONTAINER="postgres_container"
DB_USER="postgres"
DB_NAME="appdb"

REPORT="WEEKLY SECURITY REPORT
Server: ${HOSTNAME}
Generated: $(date '+%Y-%m-%d %H:%M:%S UTC')
Period: $(date -d '7 days ago' '+%Y-%m-%d') to $(date '+%Y-%m-%d')
============================================

--- SYSTEM HEALTH ---
Uptime: $(uptime -p)
Kernel: $(uname -r)
Disk Usage: $(df -h / | tail -1 | awk '{print $5}')
Memory Usage: $(free -m | awk '/Mem:/ {printf "%d/%dMB (%.0f%%)", $3, $2, $3/$2*100}')
"

# Container status
for NAME in n8n postgres; do
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "$NAME"; then
        REPORT="${REPORT}Container $NAME: RUNNING
"
    else
        REPORT="${REPORT}Container $NAME: DOWN
"
    fi
done

# SSL certificate
DAYS=$(echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -checkend 0 2>/dev/null && echo "valid" || echo "EXPIRED")
REPORT="${REPORT}SSL Certificate: ${DAYS}
"

# Security events
REPORT="${REPORT}
--- SECURITY EVENTS ---
"
FAILED_SSH=$(grep -c "Failed password\|Failed publickey" /var/log/auth.log 2>/dev/null || echo "0")
SUCCESS_SSH=$(grep -c "Accepted" /var/log/auth.log 2>/dev/null || echo "0")
BANNED_TOTAL=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
BANNED_NOW=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')

REPORT="${REPORT}Failed SSH attempts: ${FAILED_SSH}
Successful SSH logins: ${SUCCESS_SSH}
IPs currently banned: ${BANNED_NOW}
Total IPs banned (all time): ${BANNED_TOTAL}
"

# Top offenders
REPORT="${REPORT}
Top 5 blocked IPs:
$(grep "Ban " /var/log/fail2ban.log 2>/dev/null | awk '{print $NF}' | sort | uniq -c | sort -rn | head -5)
"

# Backup status
REPORT="${REPORT}
--- BACKUP STATUS ---
$(rclone ls gdrive:backups/ 2>/dev/null | tail -5)
"

REPORT="${REPORT}
============================================
Next report: $(date -d 'next Sunday' '+%Y-%m-%d')
"

echo "$REPORT" | msmtp -a default "$MAILTO"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Weekly report sent" >> /home/ubuntu/weekly-report.log
