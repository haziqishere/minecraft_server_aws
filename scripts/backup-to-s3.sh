#!/bin/bash
set -e

# Configuration - set these variables or pass them as environment variables
WORLD_PATH=${WORLD_PATH:-"/data/world"}
S3_BUCKET=${S3_BUCKET:-"kroni-survival-backups"}
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="minecraft-world-backup-$TIMESTAMP.tar.gz"
TMP_DIR="/tmp"
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL:-""}
RETENTION_DAYS=${RETENTION_DAYS:-30}  # Default to keeping backups for 30 days

# Function to send Discord notification
send_notification() {
    local status=$1
    local message=$2
    
    if [ -n "$DISCORD_WEBHOOK_URL" ]; then
        echo "Sending Discord notification..."
        curl -s -H "Content-Type: application/json" -X POST -d "{\"content\":\"$message\"}" $DISCORD_WEBHOOK_URL
    fi
}

# Function to clean up old backups
cleanup_old_backups() {
    echo "Checking for old backups to clean up..."
    
    # Calculate the cutoff date (RETENTION_DAYS days ago)
    CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%s)
    
    # List all backups in the S3 bucket
    BACKUPS=$(aws s3 ls "s3://$S3_BUCKET/" | grep "minecraft-world-backup-" || true)
    
    # Iterate through each backup
    echo "$BACKUPS" | while read -r line; do
        # Extract the date part from the backup filename
        BACKUP_NAME=$(echo $line | awk '{print $4}')
        if [ -z "$BACKUP_NAME" ]; then
            continue
        fi
        
        # Extract the timestamp from the filename
        DATE_PART=$(echo $BACKUP_NAME | grep -o '[0-9]\{8\}-[0-9]\{6\}' || echo "")
        if [ -z "$DATE_PART" ]; then
            continue
        fi
        
        # Convert the backup date to seconds since epoch
        BACKUP_DATE=$(date -d "${DATE_PART:0:8} ${DATE_PART:9:2}:${DATE_PART:11:2}:${DATE_PART:13:2}" +%s 2>/dev/null || echo "0")
        
        # Compare with cutoff date
        if [ $BACKUP_DATE -lt $CUTOFF_DATE ]; then
            echo "Removing old backup: $BACKUP_NAME"
            aws s3 rm "s3://$S3_BUCKET/$BACKUP_NAME"
        fi
    done
}

# Stop the Minecraft server to ensure consistent backup
echo "Stopping Minecraft server for backup..."
docker stop minecraft-server || echo "Server already stopped or container not found"

# Compress the world directory
echo "Creating backup archive of $WORLD_PATH..."
tar -czf "$TMP_DIR/$BACKUP_FILE" -C $(dirname "$WORLD_PATH") $(basename "$WORLD_PATH")

# Start the Minecraft server again
echo "Starting Minecraft server again..."
docker start minecraft-server || echo "Failed to start server - it may need to be initialized first"

# Upload to S3
echo "Uploading backup to S3..."
if aws s3 cp "$TMP_DIR/$BACKUP_FILE" "s3://$S3_BUCKET/$BACKUP_FILE"; then
    echo "Backup uploaded successfully to s3://$S3_BUCKET/$BACKUP_FILE"
    BACKUP_SIZE=$(du -h "$TMP_DIR/$BACKUP_FILE" | cut -f1)
    send_notification "SUCCESS" "✅ Minecraft world backup completed successfully!\nBackup file: $BACKUP_FILE\nSize: $BACKUP_SIZE\nTimestamp: $(date)"
else
    echo "Failed to upload backup to S3"
    send_notification "FAILURE" "❌ Minecraft world backup failed! Error uploading to S3.\nTimestamp: $(date)"
    exit 1
fi

# Clean up temporary file
rm -f "$TMP_DIR/$BACKUP_FILE"
echo "Temporary files cleaned up"

# Clean up old backups based on retention policy
cleanup_old_backups

echo "Backup process completed successfully!"