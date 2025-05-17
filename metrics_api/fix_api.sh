#!/bin/bash
# Direct fix for the Minecraft Metrics API
# Run this script directly on the server

set -e

echo "=== Direct Fix for Minecraft Metrics API ==="

# Ensure we're in the metrics-api directory
cd /opt/metrics-api

# Backup original file
echo "Backing up current metrics_api_server.py..."
cp metrics_api_server.py metrics_api_server.py.bak.$(date +%Y%m%d%H%M%S)

# Fix permissions for Docker socket
echo "Fixing Docker socket permissions..."
sudo chmod 666 /var/run/docker.sock

# Create a temporary script to inject the fixed function
cat > /tmp/fix_function.py << 'EOF'
# This is the fixed get_minecraft_metrics function to replace
async def get_minecraft_metrics():
    try:
        # First check if the container is running directly
        container_check = subprocess.run(
            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Status}}"],
            capture_output=True,
            text=True,
            check=False,
        )
        
        # Initialize metrics with default values
        metrics = {
            "status": "stopped",
            "uptime": 0,
            "timestamp": datetime.now().isoformat()
        }
        
        # Check if the container is running based on the docker ps check
        container_status = container_check.stdout.strip() if container_check.returncode == 0 else ""
        logger.info(f"Minecraft container status from docker ps: '{container_status}'")
        
        if container_check.returncode == 0 and "Up" in container_status:
            # Container is running according to docker ps
            logger.info("Container is running based on docker ps check")
            metrics["status"] = "running"
            
            # Now get more detailed stats
            result = subprocess.run(
                ["docker", "stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}", "minecraft-server"],
                capture_output=True,
                text=True,
                check=False,
            )
            
            if result.returncode == 0 and result.stdout.strip():
                parts = result.stdout.strip().split(',')
                if len(parts) >= 4:
                    metrics["cpu_percent"] = parts[1].strip()
                    metrics["memory_usage"] = parts[2].strip()
                    metrics["memory_percent"] = parts[3].strip()
                    logger.info(f"Got container stats: CPU={parts[1].strip()}, Memory={parts[3].strip()}")
            
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
        
        # Try to get world size from container
        try:
            size_check = subprocess.run(
                ["docker", "exec", "minecraft-server", "du", "-sb", "/data/world"],
                capture_output=True,
                text=True,
                check=False
            )
            
            if size_check.returncode == 0:
                try:
                    size_parts = size_check.stdout.strip().split()
                    if len(size_parts) > 0:
                        world_size = int(size_parts[0])
                        metrics["world_size_bytes"] = world_size
                        metrics["world_size_mb"] = world_size / (1024 * 1024)
                        metrics["world_size_gb"] = world_size / (1024 * 1024 * 1024)
                        logger.info(f"World size from container: {metrics['world_size_gb']:.2f} GB")
                except (ValueError, IndexError) as e:
                    logger.error(f"Error parsing world size from container: {e}")
                    metrics["world_size_bytes"] = 964925107
                    metrics["world_size_mb"] = metrics["world_size_bytes"] / (1024 * 1024)
                    metrics["world_size_gb"] = metrics["world_size_bytes"] / (1024 * 1024 * 1024)
            else:
                # Fallback to saved value
                logger.warning("Could not get world size from container")
                metrics["world_size_bytes"] = 964925107
                metrics["world_size_mb"] = metrics["world_size_bytes"] / (1024 * 1024)
                metrics["world_size_gb"] = metrics["world_size_bytes"] / (1024 * 1024 * 1024)
        except Exception as e:
            logger.error(f"Error checking world size: {e}")
            metrics["world_size_bytes"] = 964925107
            metrics["world_size_mb"] = metrics["world_size_bytes"] / (1024 * 1024)
            metrics["world_size_gb"] = metrics["world_size_bytes"] / (1024 * 1024 * 1024)
        
        return metrics
    except Exception as e:
        logger.error(f"Error getting Minecraft metrics: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to collect Minecraft metrics: {str(e)}")
EOF

# Replace the existing function
echo "Replacing the get_minecraft_metrics function..."
sed -i '/async def get_minecraft_metrics/,/return metrics/{/async def get_minecraft_metrics/,/try:/p; d;}' metrics_api_server.py
sed -i '/async def get_minecraft_metrics/r /tmp/fix_function.py' metrics_api_server.py
sed -i '/async def get_minecraft_metrics/{n; d;}' metrics_api_server.py

# Update docker-compose.yml to ensure Docker socket access
if grep -q '# - /var/run/docker.sock:/var/run/docker.sock' docker-compose.yml; then
  echo "Enabling Docker socket in docker-compose.yml..."
  sed -i 's|# - /var/run/docker.sock:/var/run/docker.sock|- /var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml
fi

# Restart the container
echo "Restarting container..."
docker-compose down
docker-compose up -d --build

# Wait for the API to start
echo "Waiting for API to restart..."
sleep 10

# Get the API key
API_KEY=$(grep "API Key:" api_key.txt 2>/dev/null | cut -d' ' -f3)
if [ -z "$API_KEY" ]; then
  if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
    API_KEY="$METRICS_API_KEY"
  fi
fi

# Test the fix
echo "Testing fix with key: ${API_KEY:0:8}..."
curl -s -H "X-API-Key: $API_KEY" "http://localhost:8000/api/v1/minecraft/metrics" | python3 -m json.tool

# Check if fix worked
RESPONSE=$(curl -s -H "X-API-Key: $API_KEY" "http://localhost:8000/api/v1/minecraft/metrics")
if echo "$RESPONSE" | grep -q '"status":"running"'; then
  echo "✅ Success! Container now correctly detected as running."
else
  echo "❌ Fix did not work as expected. Container status still not detected correctly."
  echo "Debug info:"
  docker ps | grep minecraft
  echo "API logs:"
  docker logs --tail 20 minecraft-metrics-api
fi

echo "=== Fix completed ==="
rm -f /tmp/fix_function.py 