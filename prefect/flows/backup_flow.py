from prefect import flow, task
import datetime
import os
import tempfile
import boto3
import requests

from remote_executor import RemoteExecutor

@task(name="Check Minecraft Server Status")
def check_server_status(minecraft_host: str) -> bool:
    """ Check if Minecraft server is running """
    with RemoteExecutor(hostname=minecraft_host) as executor:
        return executor.check_docker_container("minecraft-server")

@task(name="Stop Minecraft Server")
def stop_minecraft_server(minecraft_host: str) -> bool:
    """ Stop Minecraft Server """
    with RemoteExecutor(hostname=minecraft_host) as executor:
        return executor.docker_stop_container("minecraft-server")
    
@task(name="Start Minecraft Server")
def start_minecraft_server(minecraft_host: str) -> bool:
    """ Start Minecraft Server """
    with RemoteExecutor(hostname=minecraft_host) as executor:
        return executor.docker_start_container("minecraft-server")
    
@task(name="Create World Backup")
def create_world_backup(minecraft_host: str, world_path: str) -> str:
    """Create a tar.gz backup of the Minecraft world directory"""
    with RemoteExecutor(hostname=minecraft_host) as executor:
        return executor.create_backup(world_path)
    
@task(name="Download Backup")
def download_backup(minecraft_host: str, remote_backup_path: str) -> str:
    """ Download the backup file from the remote server """
    with tempfile.TemporaryDirectory() as temp_dir:
        local_backup_path = os.path.join(temp_dir, os.path.basename(remote_backup_path))

        with RemoteExecutor(hostname=minecraft_host) as executor:
            if executor.download_file(remote_backup_path, local_backup_path):
                return local_backup_path
            else:
                raise Exception(f"Failed to download backup file from {remote_backup_path}")
        return None

@task(name="Upload Backup to S3")
def upload_backup_to_s3(backup_path: str, bucket_name: str, region: str) -> bool:
    """ Upload the backup file to S3 """
    if not backup_path:
        raise ValueError("Could not find backup path")
        return False
    
    try:
        filename = os.path.basename(backup_path)
        
        s3_client = boto3.client("s3", region_name=region)
        s3_client.upload_file(backup_path, bucket_name, filename)
        
        return True

    except Exception as e:
        print(f"Failed to upload backup to S3: {e}. Please check your AWS credentials.")
        return False
    
@task(name="Clean Up Remote Backup")
def cleanup_remote_backup(minecraft_host: str, remote_backup_path: str) -> bool:
    """ Remove the backup file from the Minecraft server"""
    with RemoteExecutor(hostname=minecraft_host) as executor:
        return executor.remove_file(remote_backup_path)
    
@task(name="Send Discord Notificaiton")
def send_discord_notification(webhook_url: str, status: str, message: str) -> bool:
    """ Send a notification to Discord Webhook """
    if not webhook_url:
        return False
    try:
        # Set color based on status (success: green, failure: red)
        color = 5763719 if status == "SUCCESS" else 15548997
        
        # Create payload with embed
        payload = {
            "embeds": [
                {
                    "title": f"{'✅' if status == 'SUCCESS' else '❌'} Kroni Survival - {status}",
                    "description": message,
                    "color": color,
                    "timestamp": datetime.datetime.now().isoformat(),
                    "footer": {
                        "text": "Kroni Survival Minecraft Server"
                    }
                }
            ]
        }
        
        # Send the notification
        response = requests.post(webhook_url, json=payload)
        response.raise_for_status()
        
        return True
    except Exception as e:
        print(f"Failed to send Discord notification: {e}")
        return False
    
@flow(name="Minecraf World Backup Flow")
def backup_flow(config: dict=None):
    """
        Main flow for backing up the Minecraft world.
    
    Args:
        config: Configuration dictionary with the following keys:
            - minecraft_host: Hostname or IP of the Minecraft server
            - world_path: Path to the Minecraft world directory
            - s3_bucket: Name of the S3 bucket for backups
            - region: AWS region
            - discord_webhook_url: Discord webhook URL for notifications
    """

    # Default configuration
    default_config = {
        "minecraft_host": "kroni-survival-server",
        "world_path": "/data/world",
        "s3_bucket": "kroni-survival-backups-secure",
        "region": "ap-southeast-1",
        "discord_webhook_url": "https://discord.com/api/webhooks/1368209320755331194/NladTXDI7FlfzIRorCcUxR_sllrgh2gao9IdZQaUZlTnIxtefGVYa32P5Dsbu7Hxr2Lq",
    }

    # Merge provided config with defaults
    cfg = default_config.copy()
    if config:
        cfg.update(config)

    # Check if server is running
    server_was_running = check_server_status(cfg["minecraft_host"])

    try:
        # Stop the Minecraft server if it was running
        if server_was_running:
            stop_minecraft_server(cfg["minecraft_host"])

        # Create a backup on the Minecraft server
        remote_backup_path = create_world_backup(cfg["minecraft_host"], cfg["world_path"])
        backup_created = remote_backup_path is not None

        # Download the backup file to Prefect server
        local_backup_path = None
        if backup_created:
            local_backup_path = download_backup(cfg["minecraft_host"], remote_backup_path)

        # Upload the backup file to S3
        s3_success = False
        if local_backup_path:
            s3_success = upload_backup_to_s3(local_backup_path, cfg["s3_bucket"], cfg["region"])

            # Clean up the remote backup file
            cleanup_remote_backup(cfg["minecraft_host"], remote_backup_path)

        # Determine status and message
        if backup_created and local_backup_path and s3_success:
            status = "SUCCESS"
            message = f"Minecraft world backup completed successfully! Backup stored in s3://{cfg['s3_bucket']}/{os.path.basename(local_backup_path)}"
        else:
            status = "FAILURE"
            message = "Minecraft world backup failed."

            if not backup_created:
                message += "Failed to create backup on the Minecraft server."
            elif not local_backup_path:
                message += "Failed to download backup from the Minecraft server."
            elif not s3_success:
                message += "Failed to upload backup to S3."
            
        # Send Discord notification
        send_discord_notification(cfg["discord_webhook_url"], status, message)

        return status
    
    finally:
        # Always restart the server if it was running before
        if server_was_running:
            start_minecraft_server(cfg["minecraft_host"])