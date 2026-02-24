#!/bin/bash
# Server Health Monitor - 7-Check System with Email Alerting
# Runs every 15 minutes via cron
# Only sends email when issues detected (1-hour cooldown prevents spam)

LOGFILE="/home/ubuntu/server-monitor.log"
MAILTO="alerts@example.com"
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S UTC')
COOLDOWN_FILE="/tmp/server-monitor-cooldown"
COOLDOWN_SECONDS=3600
ISSUES=""

# Check cooldown - prevent repeated alerts for same ongoing issue
if [ -f "$COOLDOWN_FILE" ]; then
    LAST_ALERT=$(cat "$COOLDOWN_FILE")
    NOW=$(date +%s)
    ELAPSED=$((NOW - LAST_ALERT))
    if [ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]; then
        echo "[$DATE] Cooldown active (${ELAPSED}s elapsed). Skipping." >> "$LOGFILE"
        exit 0
    fi
fi

# Check 1: Disk usage (alert at 90%, cleanup triggers at 80%)
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_USAGE" -ge 90 ]; then
    ISSUES="${ISSUES}CRITICAL: Disk usage at ${DISK_USAGE}%\n"
fi

# Check 2: Application container running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "n8n"; then
    ISSUES="${ISSUES}CRITICAL: Application container is DOWN\n"
fi

# Check 3: PostgreSQL container running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "postgres"; then
    ISSUES="${ISSUES}CRITICAL: PostgreSQL container is DOWN\n"
fi

# Check 4: Nginx running
if ! systemctl is-active --quiet nginx; then
    ISSUES="${ISSUES}CRITICAL: Nginx is DOWN\n"
fi

# Check 5: SSL certificate expiring within 14 days
CERT_DAYS=$(echo | openssl s_client -servername localhost -connect localhost:443 2>/dev/null | openssl x509 -noout -checkend 1209600 2>/dev/null)
if [ $? -ne 0 ]; then
    ISSUES="${ISSUES}WARNING: SSL certificate expires within 14 days\n"
fi

# Check 6: Memory usage above 90%
MEM_USAGE=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -ge 90 ]; then
    ISSUES="${ISSUES}WARNING: Memory usage at ${MEM_USAGE}%\n"
fi

# Check 7: Fail2Ban banned IPs (informational)
BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
if [ -n "$BANNED" ] && [ "$BANNED" -gt 0 ]; then
    ISSUES="${ISSUES}INFO: ${BANNED} IPs currently banned by Fail2Ban\n"
fi

# Send alert only if issues found
if [ -n "$ISSUES" ]; then
    BODY=$(printf "SERVER HEALTH ALERT\nServer: %s\nTime: %s\n\nIssues Detected:\n%b" "$HOSTNAME" "$DATE" "$ISSUES")
    echo "$BODY" | msmtp -a default "$MAILTO"
    date +%s > "$COOLDOWN_FILE"
    echo "[$DATE] Issues detected - alert sent" >> "$LOGFILE"
else
    echo "[$DATE] All checks passed" >> "$LOGFILE"
fi
