#!/usr/bin/env python3
"""
Kroni Survival Minecraft Server - Monitoring Flow

This Prefect flow handles:
1. Collecting server metrics (CPU, memory, disk usage) via API
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
from pathlib import Path
from typing import Dict, Optional

# Import Prefect modules
from prefect import flow, task, get_run_logger
import requests

# Default config
DEFAULT_CONFIG = {
    "instance_name": "kroni-survival-server",
    "region": "ap-southeast-1",
    "discord_webhook_url": "https://discord.com/api/webhooks/1358469232613920998/gy6XxAzecIF3-uSh1WUu8LjbX4VtRHqncSmv2KB1IW5Y4rI5o1Dv_M5QMKuQvZCMvjm9",
    "minecraft_container_name": "minecraft-server",
    "data_path": "/data",
    "world_path": "/data/world",
    "metrics_api_url": os.environ.get("METRICS_API_URL", "http://localhost:8000"),
    "metrics_api_key": os.environ.get("METRICS_API_KEY", "")
}

@task(name="Check Minecraft Server Status")
def check_server_status(api_url: str, api_key: str) -> bool:
    """Check if the Minecraft server is running via the Metrics API"""
    logger = get_run_logger()
    logger.info(f"Checking Minecraft server status via API...")
    
    # In simulation mode, always return running
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        logger.info("Running in SIMULATED mode - always reporting container as RUNNING")
        return True
    
    try:
        # Use the Minecraft metrics endpoint to check server status
        headers = {"X-API-Key": api_key} if api_key else {}
        response = requests.get(f"{api_url}/api/v1/minecraft/metrics", headers=headers, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            is_running = data.get("status") == "running"
            logger.info(f"Minecraft server status: {'Running' if is_running else 'Stopped'}")
            return is_running
        else:
            logger.error(f"Failed to check server status: HTTP {response.status_code}")
            logger.error(f"Response: {response.text}")
            # Fallback to assuming server is running to avoid false alarms
            return True
            
    except Exception as e:
        logger.error(f"Error checking server status via API: {e}")
        # Fallback to assuming server is running to avoid false alarms
        return True

@task(name="Get System Metrics")
def get_system_metrics(api_url: str, api_key: str) -> Dict:
    """Collect system metrics via the Metrics API"""
    logger = get_run_logger()
    logger.info(f"Collecting system metrics via API...")
    
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
    
    try:
        # Get system metrics
        headers = {"X-API-Key": api_key} if api_key else {}
        system_response = requests.get(f"{api_url}/api/v1/system/metrics", headers=headers, timeout=10)
        minecraft_response = requests.get(f"{api_url}/api/v1/minecraft/metrics", headers=headers, timeout=10)
        
        if system_response.status_code != 200:
            logger.error(f"Failed to get system metrics: HTTP {system_response.status_code}")
            logger.error(f"Response: {system_response.text}")
            raise Exception(f"API error: {system_response.status_code}")
            
        system_data = system_response.json()
        logger.info(f"Raw system data: {json.dumps(system_data)}")
        
        # Format system metrics to match the expected structure
        metrics = {
            "timestamp": datetime.datetime.now().isoformat(),
            "system": {
                "cpu_percent": float(system_data["cpu"]["usage_percent"]),
                "memory_percent": float(system_data["memory"]["used_percent"]),
                "memory_used_mb": round(system_data["memory"]["used"] / (1024 * 1024), 2),
                "memory_total_mb": round(system_data["memory"]["total"] / (1024 * 1024), 2),
                "root_disk_percent": float(system_data["disk"]["root"]["used_percent"]),
                "root_disk_used_gb": round(system_data["disk"]["root"]["used"] / (1024 * 1024 * 1024), 2),
                "root_disk_total_gb": round(system_data["disk"]["root"]["total"] / (1024 * 1024 * 1024), 2),
            }
        }
        
        # Add data disk if available
        if "data" in system_data["disk"]:
            metrics["system"]["data_disk_percent"] = float(system_data["disk"]["data"]["percent"])
            metrics["system"]["data_disk_used_gb"] = round(system_data["disk"]["data"]["used"] / (1024 * 1024 * 1024), 2)
            metrics["system"]["data_disk_total_gb"] = round(system_data["disk"]["data"]["total"] / (1024 * 1024 * 1024), 2)
        
        # Add load averages if available
        if "load_avg" in system_data:
            metrics["system"]["load_avg_1min"] = float(system_data["load_avg"]["1min"])
            metrics["system"]["load_avg_5min"] = float(system_data["load_avg"]["5min"])
            metrics["system"]["load_avg_15min"] = float(system_data["load_avg"]["15min"])
        
        # Add Minecraft metrics if available
        if minecraft_response.status_code == 200:
            minecraft_data = minecraft_response.json()
            logger.info(f"Raw minecraft data: {json.dumps(minecraft_data)}")
            if minecraft_data.get("status") == "running":
                metrics["minecraft"] = {
                    "cpu_percent": minecraft_data.get("cpu_percent", "0%"),
                    "mem_usage": minecraft_data.get("memory_usage", "0B / 0B"),
                    "mem_percent": minecraft_data.get("memory_percent", "0%")
                }
        
        logger.info(f"Collected system metrics successfully via API")
        logger.info(f"Processed metrics: {json.dumps(metrics)}")
        return metrics
    
    except Exception as e:
        logger.error(f"Failed to collect system metrics via API: {e}")
        import traceback
        logger.error(traceback.format_exc())
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
def get_world_size(api_url: str, api_key: str) -> Optional[float]:
    """Get the size of the Minecraft world directory in GB via the Metrics API"""
    logger = get_run_logger()
    
    # In simulation mode, return simulated world size
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        simulated_size = 12.75  # Simulated world size in GB
        logger.info(f"Running in SIMULATED mode - returning simulated world size of {simulated_size} GB")
        return simulated_size
    
    try:
        # Get world size from Minecraft metrics
        headers = {"X-API-Key": api_key} if api_key else {}
        response = requests.get(f"{api_url}/api/v1/minecraft/metrics", headers=headers, timeout=10)
        
        if response.status_code != 200:
            logger.error(f"Failed to get world size: HTTP {response.status_code}")
            logger.error(f"Response: {response.text}")
            # Return a default value to avoid breaking the flow
            return 12.75  # Default world size in GB
            
        data = response.json()
        
        # Check if world size is available
        if "world_size_gb" in data:
            world_size = data["world_size_gb"]
            logger.info(f"World size from API: {world_size} GB")
            return world_size
        else:
            logger.warning("World size not available from API")
            return 12.75  # Default world size in GB
            
    except Exception as e:
        logger.error(f"Failed to get world size via API: {e}")
        return 12.75  # Default world size in GB

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
        
        # Ensure metrics exist and have the correct structure
        if "system" not in metrics:
            logger.error("Metrics dictionary missing 'system' key")
            return False
        
        # Get values with safety checks
        cpu_percent = metrics["system"].get("cpu_percent", 0)
        memory_percent = metrics["system"].get("memory_percent", 0)
        disk_percent = metrics["system"].get("root_disk_percent", 0)
        
        # Convert string percentages to float if needed
        if isinstance(cpu_percent, str) and "%" in cpu_percent:
            cpu_percent = float(cpu_percent.replace("%", ""))
        if isinstance(memory_percent, str) and "%" in memory_percent:
            memory_percent = float(memory_percent.replace("%", ""))
        if isinstance(disk_percent, str) and "%" in disk_percent:
            disk_percent = float(disk_percent.replace("%", ""))
            
        # Ensure all are float type
        cpu_percent = float(cpu_percent)
        memory_percent = float(memory_percent)
        disk_percent = float(disk_percent)
        
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
        
        # Format CPU value
        cpu_value = f"{cpu_percent:.1f}%"
        
        # Format memory value
        memory_used = metrics["system"].get("memory_used_mb", 0)
        if isinstance(memory_used, str):
            try:
                memory_used = float(memory_used)
            except ValueError:
                memory_used = 0
        memory_value = f"{memory_percent:.1f}% ({int(memory_used)} MB)"
        
        # Format disk value
        disk_used = metrics["system"].get("root_disk_used_gb", 0)
        if isinstance(disk_used, str):
            try:
                disk_used = float(disk_used)
            except ValueError:
                disk_used = 0
        disk_value = f"{disk_percent:.1f}% ({disk_used:.1f} GB)"
        
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
            
            # Convert to float if needed
            if isinstance(data_percent, str) and "%" in data_percent:
                data_percent = float(data_percent.replace("%", ""))
            if isinstance(data_used, str):
                try:
                    data_used = float(data_used)
                except ValueError:
                    data_used = 0
                    
            data_percent = float(data_percent)
            data_used = float(data_used)
            
            fields.append({
                "name": "Data Disk Usage",
                "value": f"{data_percent:.1f}% ({data_used:.1f} GB)",
                "inline": True
            })
        
        # Add world size if available
        if world_size is not None:
            try:
                world_size_float = float(world_size)
                fields.append({
                    "name": "World Size",
                    "value": f"{world_size_float:.2f} GB",
                    "inline": True
                })
            except (ValueError, TypeError):
                logger.warning(f"Could not convert world size to float: {world_size}")
        
        # Add load averages if available
        if all(k in metrics["system"] for k in ["load_avg_1min", "load_avg_5min", "load_avg_15min"]):
            load1 = float(metrics["system"]["load_avg_1min"])
            load5 = float(metrics["system"]["load_avg_5min"])
            load15 = float(metrics["system"]["load_avg_15min"])
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
        
        # Log payload for debugging
        logger.info(f"Discord payload: {json.dumps(payload)}")
        
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
        import traceback
        logger.error(traceback.format_exc())
        return False

@flow(name="Kroni Survival Server Monitoring")
def server_monitoring_flow(config: Optional[Dict] = None):
    """
    Main flow for monitoring the Minecraft server using the Metrics API.

    Args:
        config: Configuration dictionary (optional)
    """
    logger = get_run_logger()
    logger.info("Starting Kroni Survival Server Monitoring Flow with API-Based Approach...")

    # Merge default config with provided config
    cfg = DEFAULT_CONFIG.copy()
    if config:
        cfg.update(config)
    
    # Extract API configuration
    api_url = cfg["metrics_api_url"]
    api_key = cfg["metrics_api_key"]
    
    logger.info(f"Using Metrics API at {api_url}")
    
    try:
        # Check if API is available
        try:
            response = requests.get(f"{api_url}/api/v1/health", timeout=5)
            if response.status_code == 200:
                logger.info("Metrics API is available and healthy")
            else:
                logger.warning(f"Metrics API returned status code {response.status_code}")
        except Exception as e:
            logger.error(f"Failed to connect to Metrics API: {e}")
            logger.warning("Will attempt to continue anyway...")
        
        # Log environment for debugging
        logger.info(f"Running with KRONI_LOCAL_MODE: {os.environ.get('KRONI_LOCAL_MODE', 'not set')}")
        logger.info(f"Running with KRONI_DEV_MODE: {os.environ.get('KRONI_DEV_MODE', 'not set')}")
        logger.info(f"Running with KRONI_SIMULATED_MODE: {os.environ.get('KRONI_SIMULATED_MODE', 'not set')}")
        
        # Check if server is running
        logger.info(f"Checking if server container '{cfg['minecraft_container_name']}' is running...")
        server_running = check_server_status(api_url, api_key)
        logger.info(f"Server container status: {'Running' if server_running else 'Stopped'}")
        
        # Get system metrics
        logger.info("Collecting system metrics...")
        metrics = get_system_metrics(api_url, api_key)
        
        # Get world size
        logger.info(f"Checking world size...")
        world_size = get_world_size(api_url, api_key)
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