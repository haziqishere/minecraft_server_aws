#!/usr/bin/env python3
"""
Kroni Survival Minecraft Server - Monitoring Flow

This Prefect flow handles:
1. Collecting server metrics (CPU, memory, disk usage)
2. Sending metrics to Discord webhook
3. Monitoring Minecraft server status
4. Tracking Minecraft world size growth

Run this script directly to execute the flow or schedule with Prefect
"""

import os
import sys
import datetime
import json
import time
import platform
import psutil
from pathlib import Path
from typing import Dict, Optional

# Import Prefect modules
from prefect import flow, task, get_run_logger
import requests

# Import utility functions
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils.server_utils import (
    get_ec2_config,
    check_container_status,
    get_directory_size,
    get_system_metrics_remote
)

# Default config
DEFAULT_CONFIG = {
    "instance_name": "kroni-survival-server",
    "region": "ap-southeast-1",
    "discord_webhook_url": "https://discord.com/api/webhooks/1358469232613920998/gy6XxAzecIF3-uSh1WUu8LjbX4VtRHqncSmv2KB1IW5Y4rI5o1Dv_M5QMKuQvZCMvjm9",
    "minecraft_container_name": "minecraft-server",
    "data_path": "/data",
    "world_path": "/data/world"
}

@task(name="Check Minecraft Server Status")
def check_server_status(container_name: str = "minecraft-server") -> bool:
    """Check if the Minecraft server is running"""
    logger = get_run_logger()
    logger.info(f"Checking Minecraft server status...")
    
    # Get EC2 config if we're in remote mode
    if os.environ.get("KRONI_DEV_MODE", "").lower() == "true":
        ec2_config = get_ec2_config()
        return check_container_status(container_name, ssh_config=ec2_config, logger=logger)
    
    # Otherwise check locally
    return check_container_status(container_name, logger=logger)

@task(name="Get System Metrics")
def get_system_metrics() -> Dict:
    """Collect system metrics including CPU, memory, and disk usage"""
    logger = get_run_logger()
    logger.info(f"Collecting system metrics...")
    
    # Check if we're in remote mode
    if os.environ.get("KRONI_DEV_MODE", "").lower() == "true":
        ec2_config = get_ec2_config()
        host = ec2_config.get("EC2_HOST")
        user = ec2_config.get("SSH_USER")
        port = ec2_config.get("SSH_PORT", "22")
        
        # If we have EC2 details, get metrics remotely
        if host and user:
            logger.info(f"Getting system metrics from remote host {host}")
            return get_system_metrics_remote(host, user, port)
    
    # Otherwise get metrics locally
    try:
        # Get CPU usage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Get memory usage
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        
        # Get disk usage for root and data partition
        root_disk = psutil.disk_usage('/')
        root_disk_percent = root_disk.percent
        
        data_disk = None
        data_disk_percent = None
        
        # Check if data partition exists
        if os.path.exists('/data'):
            data_disk = psutil.disk_usage('/data')
            data_disk_percent = data_disk.percent
        
        # Check load averages (Linux only)
        load_avg = None
        if platform.system() == "Linux":
            load_avg = os.getloadavg()
        
        # Docker stats for Minecraft container
        docker_stats = None
        try:
            import subprocess
            result = subprocess.run(
                ["docker", "stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}"],
                capture_output=True,
                text=True,
                check=True,
            )
            
            # Parse docker stats output
            for line in result.stdout.splitlines():
                if "minecraft-server" in line:
                    parts = line.split(',')
                    if len(parts) >= 4:
                        docker_stats = {
                            "cpu_percent": parts[1].strip(),
                            "mem_usage": parts[2].strip(),
                            "mem_percent": parts[3].strip()
                        }
                    break
        except Exception as e:
            logger.error(f"Failed to get Docker stats: {e}")
        
        metrics = {
            "timestamp": datetime.datetime.now().isoformat(),
            "system": {
                "cpu_percent": cpu_percent,
                "memory_percent": memory_percent,
                "memory_total_mb": round(memory.total / (1024 * 1024), 2),
                "memory_used_mb": round(memory.used / (1024 * 1024), 2),
                "root_disk_percent": root_disk_percent,
                "root_disk_total_gb": round(root_disk.total / (1024 * 1024 * 1024), 2),
                "root_disk_used_gb": round(root_disk.used / (1024 * 1024 * 1024), 2),
            }
        }
        
        if load_avg:
            metrics["system"]["load_avg_1min"] = load_avg[0]
            metrics["system"]["load_avg_5min"] = load_avg[1]
            metrics["system"]["load_avg_15min"] = load_avg[2]
        
        if data_disk and data_disk_percent:
            metrics["system"]["data_disk_percent"] = data_disk_percent
            metrics["system"]["data_disk_total_gb"] = round(data_disk.total / (1024 * 1024 * 1024), 2)
            metrics["system"]["data_disk_used_gb"] = round(data_disk.used / (1024 * 1024 * 1024), 2)
        
        if docker_stats:
            metrics["minecraft"] = docker_stats
        
        logger.info(f"Collected system metrics successfully")
        return metrics
    
    except Exception as e:
        logger.error(f"Failed to collect system metrics: {e}")
        return {
            "timestamp": datetime.datetime.now().isoformat(),
            "error": str(e)
        }

@task(name="Get World Size")
def get_world_size(world_path: str) -> Optional[float]:
    """Get the size of the Minecraft world directory in GB"""
    logger = get_run_logger()
    
    # Use the utility function to get world size
    return get_directory_size(world_path)

@task(name="Send Discord Notification")
def send_metrics_to_discord(
    webhook_url: str,
    metrics: Dict,
    world_size: Optional[float],
    server_running: bool
) -> bool:
    """Send server metrics to Discord webhook"""
    logger = get_run_logger()
    logger.info("Sending metrics to Discord...")
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping notification")
        return False

    try:
        # Set emoji based on server status
        status_emoji = "✅" if server_running else "❌"
        server_status = "Running" if server_running else "Stopped"
        
        # Set colors based on resource usage levels
        cpu_percent = metrics["system"]["cpu_percent"]
        memory_percent = metrics["system"]["memory_percent"]
        disk_percent = metrics["system"]["root_disk_percent"]
        
        # Determine overall health 
        if cpu_percent > 90 or memory_percent > 90 or disk_percent > 90:
            color = 15548997  # Red
            health = "Critical"
        elif cpu_percent > 70 or memory_percent > 70 or disk_percent > 70:
            color = 16776960  # Yellow
            health = "Warning"
        else:
            color = 5763719  # Green
            health = "Good"

        # Format timestamp
        timestamp = datetime.datetime.now().isoformat()
        
        # Ensure all values are of the right types for formatting
        cpu_value = f"{float(cpu_percent):.1f}%" if isinstance(cpu_percent, (int, float)) else cpu_percent
        memory_used = metrics["system"]["memory_used_mb"]
        memory_used_str = f"{float(memory_used):.0f}" if isinstance(memory_used, (int, float)) else memory_used
        memory_value = f"{float(memory_percent):.1f}% ({memory_used_str} MB)"
        
        disk_percent_value = float(disk_percent) if isinstance(disk_percent, (int, float)) else float(disk_percent.replace('%', ''))
        disk_used = metrics["system"]["root_disk_used_gb"]
        disk_used_str = disk_used if isinstance(disk_used, str) else f"{float(disk_used):.1f}"
        disk_value = f"{disk_percent_value:.1f}% ({disk_used_str} GB)"
        
        # Build fields
        fields = [
            {
                "name": "Server Status",
                "value": f"{status_emoji} {server_status}",
                "inline": True
            },
            {
                "name": "Health",
                "value": health,
                "inline": True
            },
            {
                "name": "CPU Usage",
                "value": cpu_value,
                "inline": True
            },
            {
                "name": "Memory Usage",
                "value": memory_value,
                "inline": True
            },
            {
                "name": "Root Disk Usage",
                "value": disk_value,
                "inline": True
            }
        ]
        
        # Add data disk if available
        if "data_disk_percent" in metrics["system"]:
            data_percent = metrics["system"]["data_disk_percent"]
            data_used = metrics["system"]["data_disk_used_gb"]
            data_used_str = data_used if isinstance(data_used, str) else f"{float(data_used):.1f}"
            data_percent_value = float(data_percent) if isinstance(data_percent, (int, float)) else float(data_percent.replace('%', ''))
            
            fields.append({
                "name": "Data Disk Usage",
                "value": f"{data_percent_value:.1f}% ({data_used_str} GB)",
                "inline": True
            })
        
        # Add world size if available
        if world_size is not None:
            fields.append({
                "name": "World Size",
                "value": f"{world_size:.2f} GB",
                "inline": True
            })
        
        # Add load averages if available
        if "load_avg_1min" in metrics["system"]:
            load1 = metrics["system"]["load_avg_1min"]
            load5 = metrics["system"]["load_avg_5min"]
            load15 = metrics["system"]["load_avg_15min"]
            fields.append({
                "name": "Load Average",
                "value": f"{load1:.2f}, {load5:.2f}, {load15:.2f}",
                "inline": True
            })
        
        # Add Minecraft container stats if available
        if "minecraft" in metrics:
            fields.append({
                "name": "Minecraft CPU",
                "value": metrics["minecraft"]["cpu_percent"],
                "inline": True
            })
            fields.append({
                "name": "Minecraft Memory",
                "value": f"{metrics['minecraft']['mem_usage']} ({metrics['minecraft']['mem_percent']})",
                "inline": True
            })

        # Build the embed
        payload = {
            "embeds": [
                {
                    "title": "📊 Kroni Survival - Server Metrics",
                    "description": "Current server performance metrics",
                    "color": color,
                    "timestamp": timestamp,
                    "fields": fields,
                    "footer": {
                        "text": "Kroni Survival Minecraft Server"
                    }
                }
            ]
        }
        
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

@flow(name="Kroni Survival Server Monitoring")
def server_monitoring_flow(config: Optional[Dict] = None):
    """
    Main flow for monitoring the Minecraft server.

    Args:
        config: Configuration dictionary (optional)
    """
    logger = get_run_logger()
    logger.info("Starting Kroni Survival Server Monitoring Flow...")

    # Merge default config with provided config
    cfg = DEFAULT_CONFIG.copy()
    if config:
        cfg.update(config)
    
    try:
        # Check if server is running
        server_running = check_server_status(cfg["minecraft_container_name"])
        
        # Get system metrics
        metrics = get_system_metrics()
        
        # Get world size
        world_size = get_world_size(cfg["world_path"])
        
        # Send metrics to Discord
        if os.environ.get("DISCORD_WEBHOOK_ENABLED", "true").lower() == "true":
            send_metrics_to_discord(
                cfg["discord_webhook_url"],
                metrics,
                world_size,
                server_running
            )
        
        logger.info("Server monitoring flow completed successfully")
        return "SUCCESS"
    
    except Exception as e:
        logger.error(f"Server monitoring flow failed: {e}")
        return "FAILURE"

if __name__ == "__main__":
    # Load config from env var or command line
    config = {}

    # Env variables take precedence
    for key in DEFAULT_CONFIG:
        env_key = f"KRONI_{key.upper()}"
        if env_key in os.environ:
            config[key] = os.environ[env_key]

    # Run the flow
    server_monitoring_flow(config)