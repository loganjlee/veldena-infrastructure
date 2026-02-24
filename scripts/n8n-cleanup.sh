#!/bin/bash
# Automated Backup Lifecycle + Disk Management
# Runs hourly via cron - backs up execution data per-client then cleans up
# Prevents disk exhaustion that previously caused production outage

LOG_FILE="/home/ubuntu/n8n-cleanup.log"
THRESHOLD=80
DATE=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_DIR="/tmp/n8n-backups-${DATE}"
CONTAINER="postgres_container"
DB_USER="postgres"
DB_NAME="appdb"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
log "Disk usage: ${USAGE}%"

if [ "$USAGE" -lt "$THRESHOLD" ]; then
    log "Disk usage below ${THRESHOLD}%. No cleanup needed."
    exit 0
fi

log "Disk usage above ${THRESHOLD}%. Starting cleanup..."
mkdir -p "$BACKUP_DIR"

# Client list mapped to backup folder names
# Each client's workflows are tagged in the application for isolation
CLIENTS=("Client A" "Client B" "Client C" "Internal")
FOLDERS=("client-a" "client-b" "client-c" "internal")

for i in "${!CLIENTS[@]}"; do
    CLIENT="${CLIENTS[$i]}"
    FOLDER="${FOLDERS[$i]}"

    COUNT=$(docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "
        SELECT COUNT(*) FROM execution_entity e
        JOIN workflow_entity w ON e.\"workflowId\" = w.id
        JOIN workflows_tags wt ON wt.\"workflowId\" = w.id
        JOIN tag_entity t ON t.id = wt.\"tagId\"
        WHERE t.name = '${CLIENT}'
        AND e.\"stoppedAt\" < NOW() - INTERVAL '7 days';
    " 2>/dev/null | tr -d ' ')

    if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ]; then
        log "Client '${CLIENT}': ${COUNT} old executions found. Backing up..."

        # Export execution metadata (IDs, status, timestamps)
        docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
            COPY (
                SELECT e.* FROM execution_entity e
                JOIN workflow_entity w ON e.\"workflowId\" = w.id
                JOIN workflows_tags wt ON wt.\"workflowId\" = w.id
                JOIN tag_entity t ON t.id = wt.\"tagId\"
                WHERE t.name = '${CLIENT}'
                AND e.\"stoppedAt\" < NOW() - INTERVAL '7 days'
            ) TO STDOUT WITH CSV HEADER;
        " > "${BACKUP_DIR}/${FOLDER}-${DATE}.csv" 2>/dev/null

        # Export execution data (full node inputs/outputs for forensic investigation)
        docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "
            COPY (
                SELECT ed.* FROM execution_data ed
                JOIN execution_entity e ON ed.\"executionId\" = e.id
                JOIN workflow_entity w ON e.\"workflowId\" = w.id
                JOIN workflows_tags wt ON wt.\"workflowId\" = w.id
                JOIN tag_entity t ON t.id = wt.\"tagId\"
                WHERE t.name = '${CLIENT}'
                AND e.\"stoppedAt\" < NOW() - INTERVAL '7 days'
            ) TO STDOUT WITH CSV HEADER;
        " > "${BACKUP_DIR}/${FOLDER}-data-${DATE}.csv" 2>/dev/null

        rclone mkdir "gdrive:backups/${FOLDER}"
        rclone copy "${BACKUP_DIR}/${FOLDER}-${DATE}.csv" "gdrive:backups/${FOLDER}/" 2>> "$LOG_FILE"
        rclone copy "${BACKUP_DIR}/${FOLDER}-data-${DATE}.csv" "gdrive:backups/${FOLDER}/" 2>> "$LOG_FILE"
        log "Client '${CLIENT}': Backup + execution data uploaded"
    else
        log "Client '${CLIENT}': No old executions to clean."
    fi
done

log "Deleting all executions older than 7 days..."
docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "DELETE FROM execution_entity WHERE \"stoppedAt\" < NOW() - INTERVAL '7 days';" 2>> "$LOG_FILE"
docker exec "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "VACUUM;" 2>> "$LOG_FILE"
rm -rf "$BACKUP_DIR"

NEW_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
log "Cleanup complete. Disk usage: ${NEW_USAGE}% (was ${USAGE}%)"
