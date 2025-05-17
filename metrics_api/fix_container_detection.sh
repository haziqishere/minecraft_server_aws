#!/bin/bash
# Fix script for Minecraft metrics API container detection

set -e

echo "=== Applying fix for Minecraft container status detection ==="

# Go to metrics-api directory
cd /opt/metrics-api

# Backup existing server file
if [ -f "metrics_api_server.py" ]; then
  echo "Backing up current metrics_api_server.py..."
  cp metrics_api_server.py metrics_api_server.py.bak
else
  echo "Error: metrics_api_server.py not found!"
  exit 1
fi

# Apply fix to the check container status code
echo "Applying fix to container status detection..."
sed -i 's|result = subprocess.run|# First check if the container is running\n        container_check = subprocess.run(\n            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Status}}"],\n            capture_output=True,\n            text=True,\n            check=False,\n        )\n        \n        # Initialize metrics\n        metrics = {\n            "status": "stopped",\n            "uptime": 0,\n            "timestamp": datetime.now().isoformat()\n        }\n        \n        # Check if the container is running based on the container_check\n        if container_check.returncode == 0 and container_check.stdout.strip():\n            status = container_check.stdout.strip()\n            logger.info(f"Minecraft container status: {status}")\n            if "Up" in status:\n                # Container is running\n                metrics["status"] = "running"\n                \n                # Get Docker stats for Minecraft container\n                result = subprocess.run|' metrics_api_server.py

# Remove any existing metrics initialization that would be duplicated
sed -i '/metrics = {\s*"status": "unknown",\s*"uptime": 0,\s*"timestamp": datetime.now().isoformat()\s*}/d' metrics_api_server.py

# Remove old status check logic
sed -i '/if result.returncode == 0 and result.stdout.strip():/,/metrics\["status"\] = "stopped"/c\\                if result.returncode == 0 and result.stdout.strip():' metrics_api_server.py

# Add Docker socket permission check
echo "Adding Docker socket permission check..."
if [ -e "/var/run/docker.sock" ]; then
  echo "Checking Docker socket permissions..."
  if ! [ -r "/var/run/docker.sock" ] || ! [ -w "/var/run/docker.sock" ]; then
    echo "Fixing Docker socket permissions..."
    sudo chmod 666 /var/run/docker.sock
  fi
fi

# Update docker-compose.yml to ensure Docker socket is mounted
if ! grep -q '/var/run/docker.sock:/var/run/docker.sock' docker-compose.yml || grep -q '# - /var/run/docker.sock:/var/run/docker.sock' docker-compose.yml; then
  echo "Enabling Docker socket access in docker-compose.yml..."
  sed -i 's|# - /var/run/docker.sock:/var/run/docker.sock|- /var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml
fi

# Restart the container
echo "Rebuilding and restarting the container..."
docker-compose down
docker-compose up -d --build

echo "Waiting for API to be ready..."
sleep 5

# Test if the fix worked
API_KEY=$(grep "API Key:" api_key.txt | cut -d' ' -f3)
RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8000/api/v1/minecraft/metrics")
SERVER_STATUS=$(echo "$RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

echo "New Minecraft server status: $SERVER_STATUS"

if [ "$SERVER_STATUS" = "running" ]; then
  echo "✅ Fix successful! The Minecraft server is now correctly detected as running."
else
  DOCKER_STATUS=$(docker ps --filter "name=minecraft-server" --format "{{.Status}}")
  if [[ "$DOCKER_STATUS" == *"Up"* ]]; then
    echo "❌ Fix failed. Container is running but API still reports '$SERVER_STATUS'."
    echo "Check logs for more details:"
    docker logs --tail 20 minecraft-metrics-api
  else
    echo "ℹ️ Minecraft server is not running ($DOCKER_STATUS), so 'stopped' status is correct."
  fi
fi

echo "=== Fix script completed ===" 