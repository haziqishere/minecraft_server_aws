"""
Kroni Survival Minecraft Server - Backup Flow

This Prefect flow handles:
1. Taking a backup of the Minecraft world
2. Uploadin the backup to s3
3. managing Lightsail snapshots
4. Sending a notification to Discord


Run this script directly or schedule it with Prefect
"""

import os
import sys
import subprocess
import datetime
import tempfile
import json
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Import Prefect modules
from prefect import flow, task, get_run_logger
from prefect.context import FlowRunContext
import boto3
import requests

# Default config
DEFAULT_CONFIG = {
     "world_path": "/data/world",
    "s3_bucket": "kroni-survival-backups",
    "instance_name": "kroni-survival-server",
    "disk_name": "kroni-survival-data",
    "region": "ap-southeast-5",
    "retention_days": 30,
    "discord_webhook_url": "",
}

@task(name="Check Minecraft Server Status")
def check_server_status() -> bool:
    """Check if the Minecraft server is running"""
    logger = get_run_logger()
    try:
        result = subprocess.run(
            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=True,
        )
        is_running = "minecraft-server" in result.stdout
        logger.info(f"Minecraft server status: {'Running' if is_running else 'Stopped'}")
        return is_running
    except subprocess.CalledProcessError as e:
        logger.error(f"Failed to check server status: {e}")
        return False
    
@task(name="Stop Minecraft Server")
def stop_minecraft_server() -> bool:
    """Stop the Minecraft server to ensure a consistent backup."""
    logger = get_run_logger()
    try:
        logger.info("Stopping Minectaft server for backup...")
        result = subprocess.run(
            ["docker", "stop", "minecraft-server"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    except Exception as e:
        logger.error(f"Failed to stop Minecraft Server: {e}")
        return False
    
@task(name="Start Minecraft Server")
def start_minecraft_server() -> bool:
    """Start the Minecrasft server after backup."""
    logger = get_run_logger()
    try:
        logger.info("Starting Minecraft server...")
        result = subprocess.run(
            ["docker", "start", "minecraft-server"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    except Exception as e:
        logger.error(f"Failed to start Minecraft Server: {e}")
        return False

@task(name="Create World Backup")
def create_world_backup(world_path: str) -> Optional[str]:
    """Create a tar.gz backup of the Minecrtaft world."""
    logger = get_run_logger()
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_filename = f"minecraft-world-backup-{timestamp}.tar.gz"

    try:
        with tempfile.TemporaryDirectory() as temp_dir:
            backup_path = Path(temp_dir) / backup_filename

            logger.info(f"Creating backup archive of {world_path}...")
            world_dir = Path(world_path)

        if not world_dir.exists():
            logger.error(f"World directory {world_path} does not exist!")
            return None
        
        subprocess.run(
            ["tar", "-czf", str(backup_path), "-C", str(world_dir.paren), world_dir.name],
            check=True,
        )

        logger.info(f"Backup created at {backup_path}")
        return str(backup_path)
    
    except Exception as e:
        logger.error(f"Failed to create world backup: {e}")
        return None
    
@task(name="Upload Backup to S3")
def upload_to_s3(backup_path: str, bucket_name: str, region: str) -> bool:
    """Upload the backup file to S3."""
    
    logger = get_run_logger()
    if not backup_path:
        logger.error("No backup file to upload.")
        return False
    
    try:
        filename = os.path.basename(backup_path)
        logger.info(f"Uploading backup to S3 bucker '{bucket_name}'... ")

        s3_client = boto3.client("s3", region_name=region)
        s3_client.upload_file(backup_path, bucket_name, filename)

        logger.info(f"Backup uploaded successfully to s3://{bucket_name}/{filename}")
        return True
    except Exception as e:
        logger.error(f"Failed to upload backup to S3: {e}")
        return False
    
@task(name="Create Lightsail Snapshot")
def create_lightsail_snapshots(
    instance_name: str, disk_name: str, region: str
) -> Tuple[bool, str, str]:
    """Create snapshots of the Lightsail instance and disk."""
    logger = get_run_logger()
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    instance_snapshot_name = f"{instance_name}-{timestamp}"
    disk_snapshot_name = f"{disk_name}-{timestamp}"

    try:
        logger.info(f"Creating Lightsail snapshot...")
        lightsail_client = boto3.client('lightsail', region_name=region)

        # Create instance snapshot
        logger.info(f"Creating instance snapshot: {instance_snapshot_name}")
        lightsail_client.create_instance_snapshot(
            instanceName=instance_name,
            instanceSnapshotName=instance_snapshot_name
        )    

        # Create disk snapshot
        logger.info(f"Creating disk snapshot: {disk_snapshot_name}")
        lightsail_client.create_disk_snapshot(
            diskName=disk_name,
            diskSnapshotName=disk_snapshot_name
        )

        logger.info(f"Creating disk snapshot: {disk_snapshot_name}")
        lightsail_client.create_disk_snapshot(
            diskName=disk_name,
            diskSnapshotame=disk_snapshot_name
        )
        logger.info("Snapshot created successfully")
        return True, instance_snapshot_name, disk_snapshot_name
    except Exception as e:
        logger.error(f"Failed to create Lighsail snapshot: {e}")
        return False, "", ""
    
@task(name="Clean Up Old Snapshots")
def cleanup_old_snapshots(instance_name: str, disk_name: str, region: str, retention_days: int) -> int:
    """CLean up old Lighsail snapshots based on retention policy."""
    logger = get_run_logger()
    try:
        logger.info("Cleaning up old snapshots (older than {retention_days} days...)")

        lightsail_client = boto3.client('lightsail', region_name=region)
        cutoff_date = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=retention_days)
        deleted_count = 0

        # Clean up instance snapshots
        instance_snapshots = lightsail_client.get_instance_snapshots()
        for snapshot in instance_snapshots['instanceSnapshots']:
            if (snapshot['fromInstanceName'] == instance_name and snapshot['createdAt'] < cutoff_date):
                logger.info(f"Deleting old instance snapshot: {snapshot['name']}")
                lightsail_client.delete_instance_snapshot(instanceSnapshotName=snapshot['name'])
                deleted_count += 1

        # Clean up disk snapshots
        disk_snapshots = lightsail_client.get_disk_snapshots()
        for snapshot in disk_snapshots['diskSnapshots']:
            if (snapshot['fromDiskName'] == disk_name and snapshot['createdAt'] < cutoff_date):
                logger.info(f"Deleting old disk snapshot: {snapshot['name']}")
                lightsail_client.delete_disk_snapshot(diskSnapshotName=snapshot['name'])
                deleted_count += 1
            
        logger.info(f"Deleted {deleted_count} old snapshots.")
        return deleted_count
    except Exception as e:
        logger.error(f"Failed to clean up old snapshots: {e}")
        return 0
    
@task(name="Send Discord Notification")
def send_discord_notification(
    webhook_url: str,
    status: str,
    message: str,
    details: Dict = None
) -> bool:
    """Send notificaiton to Discord webhook."""
    logger = get_run_logger()
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping notification")
        return False

    try:
        logger.info(f"Sending Discord notification: {status}")

        # Set emoji based on status
        emoji = "✅" if status == "SUCCESS" else "❌"

        # Build the embed
        timestamp = datetime.datetime.now().isoformat()
        color = 5763719 if status == "SUCCESS" else 15548997 # Green or Red

        payload = {
            "embeds": [
                {
                    "title": f"{emoji} Kroni Survival - {status}",
                    "description": message,
                    "color" : color,
                    "timestamp": timestamp,
                    "footer": {
                        "text": "Kroni Survival Minecraft Server"
                    }
                }
            ]
        }

        # Add fields if details are provided
        if details:
            fields = []
            for key, value in details.items():
                fields.append({
                    "name": key,
                    "value": str(value),
                    "inline": True
                })
                payload["embeds"][0]["fields"] = fields
        
        # Send the notification
        response = requests.post(
            webhook_url,
            data=json.dumps(payload),
            headers={"Content-Type": "application/json"}
        )

        response.raise_for_status()
        logger.info("Discord notification sent successfully")
        return True
    
    except Exception as e:
        logger.error(f"Failed to send Discord notification: {e}")
        return False
    
@task(name="Kroni Survival Backup Flow")
def backup_flow(config: Optional[Dict] = None):
    """
    Main flow for backing up the Minecraft server.

    Args:
        config: COnfiguration dictionary (optional)
    """

    logger = get_run_logger()
    logger.info("Starting Kroni Survival Backup Flow...")

    # Merge default config with provided config
    cfg = DEFAULT_CONFIG.copy()
    if config:
        cfg.update(config)
    
    # Check if server is running
    server_was_running = check_server_status()

    try:
        # Stop the server if it's running
        if server_was_running:
            stop_minecraft_server()
        
        # Create world backup
        backup_path = create_world_backup(cfg["world_path"])
        backup_success = backup_path is not None

        # Upload backup to S3
        s3_success = False
        if backup_success:
            s3_success = upload_to_s3(backup_path, cfg["s3_bucket"], cfg["region"])

        # Create Lightsail snapshots
        snapshot_success, instance_snapshot, disk_snapshot = create_lightsail_snapshots(
            cfg["instance_name"],
            cfg["disk_name"],
            cfg["region"]
        )

        # Clean up old snapshots
        deleted_snapshots = cleanup_old_snapshots(
            cfg["instance_name"],
            cfg["disk_name"],
            cfg["region"],
            cfg["retention_days"]
        )

        # Prepare notification details
        notification_details = {
            "World Backup": "Success" if s3_success else "Failed",
            "Lightsail Snapshots": "Success" if snapshot_success else "Failed",
            "Deleted Snapshots": deleted_snapshots,
            "Timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }

        # Determine overall status
        if s3_success and snapshot_success:
            status = "SUCCESS"
            message = "Backup and snapshots created successfully!"

        else:
            status = "PARTIAL SUCCESS" if s3_success or snapshot_success else "FAILURE"
            message = "Minecraft server backup completed with some issues."

        # Send notification
        send_discord_notification(
            cfg["discord_webhook_url"],
            status,
            message,
            notification_details
        )

        logger.info(f"Backup flow completed with status: {status}")
        return status
    finally:
        # Always restart server if it was running before
        if server_was_running:
            start_minecraft_server()
    
if __name__ == "__main__":
    # Load config from env var or command line
    config = {}

    # Env variables take precedence
    for key in DEFAULT_CONFIG:
        env_key = f"KRONI_{key.upper()}"
        if env_key in os.environ:
            config[key] = os.environ[env_key]
        

    # Run the flow
    backup_flow(config)