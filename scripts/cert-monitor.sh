#!/bin/bash
# SSL Certificate Monitor + Auto-Renewal
# Runs daily via cron - checks certificate expiry and auto-renews when needed
# Handles three states: healthy, expiring soon (auto-renew), already expired (force-renew)

LOGFILE="/home/ubuntu/cert-monitor.log"
MAILTO="alerts@example.com"
DOMAIN="app.example.com"
DATE=$(date '+%Y-%m-%d %H:%M:%S UTC')

echo "[$DATE] Checking SSL certificate for $DOMAIN" >> "$LOGFILE"

# Get days until expiration
EXPIRY_DATE=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

if [ -z "$EXPIRY_DATE" ]; then
    echo "[$DATE] ERROR: Could not retrieve certificate" >> "$LOGFILE"
    printf "SSL CERTIFICATE ERROR\nCould not retrieve cert for %s\nManual investigation required." "$DOMAIN" | msmtp -a default "$MAILTO"
    exit 1
fi

EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s)
NOW=$(date +%s)
DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW) / 86400 ))

echo "[$DATE] Certificate expires in $DAYS_LEFT days ($EXPIRY_DATE)" >> "$LOGFILE"

if [ "$DAYS_LEFT" -le 0 ]; then
    # Certificate already expired - force renewal
    echo "[$DATE] Certificate EXPIRED. Force renewing..." >> "$LOGFILE"
    sudo certbot renew --force-renewal --nginx 2>> "$LOGFILE"
    sudo systemctl restart nginx
    printf "SSL CERTIFICATE RENEWED (was expired)\nDomain: %s\nNginx restarted." "$DOMAIN" | msmtp -a default "$MAILTO"

elif [ "$DAYS_LEFT" -le 14 ]; then
    # Certificate expiring soon - auto-renew
    echo "[$DATE] Certificate expiring in $DAYS_LEFT days. Renewing..." >> "$LOGFILE"
    sudo certbot renew --nginx 2>> "$LOGFILE"
    sudo systemctl restart nginx
    printf "SSL CERTIFICATE RENEWED\nDomain: %s\nWas expiring in %s days.\nNginx restarted." "$DOMAIN" "$DAYS_LEFT" | msmtp -a default "$MAILTO"

else
    echo "[$DATE] Certificate healthy. $DAYS_LEFT days remaining." >> "$LOGFILE"
fi
