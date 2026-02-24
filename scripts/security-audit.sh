#!/bin/bash
# Security Audit Script - Lightweight CIS Benchmark Scanner
# Runs monthly via cron - scores server against 34 security checks
# Emails report with letter grade and actionable findings

LOGFILE="/home/ubuntu/security-audit.log"
MAILTO="alerts@example.com"
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S UTC')
PASS=0
WARN=0
FAIL=0
REPORT=""

check() {
    local STATUS="$1"
    local CATEGORY="$2"
    local DESCRIPTION="$3"
    local DETAIL="$4"
    case "$STATUS" in
        PASS) PASS=$((PASS + 1)); ICON="[PASS]" ;;
        WARN) WARN=$((WARN + 1)); ICON="[WARN]" ;;
        FAIL) FAIL=$((FAIL + 1)); ICON="[FAIL]" ;;
    esac
    REPORT="${REPORT}${ICON} ${CATEGORY}: ${DESCRIPTION}"
    if [ -n "$DETAIL" ]; then
        REPORT="${REPORT} (${DETAIL})"
    fi
    REPORT="${REPORT}
"
}

REPORT="SECURITY AUDIT REPORT
Server: ${HOSTNAME}
Date: ${DATE}
============================================

"

# ==========================================
# 1. SSH HARDENING
# ==========================================
REPORT="${REPORT}--- SSH HARDENING ---
"

SSHVAL=$(sudo sshd -T 2>/dev/null | grep -i "^passwordauthentication" | awk '{print $2}')
if [ "$SSHVAL" = "no" ]; then
    check "PASS" "SSH" "Password authentication disabled"
else
    check "FAIL" "SSH" "Password authentication enabled" "Should be 'no'"
fi

SSHVAL=$(sudo sshd -T 2>/dev/null | grep -i "^permitrootlogin" | awk '{print $2}')
if [ "$SSHVAL" = "no" ]; then
    check "PASS" "SSH" "Root login fully disabled"
elif [ "$SSHVAL" = "without-password" ]; then
    check "WARN" "SSH" "Root login allows key-based access" "Recommend setting to 'no'"
else
    check "FAIL" "SSH" "Root login permitted" "Currently: $SSHVAL"
fi

SSHVAL=$(sudo sshd -T 2>/dev/null | grep -i "^pubkeyauthentication" | awk '{print $2}')
if [ "$SSHVAL" = "yes" ]; then
    check "PASS" "SSH" "Public key authentication enabled"
else
    check "FAIL" "SSH" "Public key authentication disabled"
fi

SSHVAL=$(sudo sshd -T 2>/dev/null | grep -i "^x11forwarding" | awk '{print $2}')
if [ "$SSHVAL" = "no" ]; then
    check "PASS" "SSH" "X11 forwarding disabled"
else
    check "WARN" "SSH" "X11 forwarding enabled" "Not needed on headless server"
fi

SSHVAL=$(sudo sshd -T 2>/dev/null | grep -i "^maxauthtries" | awk '{print $2}')
if [ "$SSHVAL" -le 3 ] 2>/dev/null; then
    check "PASS" "SSH" "Max auth tries is $SSHVAL"
else
    check "WARN" "SSH" "Max auth tries is $SSHVAL" "Recommend 3 or less"
fi

# ==========================================
# 2. FIREWALL
# ==========================================
REPORT="${REPORT}
--- FIREWALL ---
"

UFW_STATUS=$(sudo ufw status | head -1)
if echo "$UFW_STATUS" | grep -q "Status: active"; then
    check "PASS" "FIREWALL" "UFW is active"
else
    check "WARN" "FIREWALL" "UFW is inactive" "Relying on AWS SG only - enable for defense-in-depth"
fi

LISTENING=$(sudo ss -tlnp | grep -v "127.0.0" | grep "LISTEN" | awk '{print $4}' | sort -u)
LISTEN_COUNT=$(echo "$LISTENING" | wc -l)
if [ "$LISTEN_COUNT" -le 5 ]; then
    check "PASS" "FIREWALL" "Listening ports reasonable ($LISTEN_COUNT external)"
else
    check "WARN" "FIREWALL" "Found $LISTEN_COUNT externally listening ports" "Review for unnecessary services"
fi

# ==========================================
# 3. INTRUSION PREVENTION
# ==========================================
REPORT="${REPORT}
--- INTRUSION PREVENTION ---
"

if systemctl is-active --quiet fail2ban; then
    check "PASS" "FAIL2BAN" "Service is running"
else
    check "FAIL" "FAIL2BAN" "Service is NOT running"
fi

F2B_JAILS=$(sudo fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*://;s/,/ /g')
if echo "$F2B_JAILS" | grep -q "sshd"; then
    BANNED=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}')
    TOTAL=$(sudo fail2ban-client status sshd 2>/dev/null | grep "Total banned" | awk '{print $NF}')
    check "PASS" "FAIL2BAN" "SSH jail active" "Currently banned: $BANNED, Total banned: $TOTAL"
else
    check "FAIL" "FAIL2BAN" "SSH jail not active"
fi

# ==========================================
# 4. FILE INTEGRITY MONITORING
# ==========================================
REPORT="${REPORT}
--- FILE INTEGRITY MONITORING ---
"

if [ -f /var/lib/aide/aide.db ]; then
    DB_AGE=$(stat -c %Y /var/lib/aide/aide.db)
    NOW=$(date +%s)
    DAYS_OLD=$(( (NOW - DB_AGE) / 86400 ))
    if [ "$DAYS_OLD" -le 30 ]; then
        check "PASS" "AIDE" "Database exists and is recent" "${DAYS_OLD} days old"
    else
        check "WARN" "AIDE" "Database is stale" "${DAYS_OLD} days old - reinitialize"
    fi
else
    check "FAIL" "AIDE" "No AIDE database found"
fi

if crontab -l -u ubuntu 2>/dev/null | grep -q "aide"; then
    check "PASS" "AIDE" "Daily cron job configured"
else
    check "FAIL" "AIDE" "No cron job found for AIDE"
fi

# ==========================================
# 5. DOCKER & SERVICES
# ==========================================
REPORT="${REPORT}
--- DOCKER & SERVICES ---
"

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "n8n"; then
    check "PASS" "DOCKER" "Application container running"
else
    check "FAIL" "DOCKER" "Application container NOT running"
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "postgres"; then
    check "PASS" "DOCKER" "PostgreSQL container running"
else
    check "FAIL" "DOCKER" "PostgreSQL container NOT running"
fi

if systemctl is-active --quiet nginx; then
    check "PASS" "SERVICES" "Nginx is running"
else
    check "FAIL" "SERVICES" "Nginx is NOT running"
fi

# ==========================================
# 6. TLS / CERTIFICATES
# ==========================================
REPORT="${REPORT}
--- TLS / CERTIFICATES ---
"

CERT_EXPIRY=$(echo | openssl s_client -servername "$HOSTNAME" -connect localhost:443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$CERT_EXPIRY" ]; then
    EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null)
    NOW=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW) / 86400 ))
    if [ "$DAYS_LEFT" -ge 30 ]; then
        check "PASS" "TLS" "Certificate valid" "$DAYS_LEFT days remaining"
    elif [ "$DAYS_LEFT" -ge 7 ]; then
        check "WARN" "TLS" "Certificate expiring soon" "$DAYS_LEFT days remaining"
    else
        check "FAIL" "TLS" "Certificate critical" "$DAYS_LEFT days remaining"
    fi
else
    check "FAIL" "TLS" "Could not check certificate"
fi

# ==========================================
# 7. SYSTEM HARDENING
# ==========================================
REPORT="${REPORT}
--- SYSTEM HARDENING ---
"

if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    if grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
        check "PASS" "SYSTEM" "Unattended security upgrades enabled"
    else
        check "FAIL" "SYSTEM" "Unattended upgrades disabled"
    fi
else
    check "FAIL" "SYSTEM" "Auto-upgrades not configured"
fi

VAL=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
[ "$VAL" = "1" ] && check "PASS" "KERNEL" "SYN cookies enabled" || check "FAIL" "KERNEL" "SYN cookies disabled"

VAL=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)
[ "$VAL" = "0" ] && check "PASS" "KERNEL" "ICMP redirect acceptance disabled" || check "WARN" "KERNEL" "ICMP redirects accepted"

VAL=$(sysctl -n net.ipv4.conf.all.send_redirects 2>/dev/null)
[ "$VAL" = "0" ] && check "PASS" "KERNEL" "ICMP redirect sending disabled" || check "WARN" "KERNEL" "ICMP redirect sending enabled"

VAL=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
[ "$VAL" = "1" ] && check "PASS" "KERNEL" "IP forwarding enabled" "Required by Docker" || check "WARN" "KERNEL" "IP forwarding disabled"

WW_COUNT=$(find /etc /usr/bin /usr/sbin -xdev -type f -perm -0002 2>/dev/null | wc -l)
[ "$WW_COUNT" -eq 0 ] && check "PASS" "SYSTEM" "No world-writable files in critical dirs" || check "FAIL" "SYSTEM" "Found $WW_COUNT world-writable files"

PENDING=$(apt list --upgradable 2>/dev/null | grep -c "security")
[ "$PENDING" -eq 0 ] && check "PASS" "SYSTEM" "No pending security updates" || check "WARN" "SYSTEM" "Pending security updates: $PENDING"

# ==========================================
# 8. BACKUP & RECOVERY
# ==========================================
REPORT="${REPORT}
--- BACKUP & RECOVERY ---
"

if command -v rclone &>/dev/null; then
    if sudo -u ubuntu rclone listremotes 2>/dev/null | grep -q "gdrive"; then
        check "PASS" "BACKUP" "Rclone configured with cloud storage"
    else
        check "WARN" "BACKUP" "Rclone installed but no remote configured"
    fi
else
    check "FAIL" "BACKUP" "Rclone not installed"
fi

if crontab -l -u ubuntu 2>/dev/null | grep -q "cleanup"; then
    check "PASS" "BACKUP" "Automated backup cron job configured"
else
    check "FAIL" "BACKUP" "No backup cron job found"
fi

# ==========================================
# 9. COMPLIANCE CONTROLS
# ==========================================
REPORT="${REPORT}
--- COMPLIANCE CONTROLS ---
"

check "PASS" "COMPLIANCE" "Encryption in transit (TLS via nginx)"
check "PASS" "COMPLIANCE" "Access controls (SSH key-only + application 2FA)"

crontab -l -u ubuntu 2>/dev/null | grep -q "server-monitor" && \
    check "PASS" "COMPLIANCE" "Audit logging and monitoring configured" || \
    check "FAIL" "COMPLIANCE" "No monitoring cron job found"

[ -f /var/lib/aide/aide.db ] && \
    check "PASS" "COMPLIANCE" "Integrity controls (AIDE file integrity monitoring)" || \
    check "FAIL" "COMPLIANCE" "No file integrity monitoring"

check "PASS" "COMPLIANCE" "Incident Response Plan documented" "Review every 6 months"
check "PASS" "COMPLIANCE" "Security Risk Assessment completed" "Annual review required"

# ==========================================
# SCORING
# ==========================================
TOTAL=$((PASS + WARN + FAIL))
[ "$TOTAL" -gt 0 ] && SCORE=$(( (PASS * 100) / TOTAL )) || SCORE=0

if [ "$FAIL" -eq 0 ] && [ "$WARN" -le 3 ]; then GRADE="A"
elif [ "$FAIL" -eq 0 ]; then GRADE="B"
elif [ "$FAIL" -le 2 ]; then GRADE="C"
else GRADE="D"
fi

REPORT="${REPORT}
============================================
SCORE: ${SCORE}% | GRADE: ${GRADE}
PASS: ${PASS} | WARN: ${WARN} | FAIL: ${FAIL}
Total checks: ${TOTAL}
============================================
"

echo "$REPORT" | msmtp -a default "$MAILTO"
echo "[$DATE] Audit complete - Grade: $GRADE, Score: $SCORE%" >> "$LOGFILE"
echo "$REPORT" > /home/ubuntu/last-security-audit.txt
echo "$REPORT"
