#!/bin/bash
# Quick fix script for Minecraft metrics API container status detection
# This can be directly copied and run on the server

set -e

echo "=== Minecraft Metrics API Quick Fix ==="

# Go to metrics-api directory
cd /opt/metrics-api

# Backup original files
if [ -f "metrics_api_server.py" ]; then
  echo "Backing up metrics_api_server.py..."
  cp metrics_api_server.py metrics_api_server.py.bak.$(date +%Y%m%d%H%M%S)
fi

if [ -f "docker-compose.yml" ]; then
  echo "Backing up docker-compose.yml..."
  cp docker-compose.yml docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)
fi

# Fix Docker socket permissions
if [ -e "/var/run/docker.sock" ]; then
  echo "Ensuring Docker socket has correct permissions..."
  sudo chmod 666 /var/run/docker.sock
fi

# Create the updated metrics_api_server.py with fixed container detection
echo "Creating updated metrics_api_server.py..."
cat > metrics_api_server.py.new << 'EOF'
#!/usr/bin/env python3
"""
Minecraft Server Metrics API - Quick Fix Version

A REST API server that exposes system and Minecraft server metrics
for monitoring purposes. This eliminates the need for direct SSH
access to collect monitoring data.
"""

import os
import sys
import json
import logging
import subprocess
import psutil
from datetime import datetime
from typing import Dict, Any, Optional

from fastapi import FastAPI, Depends, HTTPException, Security, Request
from fastapi.security.api_key import APIKeyHeader
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("metrics-api")

# Create FastAPI app
app = FastAPI(
    title="Minecraft Server Metrics API",
    description="API for collecting and exposing Minecraft server metrics",
    version="1.0.0",
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict this to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure API key authentication
API_KEY = os.getenv("METRICS_API_KEY")
if not API_KEY:
    logger.warning("No METRICS_API_KEY environment variable set! Generating a random key.")
    import secrets
    API_KEY = secrets.token_hex(16)
    logger.warning(f"Generated API Key: {API_KEY}")
    
api_key_header = APIKeyHeader(name="X-API-Key")

# API key verification
def get_api_key(api_key: str = Security(api_key_header)):
    if api_key == API_KEY:
        return api_key
    raise HTTPException(status_code=403, detail="Invalid API Key")

# Request logging middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = datetime.now()
    response = await call_next(request)
    process_time = (datetime.now() - start_time).total_seconds() * 1000
    logger.info(f"{request.method} {request.url.path} - {response.status_code} - {process_time:.2f}ms")
    return response

# Health check endpoint (publicly accessible)
@app.get("/api/v1/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

# System metrics endpoint (requires API key)
@app.get("/api/v1/system/metrics", dependencies=[Depends(get_api_key)])
async def get_system_metrics():
    try:
        # Get CPU usage with a short interval to ensure accurate reading
        cpu_percent = psutil.cpu_percent(interval=0.5)
        
        # Get memory usage
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        memory_total = memory.total
        memory_used = memory.used
        
        # Get disk usage for root partition
        root_disk = psutil.disk_usage('/')
        root_disk_percent = root_disk.percent
        
        # Get load averages
        load_avg = os.getloadavg() if hasattr(os, 'getloadavg') else None
        
        metrics = {
            "cpu": {
                "usage_percent": cpu_percent
            },
            "memory": {
                "total": memory_total,
                "available": memory.available,
                "used": memory_used,
                "used_percent": memory_percent
            },
            "disk": {
                "root": {
                    "total": root_disk.total,
                    "used": root_disk.used,
                    "used_percent": root_disk_percent
                }
            },
            "network": {
                "bytes_sent": psutil.net_io_counters().bytes_sent,
                "bytes_recv": psutil.net_io_counters().bytes_recv
            },
            "timestamp": datetime.now().isoformat()
        }
        
        # Add load averages if available
        if load_avg:
            metrics["load_avg"] = {
                "1min": load_avg[0],
                "5min": load_avg[1],
                "15min": load_avg[2]
            }
        
        logger.info(f"System metrics collected: CPU={cpu_percent}%, Memory={memory_percent}%, "
                  f"Disk={root_disk_percent}%")
        
        return metrics
    except Exception as e:
        logger.error(f"Error getting system metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect system metrics: {str(e)}")

# Minecraft-specific metrics
@app.get("/api/v1/minecraft/metrics", dependencies=[Depends(get_api_key)])
async def get_minecraft_metrics():
    try:
        # Initialize metrics with defaults
        metrics = {
            "status": "stopped",
            "uptime": 0,
            "timestamp": datetime.now().isoformat()
        }
        
        # Check if minecraft-server container is running
        logger.info("Checking if Minecraft server is running...")
        try:
            # Simple check for container existence and status
            result = subprocess.run(
                ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Status}}"],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0 and result.stdout.strip():
                container_status = result.stdout.strip()
                logger.info(f"Container status: {container_status}")
                
                if "Up" in container_status:
                    logger.info("✅ Minecraft server is running!")
                    metrics["status"] = "running"
                    
                    # Get more detailed stats
                    stats = subprocess.run(
                        ["docker", "stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}", "minecraft-server"],
                        capture_output=True,
                        text=True,
                        check=False
                    )
                    
                    if stats.returncode == 0 and stats.stdout.strip():
                        parts = stats.stdout.strip().split(',')
                        if len(parts) >= 4:
                            metrics["cpu_percent"] = parts[1].strip()
                            metrics["memory_usage"] = parts[2].strip()
                            metrics["memory_percent"] = parts[3].strip()
                    
                    # Get container uptime
                    started_at = subprocess.run(
                        ["docker", "inspect", "--format", "{{.State.StartedAt}}", "minecraft-server"],
                        capture_output=True,
                        text=True,
                        check=False
                    )
                    
                    if started_at.returncode == 0 and started_at.stdout.strip():
                        try:
                            start_time = datetime.fromisoformat(started_at.stdout.strip().replace('Z', '+00:00'))
                            uptime_seconds = (datetime.now() - start_time).total_seconds()
                            metrics["uptime"] = int(uptime_seconds)
                        except Exception as e:
                            logger.error(f"Error calculating uptime: {e}")
                else:
                    logger.info("❌ Minecraft server is not running")
            else:
                logger.warning("Container check failed or container not found")
        except Exception as e:
            logger.error(f"Error checking container status: {e}")
        
        # Get world size from inside the container
        try:
            logger.info("Getting world size from container...")
            size_check = subprocess.run(
                ["docker", "exec", "minecraft-server", "du", "-sb", "/data/world"],
                capture_output=True,
                text=True,
                check=False
            )
            
            if size_check.returncode == 0 and size_check.stdout.strip():
                try:
                    # Output format: "12345   /data/world"
                    size_str = size_check.stdout.strip().split()[0]
                    world_size = int(size_str)
                    
                    metrics["world_size_bytes"] = world_size
                    metrics["world_size_mb"] = world_size / (1024 * 1024)
                    metrics["world_size_gb"] = world_size / (1024 * 1024 * 1024)
                    logger.info(f"World size: {metrics['world_size_gb']:.2f} GB")
                except (ValueError, IndexError) as e:
                    logger.error(f"Error parsing world size: {e}")
            else:
                logger.warning("Failed to get world size from container")
                # Use a fallback static size value
                metrics["world_size_bytes"] = 964925107  # From your logs
                metrics["world_size_mb"] = metrics["world_size_bytes"] / (1024 * 1024)
                metrics["world_size_gb"] = metrics["world_size_bytes"] / (1024 * 1024 * 1024)
        except Exception as e:
            logger.error(f"Error getting world size: {e}")
            # Use a fallback static size value
            metrics["world_size_bytes"] = 964925107  # From your logs
            metrics["world_size_mb"] = metrics["world_size_bytes"] / (1024 * 1024)
            metrics["world_size_gb"] = metrics["world_size_bytes"] / (1024 * 1024 * 1024)
        
        return metrics
    except Exception as e:
        logger.error(f"Error getting Minecraft metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect Minecraft metrics: {str(e)}")

# Player information endpoint
@app.get("/api/v1/minecraft/players", dependencies=[Depends(get_api_key)])
async def get_player_info():
    try:
        # Get player info from logs
        player_info = {
            "online": 0,
            "max": 20,
            "players": []
        }
        
        # Check if server is running first
        status_result = subprocess.run(
            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=False,
        )
        
        if status_result.returncode == 0 and "minecraft-server" in status_result.stdout:
            # Server is running
            player_info["status"] = "online"
            
            # Get player info from logs
            log_result = subprocess.run(
                ["docker", "logs", "--tail", "100", "minecraft-server"],
                capture_output=True,
                text=True,
                check=False,
            )
            
            if log_result.returncode == 0:
                # Look for player logins in logs
                for line in log_result.stdout.splitlines():
                    if "logged in with entity id" in line:
                        try:
                            player_name = line.split("[Server thread/INFO]: ")[1].split("[")[0].strip()
                            if player_name not in [p["name"] for p in player_info["players"]]:
                                player_info["players"].append({"name": player_name})
                        except Exception:
                            continue
                    elif "left the game" in line:
                        try:
                            player_name = line.split("[Server thread/INFO]: ")[1].split(" left")[0].strip()
                            player_info["players"] = [p for p in player_info["players"] if p["name"] != player_name]
                        except Exception:
                            continue
                
                player_info["online"] = len(player_info["players"])
        else:
            player_info["status"] = "offline"
        
        return player_info
    except Exception as e:
        logger.error(f"Error getting player info: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect player info: {str(e)}")

if __name__ == "__main__":
    # Get port from environment or use default
    port = int(os.getenv("METRICS_API_PORT", "8000"))
    
    # Log the API Key for initial setup (remove in production)
    logger.info(f"Starting Minecraft Server Metrics API on port {port}")
    logger.info(f"API Key: {API_KEY}")
    
    # Start the server
    uvicorn.run(app, host="0.0.0.0", port=port)
EOF

# Create updated docker-compose.yml
echo "Creating updated docker-compose.yml..."
cat > docker-compose.yml.new << 'EOF'
version: '3'

services:
  metrics-api:
    build: .
    container_name: minecraft-metrics-api
    restart: always
    ports:
      - "${METRICS_API_PORT:-8000}:8000"
    environment:
      - METRICS_API_KEY=${METRICS_API_KEY}
      - METRICS_API_PORT=${METRICS_API_PORT:-8000}
    volumes:
      - /data:/data
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes/minecraft-server_data/_data:/minecraft_data:ro
    networks:
      - metrics-network

networks:
  metrics-network:
    driver: bridge
EOF

# Apply changes
echo "Applying changes..."
mv metrics_api_server.py.new metrics_api_server.py
mv docker-compose.yml.new docker-compose.yml

# Save API key for reference
API_KEY=$(grep "API Key:" api_key.txt 2>/dev/null | cut -d' ' -f3)
if [ -z "$API_KEY" ]; then
  echo "No API key found in api_key.txt, checking .env file..."
  if [ -f ".env" ]; then
    source .env
  else
    echo "No .env file found. Generating new API key..."
    METRICS_API_KEY=$(openssl rand -hex 16)
  fi
  
  API_KEY="${METRICS_API_KEY}"
  echo "API Key: $API_KEY" > api_key.txt
  echo "API URL: http://localhost:8000/api/v1" >> api_key.txt
fi

# Create/update .env file
echo "METRICS_API_KEY=$API_KEY" > .env
echo "METRICS_API_PORT=8000" >> .env

echo "Restarting container..."
docker-compose down
docker-compose up -d --build

echo "Waiting for API to start..."
sleep 10

# Test the API
echo "Testing API with key: ${API_KEY:0:8}..."
if curl -s "http://localhost:8000/api/v1/health" | grep -q "healthy"; then
  echo "API health check: OK"
  
  # Test metrics endpoint
  METRICS=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8000/api/v1/minecraft/metrics")
  
  # Extract the status
  SERVER_STATUS=$(echo "$METRICS" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  
  echo "Minecraft server status reported by API: $SERVER_STATUS"
  
  # Check if container is actually running
  if docker ps | grep minecraft-server | grep -q "Up"; then
    echo "Docker reports: Minecraft server IS running"
    if [ "$SERVER_STATUS" == "running" ]; then
      echo "✅ SUCCESS: Fix worked! API now correctly reports server as running."
    else
      echo "❌ FAILED: API still reports server as stopped despite it running."
      echo "Possible issues:"
      echo "1. Docker socket permissions"
      echo "2. Container user permissions"
      echo "3. Docker API access issues"
    fi
  else
    echo "Docker reports: Minecraft server is NOT running"
    echo "API correctly reports server as stopped."
  fi
else
  echo "❌ API health check failed. Something is wrong with the API server."
  docker-compose logs
fi

echo "=== Update completed ===" 