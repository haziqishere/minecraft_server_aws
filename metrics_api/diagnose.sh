#!/bin/bash
# Diagnostic script for troubleshooting Minecraft Metrics API

set -e
echo "=== Minecraft Metrics API Diagnostic Tool ==="
echo "Current date: $(date)"

# Check Docker and container status
echo -e "\n=== Docker Status ==="
docker --version
echo "Docker socket: $(ls -la /var/run/docker.sock)"
echo "Docker socket permissions: $(stat -c '%a %u:%g' /var/run/docker.sock)"
echo "Current user: $(id)"

echo -e "\n=== Container Status ==="
docker ps -a
echo
docker inspect minecraft-server | grep Status -A 3
echo
docker inspect minecraft-metrics-api | grep Status -A 3

# Check API container setup
echo -e "\n=== API Container Setup ==="
echo "Container environment variables:"
docker exec minecraft-metrics-api env | grep -E 'METRICS|MINECRAFT'

# Check Docker socket access from within container
echo -e "\n=== Testing Docker access from API container ==="
echo "Running docker ps within container:"
docker exec minecraft-metrics-api docker ps || echo "Failed to run docker within container!"

# Check metrics directly
echo -e "\n=== Direct Container Status Check ==="
docker ps --filter "name=minecraft-server" --format "{{.Status}}"

# Check world paths
echo -e "\n=== Checking Minecraft World Paths ==="
for path in "/data/world" "/minecraft_data/world" "/var/lib/docker/volumes/minecraft-server_data/_data/world"; do
  if [ -d "$path" ]; then
    echo "Path exists: $path (Size: $(du -sh $path 2>/dev/null || echo 'Permission denied'))"
  else
    echo "Path does not exist: $path"
  fi
done

# Check world inside Minecraft container
echo -e "\n=== Checking World Inside Container ==="
docker exec minecraft-server ls -la /data 2>/dev/null || echo "Failed to list /data in container"
docker exec minecraft-server ls -la /data/world 2>/dev/null || echo "Failed to list /data/world in container"

# Test API endpoints
echo -e "\n=== Testing API Endpoints ==="
API_KEY=$(grep "API Key:" /opt/metrics-api/api_key.txt | cut -d' ' -f3)
echo "Health endpoint:"
curl -s "http://localhost:8000/api/v1/health"
echo -e "\n\nMinecraft metrics endpoint:"
curl -s -H "X-API-Key: $API_KEY" "http://localhost:8000/api/v1/minecraft/metrics" | python -m json.tool

# Check API container logs
echo -e "\n=== API Container Logs (last 20 lines) ==="
docker logs --tail 20 minecraft-metrics-api

echo -e "\n=== End of Diagnostic Report ==="
echo "To update the API container, run: docker-compose up -d --build in /opt/metrics-api" 