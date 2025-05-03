#!/bin/bash
set -e

# Variables (will be replaced by Terraform)
AWS_REGION="${aws_region}"
VOLUME_DEVICE="${volume_device}"
VOLUME_MOUNT_PATH="${volume_mount_path}"
MINECRAFT_WORLD_PATH="${minecraft_world_path}"
MINECRAFT_DOCKER_IMAGE="${minecraft_docker_image}"
MINECRAFT_SERVER_PORT="${minecraft_server_port}"
BACKUP_SCHEDULE_CRON="${backup_schedule_cron}"
SNAPSHOT_SCHEDULE_CRON="${snapshot_schedule_cron}"
S3_BACKUP_BUCKET="${s3_backup_bucket}"
DISCORD_WEBHOOK_URL="${discord_webhook_url}"
AWS_ACCESS_KEY="${aws_access_key}"
AWS_SECRET_KEY="${aws_secret_key}"
INSTANCE_NAME="${instance_name}"
VOLUME_NAME="${volume_name}"
SNAPSHOT_RETENTION_DAYS="${snapshot_retention_days}"

echo "=== Starting Kroni Survival server provisioning ==="

# Update the system
echo "=== Updating system packages ==="
sudo yum update -y

# Install required packages
echo "=== Installing required packages ==="
sudo yum install -y \
    amazon-cloudwatch-agent \
    aws-cli \
    jq \
    unzip \
    git \
    curl

# Configure AWS CLI with backup credentials
echo "=== Configuring AWS CLI ==="
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY
aws_secret_access_key = $AWS_SECRET_KEY
region = $AWS_REGION
EOF

# Install Docker
echo "=== Installing Docker ==="
sudo amazon-linux-extras install docker -y
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

# Format the block storage volume if it's not already formatted
echo "=== Formatting and mounting block storage volume ==="
if [ "$(sudo file -s $VOLUME_DEVICE)" = "$VOLUME_DEVICE: data" ]; then
    echo "Formatting volume $VOLUME_DEVICE..."
    sudo mkfs -t xfs $VOLUME_DEVICE
fi

# Create mount directory if it doesn't exist
sudo mkdir -p $VOLUME_MOUNT_PATH

# Add mount entry to /etc/fstab for persistence across reboots
if ! grep -q "$VOLUME_DEVICE" /etc/fstab; then
    echo "Adding mount entry to /etc/fstab..."
    echo "$VOLUME_DEVICE $VOLUME_MOUNT_PATH xfs defaults,nofail 0 2" | sudo tee -a /etc/fstab
fi

# Mount the volume
sudo mount -a

# Create Minecraft world directory if it doesn't exist
sudo mkdir -p $MINECRAFT_WORLD_PATH
sudo chmod -R 777 $VOLUME_MOUNT_PATH

# Create scripts directory
echo "=== Creating scripts directory ==="
sudo mkdir -p /opt/kroni-survival/scripts
sudo chmod -R 755 /opt/kroni-survival

# Create backup-to-s3 script
echo "=== Creating backup-to-s3 script ==="
cat > /opt/kroni-survival/scripts/backup-to-s3.sh << 'EOF'
#!/bin/bash
set -e

# Variables
WORLD_PATH="MINECRAFT_WORLD_PATH_VALUE"
S3_BUCKET="S3_BUCKET_VALUE"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="minecraft-world-backup-$TIMESTAMP.tar.gz"
TMP_DIR="/tmp"
DISCORD_WEBHOOK_URL="DISCORD_WEBHOOK_URL_VALUE"

# Compress the world directory
echo "Creating backup archive..."
tar -czf "$TMP_DIR/$BACKUP_FILE" -C $(dirname "$WORLD_PATH") $(basename "$WORLD_PATH")

# Upload to S3
echo "Uploading backup to S3..."
aws s3 cp "$TMP_DIR/$BACKUP_FILE" "s3://$S3_BUCKET/$BACKUP_FILE"

# Clean up
rm -f "$TMP_DIR/$BACKUP_FILE"

# Send Discord notification
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "Sending Discord notification..."
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"✅ Minecraft world backup completed successfully! Backup file: $BACKUP_FILE\"}" $DISCORD_WEBHOOK_URL
fi

echo "Backup completed successfully!"
EOF

# Replace placeholders in backup-to-s3.sh
sed -i "s|MINECRAFT_WORLD_PATH_VALUE|$MINECRAFT_WORLD_PATH|g" /opt/kroni-survival/scripts/backup-to-s3.sh
sed -i "s|S3_BUCKET_VALUE|$S3_BACKUP_BUCKET|g" /opt/kroni-survival/scripts/backup-to-s3.sh
sed -i "s|DISCORD_WEBHOOK_URL_VALUE|$DISCORD_WEBHOOK_URL|g" /opt/kroni-survival/scripts/backup-to-s3.sh

sudo chmod +x /opt/kroni-survival/scripts/backup-to-s3.sh

# Create snapshot script
echo "=== Creating snapshot script ==="
cat > /opt/kroni-survival/scripts/create-snapshots.sh << 'EOF'
#!/bin/bash
set -e

# Variables
INSTANCE_NAME="INSTANCE_NAME_VALUE"
VOLUME_NAME="VOLUME_NAME_VALUE"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RETENTION_DAYS=RETENTION_DAYS_VALUE
DISCORD_WEBHOOK_URL="DISCORD_WEBHOOK_URL_VALUE"

# Create instance snapshot
echo "Creating instance snapshot..."
INSTANCE_SNAPSHOT_NAME="$INSTANCE_NAME-$TIMESTAMP"
aws lightsail create-instance-snapshot --instance-name $INSTANCE_NAME --instance-snapshot-name $INSTANCE_SNAPSHOT_NAME

# Create disk snapshot
echo "Creating disk snapshot..."
DISK_SNAPSHOT_NAME="$VOLUME_NAME-$TIMESTAMP"
aws lightsail create-disk-snapshot --disk-name $VOLUME_NAME --disk-snapshot-name $DISK_SNAPSHOT_NAME

# Cleanup old snapshots (older than RETENTION_DAYS)
echo "Cleaning up old snapshots..."
CUTOFF_DATE=$(date -d "-$RETENTION_DAYS days" +%s)

# Cleanup old instance snapshots
INSTANCE_SNAPSHOTS=$(aws lightsail get-instance-snapshots --output json)
for SNAPSHOT in $(echo $INSTANCE_SNAPSHOTS | jq -r '.instanceSnapshots[] | select(.fromInstanceName == "'$INSTANCE_NAME'") | .name'); do
    CREATED_AT=$(echo $INSTANCE_SNAPSHOTS | jq -r '.instanceSnapshots[] | select(.name == "'$SNAPSHOT'") | .createdAt')
    CREATED_TIMESTAMP=$(date -d "$CREATED_AT" +%s)
    
    if [ $CREATED_TIMESTAMP -lt $CUTOFF_DATE ]; then
        echo "Deleting old instance snapshot: $SNAPSHOT"
        aws lightsail delete-instance-snapshot --instance-snapshot-name $SNAPSHOT
    fi
done

# Cleanup old disk snapshots
DISK_SNAPSHOTS=$(aws lightsail get-disk-snapshots --output json)
for SNAPSHOT in $(echo $DISK_SNAPSHOTS | jq -r '.diskSnapshots[] | select(.fromDiskName == "'$VOLUME_NAME'") | .name'); do
    CREATED_AT=$(echo $DISK_SNAPSHOTS | jq -r '.diskSnapshots[] | select(.name == "'$SNAPSHOT'") | .createdAt')
    CREATED_TIMESTAMP=$(date -d "$CREATED_AT" +%s)
    
    if [ $CREATED_TIMESTAMP -lt $CUTOFF_DATE ]; then
        echo "Deleting old disk snapshot: $SNAPSHOT"
        aws lightsail delete-disk-snapshot --disk-snapshot-name $SNAPSHOT
    fi
done

# Send Discord notification
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "Sending Discord notification..."
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"✅ Lightsail snapshots created successfully! Instance: $INSTANCE_SNAPSHOT_NAME, Disk: $DISK_SNAPSHOT_NAME\"}" $DISCORD_WEBHOOK_URL
fi

echo "Snapshots created successfully!"
EOF

# Replace placeholders in create-snapshots.sh
sed -i "s|INSTANCE_NAME_VALUE|$INSTANCE_NAME|g" /opt/kroni-survival/scripts/create-snapshots.sh
sed -i "s|VOLUME_NAME_VALUE|$VOLUME_NAME|g" /opt/kroni-survival/scripts/create-snapshots.sh
sed -i "s|RETENTION_DAYS_VALUE|$SNAPSHOT_RETENTION_DAYS|g" /opt/kroni-survival/scripts/create-snapshots.sh
sed -i "s|DISCORD_WEBHOOK_URL_VALUE|$DISCORD_WEBHOOK_URL|g" /opt/kroni-survival/scripts/create-snapshots.sh

sudo chmod +x /opt/kroni-survival/scripts/create-snapshots.sh

# Create Discord notification script
echo "=== Creating Discord notification script ==="
cat > /opt/kroni-survival/scripts/notify-discord.sh << 'EOF'
#!/bin/bash

# Variables
WEBHOOK_URL="DISCORD_WEBHOOK_URL_VALUE"
MESSAGE="$1"

if [ -z "$MESSAGE" ]; then
    echo "Error: No message provided"
    exit 1
fi

if [ -z "$WEBHOOK_URL" ]; then
    echo "Error: No Discord webhook URL provided"
    exit 1
fi

# Send notification to Discord
curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"$MESSAGE\"}" $WEBHOOK_URL
EOF

# Replace placeholder in notify-discord.sh
sed -i "s|DISCORD_WEBHOOK_URL_VALUE|$DISCORD_WEBHOOK_URL|g" /opt/kroni-survival/scripts/notify-discord.sh

sudo chmod +x /opt/kroni-survival/scripts/notify-discord.sh

# Create cron jobs
echo "=== Setting up cron jobs ==="
(crontab -l 2>/dev/null || true; echo "$BACKUP_SCHEDULE_CRON /opt/kroni-survival/scripts/backup-to-s3.sh >> /var/log/kroni-backup.log 2>&1") | crontab -
(crontab -l 2>/dev/null || true; echo "$SNAPSHOT_SCHEDULE_CRON /opt/kroni-survival/scripts/create-snapshots.sh >> /var/log/kroni-snapshot.log 2>&1") | crontab -

# Create CloudWatch agent configuration
echo "=== Configuring CloudWatch agent ==="
cat > /tmp/cloudwatch-config.json << EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "metrics_collected": {
      "disk": {
        "measurement": [
          "used_percent"
        ],
        "resources": [
          "/"
        ]
      },
      "mem": {
        "measurement": [
          "mem_used_percent"
        ]
      },
      "cpu": {
        "measurement": [
          "cpu_usage_idle",
          "cpu_usage_user",
          "cpu_usage_system"
        ],
        "totalcpu": true
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/kroni-backup.log",
            "log_group_name": "/kroni-survival/backup",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/kroni-snapshot.log",
            "log_group_name": "/kroni-survival/snapshot",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/tmp/cloudwatch-config.json

# Run Minecraft server using Docker
echo "=== Starting Minecraft server container ==="
sudo docker run -d \
  --name minecraft-server \
  --restart always \
  -p ${MINECRAFT_SERVER_PORT}:25565 \
  -v ${MINECRAFT_WORLD_PATH}:/data/world \
  -e EULA=TRUE \
  -e ONLINE_MODE=false \
  -e MEMORY=768m \
  -e ENABLE_AUTOPAUSE=TRUE \
  -e OVERRIDE_SERVER_PROPERTIES=true \
  -e DIFFICULTY=hard \
  -e ALLOW_NETHER=true \
  -e ENABLE_RCON=false \
  -e LEVEL_TYPE=default \
  ${MINECRAFT_DOCKER_IMAGE}

# Send notification about successful setup
if [ -n "$DISCORD_WEBHOOK_URL" ]; then
    echo "=== Sending success notification ==="
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"🎮 Kroni Survival Minecraft server has been successfully deployed! Server IP: $(curl -s http://checkip.amazonaws.com)\"}" $DISCORD_WEBHOOK_URL
fi

echo "=== Provisioning completed successfully! ==="