#!/bin/bash
# AIDE Daily Integrity Check with Email Alerting
# Runs daily via cron - checks filesystem against known-good baseline
# Emails alert only when changes detected (no spam on clean checks)

LOGFILE="/home/ubuntu/aide-check.log"
MAILTO="alerts@example.com"
HOSTNAME=$(hostname)
DATE=$(date '+%Y-%m-%d %H:%M:%S UTC')

echo "[$DATE] Starting AIDE integrity check" >> "$LOGFILE"

# Run AIDE check and capture output
AIDE_OUTPUT=$(sudo aide --check --config=/etc/aide/aide.conf 2>&1)
AIDE_EXIT=$?

# AIDE exit codes:
# 0 = no changes (clean)
# 1-7 = changes detected (bitmask: 1=added, 2=removed, 4=changed)
# 14+ = AIDE itself encountered an error

if [ $AIDE_EXIT -eq 0 ]; then
    echo "[$DATE] AIDE check clean - no changes detected" >> "$LOGFILE"
elif [ $AIDE_EXIT -ge 14 ]; then
    # AIDE error - something is wrong with the tool itself
    BODY=$(printf "AIDE FILE INTEGRITY CHECK - ERROR\nServer: %s\nTime: %s\nExit Code: %s\n\nAIDE encountered an error. Manual investigation required.\n\nOutput:\n%s" "$HOSTNAME" "$DATE" "$AIDE_EXIT" "$AIDE_OUTPUT")
    echo "$BODY" | msmtp -a default "$MAILTO"
    echo "[$DATE] AIDE error (exit $AIDE_EXIT) - alert sent" >> "$LOGFILE"
else
    # Changes detected - parse summary counts
    ADDED=$(echo "$AIDE_OUTPUT" | grep -m1 "Added entries:" | awk '{print $NF}')
    REMOVED=$(echo "$AIDE_OUTPUT" | grep -m1 "Removed entries:" | awk '{print $NF}')
    CHANGED=$(echo "$AIDE_OUTPUT" | grep -m1 "Changed entries:" | awk '{print $NF}')

    BODY=$(printf "AIDE FILE INTEGRITY CHECK - CHANGES DETECTED\nServer: %s\nTime: %s\n\nSummary:\n  Added:   %s\n  Removed: %s\n  Changed: %s\n\n--- Full Report ---\n%s\n\n--- Action Required ---\nReview the changes above.\nIf expected (e.g., after apt update), update the baseline:\n  sudo aide --init --config=/etc/aide/aide.conf\n  sudo cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db" "$HOSTNAME" "$DATE" "$ADDED" "$REMOVED" "$CHANGED" "$AIDE_OUTPUT")
    echo "$BODY" | msmtp -a default "$MAILTO"
    echo "[$DATE] AIDE found changes (A:$ADDED R:$REMOVED C:$CHANGED) - alert sent" >> "$LOGFILE"
fi
