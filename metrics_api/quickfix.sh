#!/bin/bash
# Quick fix for Minecraft Metrics API container detection

set -e

echo "=== Quick Fix for Minecraft Metrics API ==="
cd /opt/metrics-api

# Backup current file
cp metrics_api_server.py metrics_api_server.py.bak

# Fix Docker socket permissions
sudo chmod 666 /var/run/docker.sock

# Fix docker-compose.yml
if grep -q '# - /var/run/docker.sock:/var/run/docker.sock' docker-compose.yml; then
  sed -i 's|# - /var/run/docker.sock:/var/run/docker.sock|- /var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml
fi

# Modify the get_minecraft_metrics function to properly detect running containers
sed -i '/async def get_minecraft_metrics/,/return metrics/{s/if result.returncode == 0 and result.stdout.strip():/if container_check.returncode == 0 and container_check.stdout.strip(): status = container_check.stdout.strip() logger.info(f"Container status: {status}") if "Up" in status: metrics["status"] = "running"/; s/metrics\["status"\] = "running"//; s/metrics\["status"\] = "stopped"//; s/# Get Docker stats for Minecraft container/# First check if the container is running container_check = subprocess.run( ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Status}}"], capture_output=True, text=True, check=False, ) # Initialize metrics metrics = { "status": "stopped", "uptime": 0, "timestamp": datetime.now().isoformat() } # Check if the container is running if container_check.returncode == 0 and "Up" in container_check.stdout: metrics["status"] = "running" # Get Docker stats for Minecraft container/;}' metrics_api_server.py

# Restart the container
docker-compose down
docker-compose up -d --build

# Wait for API to restart
echo "Waiting for API to restart..."
sleep 5

# Test if fix worked
API_KEY=$(grep "API Key:" api_key.txt | cut -d' ' -f3)
echo "Testing with API key: ${API_KEY:0:8}..."

RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" http://localhost:8000/api/v1/minecraft/metrics)
echo "API Response: $RESPONSE"

if echo "$RESPONSE" | grep -q '"status":"running"'; then
  echo "✅ Success! API now correctly reports Minecraft server as running."
else
  echo "❌ Fix didn't work. Manual intervention required."
  echo "Error details:"
  docker logs --tail 20 minecraft-metrics-api
fi 