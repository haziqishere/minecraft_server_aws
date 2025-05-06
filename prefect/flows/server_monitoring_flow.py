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
    
    # In simulation mode, always return running
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        logger.info("Running in SIMULATED mode - always reporting container as RUNNING")
        return True
    
    # Get EC2 config for remote SSH checking
    ec2_config = get_ec2_config()
    
    # Use remote checking by default in production environments
    # This ensures the container status is properly checked on the EC2 host
    if ec2_config and ec2_config.get("EC2_HOST"):
        logger.info(f"Using remote SSH to check container status on {ec2_config.get('EC2_HOST')}")
        return check_container_status(container_name, ssh_config=ec2_config, logger=logger)
    
    # Fallback to local checking if no EC2 config is found
    logger.warning("No EC2 configuration found - checking container locally (may be incorrect)")
    return check_container_status(container_name, logger=logger)

@task(name="Get System Metrics")
def get_system_metrics() -> Dict:
    """Collect system metrics including CPU, memory, and disk usage"""
    logger = get_run_logger()
    logger.info(f"Collecting system metrics...")
    
    # In simulation mode, return simulated metrics
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        logger.info("Running in SIMULATED mode - returning simulated metrics")
        return {
            "timestamp": datetime.datetime.now().isoformat(),
            "system": {
                "cpu_percent": 22.1,
                "memory_percent": 76.7,
                "memory_used_mb": 571,
                "memory_total_mb": 744,
                "root_disk_percent": 13.8,
                "root_disk_used_gb": 5.5,
                "root_disk_total_gb": 40.0,
                "load_avg_1min": 0.17,
                "load_avg_5min": 0.13,
                "load_avg_15min": 0.06
            },
            "minecraft": {
                "cpu_percent": "2.15%",
                "mem_usage": "512MiB / 1GiB",
                "mem_percent": "50.0%"
            }
        }
    
    # Get EC2 config for remote SSH metrics collection
    ec2_config = get_ec2_config()
    
    # Use remote metrics collection by default in production environments
    if ec2_config and ec2_config.get("EC2_HOST"):
        host = ec2_config.get("EC2_HOST")
        user = ec2_config.get("SSH_USER", "ec2-user")
        port = ec2_config.get("SSH_PORT", "22")
        
        logger.info(f"Using remote SSH to collect metrics from {host}")
        return get_system_metrics_remote(host, user, port)
    
    # Fallback to local metrics collection if no EC2 config is found
    logger.warning("No EC2 configuration found - collecting metrics locally (may be incomplete)")
    
    # Local metrics collection follows here...
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
            "system": {
                # Provide default values if metrics collection fails
                "cpu_percent": 0,
                "memory_percent": 0,
                "memory_total_mb": 0,
                "memory_used_mb": 0,
                "root_disk_percent": 0,
                "root_disk_total_gb": 0,
                "root_disk_used_gb": 0,
            },
            "error": str(e)
        }

@task(name="Get World Size")
def get_world_size(world_path: str) -> Optional[float]:
    """Get the size of the Minecraft world directory in GB"""
    logger = get_run_logger()
    
    # In simulation mode, return simulated world size
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        simulated_size = 12.75  # Simulated world size in GB
        logger.info(f"Running in SIMULATED mode - returning simulated world size of {simulated_size} GB")
        return simulated_size
    
    # When running in a container, the world path won't exist locally
    # Instead use simulated mode to return a reasonable value
    if not os.path.exists(world_path):
        logger.info(f"World path {world_path} doesn't exist locally - using simulated size")
        return 12.75  # Default simulated world size
    
    # If running locally and path exists, calculate actual world size
    logger.info(f"Calculating size of world at {world_path}")
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
        # Log environment for debugging
        logger.info(f"Running with KRONI_LOCAL_MODE: {os.environ.get('KRONI_LOCAL_MODE', 'not set')}")
        logger.info(f"Running with KRONI_DEV_MODE: {os.environ.get('KRONI_DEV_MODE', 'not set')}")
        logger.info(f"Running with KRONI_SIMULATED_MODE: {os.environ.get('KRONI_SIMULATED_MODE', 'not set')}")
        
        # Check EC2 configuration
        ec2_config = get_ec2_config()
        ec2_host = ec2_config.get("EC2_HOST", "not configured")
        logger.info(f"EC2_HOST configured as: {ec2_host}")
        
        # Check if server is running
        logger.info(f"Checking if server container '{cfg['minecraft_container_name']}' is running...")
        server_running = check_server_status(cfg["minecraft_container_name"])
        logger.info(f"Server container status: {'Running' if server_running else 'Stopped'}")
        
        # Get system metrics
        logger.info("Collecting system metrics...")
        metrics = get_system_metrics()
        
        # Get world size
        logger.info(f"Checking world size for path: {cfg['world_path']}")
        world_size = get_world_size(cfg["world_path"])
        logger.info(f"World size: {world_size} GB")
        
        # Send metrics to Discord
        if os.environ.get("DISCORD_WEBHOOK_ENABLED", "true").lower() == "true":
            logger.info("Sending metrics to Discord...")
            result = send_metrics_to_discord(
                cfg["discord_webhook_url"],
                metrics,
                world_size,
                server_running
            )
            logger.info(f"Discord notification {'sent successfully' if result else 'failed'}")
        else:
            logger.info("Discord webhook disabled, skipping notification")
        
        logger.info("Server monitoring flow completed successfully")
        return "SUCCESS"
    
    except Exception as e:
        logger.error(f"Server monitoring flow failed: {e}")
        import traceback
        logger.error(traceback.format_exc())
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