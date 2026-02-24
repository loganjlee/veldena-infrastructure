# Backup Failure Response

## How Failures Are Detected

- Weekly report shows backup status and last successful backup date
- Manual check by reviewing the cleanup log

## Step 1: Check the Log

```bash
tail -50 /home/ubuntu/n8n-cleanup.log
```

Look for error messages from rclone (upload failures) or psql (export failures).

## Step 2: Figure Out What Went Wrong

### Disk Below Threshold (Most Common, Not Actually a Failure)

If the log says:
```
Disk usage below 80%. No cleanup needed.
```

This is normal. The cleanup script only backs up and cleans when disk exceeds 80%. Data is still accumulating and will be backed up when the threshold triggers.

To force a backup, either lower the threshold temporarily or run the export commands manually.

### Rclone Upload Failed

If the log shows rclone errors:

1. Check rclone auth:
   ```bash
   rclone ls gdrive:n8n-backups/ --max-depth 1
   ```
2. If auth expired: re-authenticate rclone with Google Drive
3. If network issue: check internet connectivity
4. If Drive is full: check Google Workspace storage quota

### PostgreSQL Export Failed

If the log shows psql errors:

1. Check if the container is running:
   ```bash
   docker ps | grep postgres
   ```
2. Test database connectivity:
   ```bash
   docker exec [CONTAINER] psql -U postgres -d [DATABASE] -c "SELECT 1;"
   ```
3. Check disk space. If disk is at 100%, PostgreSQL may be in read-only mode:
   ```bash
   df -h /
   ```

### Container Not Running

If Docker containers are down:

1. Restart them:
   ```bash
   cd /home/ubuntu && docker-compose up -d
   ```
2. Check why they stopped:
   ```bash
   docker logs [CONTAINER] --tail 50
   ```

## Step 3: Verify It's Working Again

1. Force a manual backup:
   ```bash
   /home/ubuntu/n8n-cleanup.sh
   ```
2. Verify the upload:
   ```bash
   rclone ls gdrive:n8n-backups/ | tail -5
   ```
3. Check the log:
   ```bash
   tail -20 /home/ubuntu/n8n-cleanup.log
   ```

## Escalation

If backups have been failing for more than 24 hours and you can't fix it, the server is accumulating execution data without offloading. The disk will eventually fill up and crash PostgreSQL. Prioritize fixing this or manually export critical client data.
