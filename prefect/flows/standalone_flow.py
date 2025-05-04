#!/usr/bin/env python3
"""
Standalone flow that doesn't require Prefect server connection
This can be used as a template for all your flows
"""

import os
import sys
import datetime
import logging
import subprocess
import json
import tempfile
import boto3
import requests
from pathlib import Path

# Configure basic logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("standalone-flow")

# Default config
DEFAULT_CONFIG = {
    "minecraft_host": "kroni-survival-server",
    "world_path": "/data/world",
    "s3_bucket": "kroni-survival-backups-secure",
    "region": "ap-southeast-1",
    "discord_webhook_url": "",
    "instance_name": "kroni-survival-server",
    "disk_name": "kroni-survival-data",
    "retention_days": 30,
}

def run_command(command):
    """Run a shell command and return the output"""
    logger.info(f"Running command: {command}")
    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        logger.error(f"Command failed with code {result.returncode}: {result.stderr}")
    return result.returncode, result.stdout, result.stderr

def send_discord_notification(webhook_url, status, message, details=None):
    """Send a notification to Discord webhook"""
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping notification")
        return False

    try:
        logger.info(f"Sending Discord notification: {status}")
        
        # Set emoji based on status
        emoji = "✅" if status == "SUCCESS" else "❌"
        
        # Build the embed
        timestamp = datetime.datetime.now().isoformat()
        color = 5763719 if status == "SUCCESS" else 15548997  # Green or Red
        
        payload = {
            "embeds": [
                {
                    "title": f"{emoji} Kroni Survival - {status}",
                    "description": message,
                    "color": color,
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

def backup_flow():
    """Simple backup flow that runs in standalone mode"""
    logger.info("Starting Standalone Backup Flow")
    
    # Load config
    config = DEFAULT_CONFIG.copy()
    
    # Show what we're doing
    logger.info(f"Configuration: {json.dumps(config, indent=2)}")
    
    # Collect some basic system info
    system_info = {}
    _, stdout, _ = run_command("hostname")
    system_info["hostname"] = stdout.strip()
    
    _, stdout, _ = run_command("uname -a")
    system_info["system"] = stdout.strip()
    
    _, stdout, _ = run_command("df -h")
    system_info["disk_usage"] = stdout.strip()
    
    # Show the flows directory
    _, stdout, _ = run_command("ls -la /opt/prefect/flows")
    logger.info(f"Flow directory contents:\n{stdout}")
    
    # Send notification
    send_discord_notification(
        config["discord_webhook_url"],
        "SUCCESS",
        "Standalone flow test completed successfully!",
        {
            "Hostname": system_info["hostname"],
            "System": system_info["system"],
            "Time": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
    )
    
    return "SUCCESS"

if __name__ == "__main__":
    try:
        result = backup_flow()
        logger.info(f"Flow completed with status: {result}")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Flow failed with error: {e}")
        sys.exit(1) 