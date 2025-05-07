#!/bin/bash
#
# Deploy script for Minecraft Metrics API server
# This script should be run on the Minecraft server VM
#

set -e

# Default values
METRICS_API_KEY=${METRICS_API_KEY:-$(openssl rand -hex 16)}
METRICS_API_PORT=${METRICS_API_PORT:-8000}
INSTALL_DIR="/opt/metrics-api"

# Show usage
usage() {
  echo "Usage: $0 [deploy|update|stop|logs|status]"
  echo
  echo "Commands:"
  echo "  deploy    Deploy the Metrics API server"
  echo "  update    Update the Metrics API server"
  echo "  stop      Stop the Metrics API server"
  echo "  logs      Show logs from the Metrics API server"
  echo "  status    Show status of the Metrics API server"
  echo
  exit 1
}

# Check command
if [ $# -lt 1 ]; then
  usage
fi

COMMAND="$1"

# Create installation directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Create files
create_files() {
  echo "Creating Metrics API files..."
  
  # Create Python file
  cat > metrics_api_server.py << 'EOF'
#!/usr/bin/env python3
"""
Minecraft Server Metrics API

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
        # Get CPU usage
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # Get memory usage
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        memory_total = memory.total
        memory_used = memory.used
        
        # Get disk usage for root and data partition
        root_disk = psutil.disk_usage('/')
        root_disk_percent = root_disk.percent
        
        data_disk_info = None
        if os.path.exists('/data'):
            data_disk = psutil.disk_usage('/data')
            data_disk_info = {
                "total": data_disk.total,
                "used": data_disk.used,
                "percent": data_disk.percent
            }
        
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
        
        # Add data disk if available
        if data_disk_info:
            metrics["disk"]["data"] = data_disk_info
        
        return metrics
    except Exception as e:
        logger.error(f"Error getting system metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect system metrics: {str(e)}")

# Minecraft-specific metrics
@app.get("/api/v1/minecraft/metrics", dependencies=[Depends(get_api_key)])
async def get_minecraft_metrics():
    try:
        # Get Docker stats for Minecraft container
        result = subprocess.run(
            ["docker", "stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}", "minecraft-server"],
            capture_output=True,
            text=True,
            check=False,
        )
        
        # Initialize metrics
        metrics = {
            "status": "unknown",
            "uptime": 0,
            "timestamp": datetime.now().isoformat()
        }
        
        # Check if the container is running
        if result.returncode == 0 and result.stdout.strip():
            parts = result.stdout.strip().split(',')
            if len(parts) >= 4:
                metrics["status"] = "running"
                metrics["cpu_percent"] = parts[1].strip()
                metrics["memory_usage"] = parts[2].strip()
                metrics["memory_percent"] = parts[3].strip()
                
                # Get container uptime
                uptime_result = subprocess.run(
                    ["docker", "inspect", "--format", "{{.State.StartedAt}}", "minecraft-server"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                
                if uptime_result.returncode == 0 and uptime_result.stdout.strip():
                    started_at = datetime.fromisoformat(uptime_result.stdout.strip().replace('Z', '+00:00'))
                    uptime_seconds = (datetime.now() - started_at).total_seconds()
                    metrics["uptime"] = int(uptime_seconds)
        else:
            metrics["status"] = "stopped"
        
        # Get world size
        world_path = os.getenv("MINECRAFT_WORLD_PATH", "/data/world")
        if os.path.exists(world_path):
            # Calculate world size
            total_size = 0
            for dirpath, dirnames, filenames in os.walk(world_path):
                for f in filenames:
                    fp = os.path.join(dirpath, f)
                    if os.path.exists(fp):
                        total_size += os.path.getsize(fp)
            
            metrics["world_size_bytes"] = total_size
            metrics["world_size_mb"] = total_size / (1024 * 1024)
            metrics["world_size_gb"] = total_size / (1024 * 1024 * 1024)
        
        return metrics
    except Exception as e:
        logger.error(f"Error getting Minecraft metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect Minecraft metrics: {str(e)}")

# Player information endpoint
@app.get("/api/v1/minecraft/players", dependencies=[Depends(get_api_key)])
async def get_player_info():
    try:
        # Get player info from logs (this is a simplified approach)
        # A more robust implementation would use RCON to query the server
        player_info = {
            "online": 0,
            "max": 20,
            "players": []
        }
        
        # Attempt to get player count from docker logs
        try:
            # Check if server is running first
            status_result = subprocess.run(
                ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                check=False,
            )
            
            if status_result.returncode == 0 and "minecraft-server" in status_result.stdout:
                # Server is running, try to get player info from logs
                player_info["status"] = "online"
                
                # This is a simple approach, a better implementation would use RCON
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
                            player_name = line.split("[Server thread/INFO]: ")[1].split("[")[0].strip()
                            if player_name not in [p["name"] for p in player_info["players"]]:
                                player_info["players"].append({"name": player_name})
                        elif "left the game" in line:
                            player_name = line.split("[Server thread/INFO]: ")[1].split(" left")[0].strip()
                            player_info["players"] = [p for p in player_info["players"] if p["name"] != player_name]
                    
                    player_info["online"] = len(player_info["players"])
            else:
                player_info["status"] = "offline"
        except Exception as e:
            logger.error(f"Error getting player info from logs: {e}")
            player_info["error"] = str(e)
        
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
  
  # Create requirements.txt
  cat > requirements.txt << 'EOF'
fastapi==0.103.1
uvicorn==0.23.2
psutil==5.9.5
python-multipart==0.0.6
EOF
  
  # Create Docker Compose file
  cat > docker-compose.yml << 'EOF'
version: '3'

services:
  metrics-api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: minecraft-metrics-api
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - METRICS_API_KEY=${METRICS_API_KEY:-changeme}
      - METRICS_API_PORT=8000
      - MINECRAFT_WORLD_PATH=/data/world
      - TZ=UTC
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro  # For Docker stats
      - /data:/data:ro  # For world size calculation
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
EOF
  
  # Create Dockerfile
  cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY metrics_api_server.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Expose port
EXPOSE 8000

# Command to run
CMD ["python", "metrics_api_server.py"]
EOF
  
  # Create .env file
  cat > .env << EOF
METRICS_API_KEY=${METRICS_API_KEY}
METRICS_API_PORT=${METRICS_API_PORT}
EOF
  
  # Create systemd service file
  cat > metrics-api.service << 'EOF'
[Unit]
Description=Minecraft Metrics API Server
After=docker.service
Requires=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/metrics-api
EnvironmentFile=/opt/metrics-api/.env
ExecStart=/usr/local/bin/docker-compose up
ExecStop=/usr/local/bin/docker-compose down
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

install_dependencies() {
  echo "Installing dependencies..."
  
  # Check if Docker is installed
  if ! command -v docker >/dev/null 2>&1; then
    echo "Installing Docker..."
    sudo yum update -y
    sudo amazon-linux-extras install docker -y
    sudo service docker start
    sudo systemctl enable docker
  fi
  
  # Check if Docker Compose is installed
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  fi
  
  # Install dependencies for Python
  sudo yum install -y python3-pip
}

deploy() {
  echo "Deploying Metrics API server..."
  
  # Install dependencies
  install_dependencies
  
  # Create files
  create_files
  
  # Install systemd service
  sudo cp metrics-api.service /etc/systemd/system/
  sudo systemctl daemon-reload
  
  # Start the service
  sudo systemctl enable metrics-api
  sudo systemctl start metrics-api
  
  # Show status
  echo "Metrics API server deployed successfully"
  echo "API Key: $METRICS_API_KEY"
  echo "API URL: http://localhost:${METRICS_API_PORT}/api/v1/health"
  
  # Save API key to file for future reference
  echo "API Key: $METRICS_API_KEY" > api_key.txt
  echo "API URL: http://localhost:${METRICS_API_PORT}/api/v1" >> api_key.txt
  
  # Show status
  sudo systemctl status metrics-api
}

update() {
  echo "Updating Metrics API server..."
  
  # Create files (update them)
  create_files
  
  # Restart the service
  sudo systemctl restart metrics-api
  
  # Show status
  echo "Metrics API server updated successfully"
  sudo systemctl status metrics-api
}

stop() {
  echo "Stopping Metrics API server..."
  sudo systemctl stop metrics-api
  echo "Metrics API server stopped"
}

logs() {
  echo "Showing logs from Metrics API server..."
  sudo journalctl -u metrics-api -f
}

status() {
  echo "Checking status of Metrics API server..."
  sudo systemctl status metrics-api
  
  # Check API health
  curl -s http://localhost:${METRICS_API_PORT}/api/v1/health
  
  # Display API key
  if [ -f api_key.txt ]; then
    echo ""
    cat api_key.txt
  fi
}

# Run the command
case "$COMMAND" in
  deploy)
    deploy
    ;;
  update)
    update
    ;;
  stop)
    stop
    ;;
  logs)
    logs
    ;;
  status)
    status
    ;;
  *)
    usage
    ;;
esac 