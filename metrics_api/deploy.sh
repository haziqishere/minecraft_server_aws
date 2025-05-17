#!/bin/bash

# Deploy the Minecraft Metrics API server
# This script can be run manually on the server

# Set default port if not provided
METRICS_API_PORT="${METRICS_API_PORT:-8000}"

# Generate an API key if not provided
if [ -z "$METRICS_API_KEY" ]; then
  METRICS_API_KEY=$(openssl rand -hex 16)
  echo "Generated new API key: $METRICS_API_KEY"
fi

# Create directory if it doesn't exist
sudo mkdir -p /opt/metrics-api
sudo chown "$(whoami)":"$(whoami)" /opt/metrics-api
cd /opt/metrics-api || exit 1

# Create environment file with API key
echo "METRICS_API_KEY=$METRICS_API_KEY" > .env
echo "METRICS_API_PORT=$METRICS_API_PORT" >> .env

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
  echo "Docker not found. Installing it..."
  sudo amazon-linux-extras install docker -y
  sudo systemctl enable docker
  sudo systemctl start docker
  sudo usermod -aG docker "$(whoami)"
  echo "Docker has been installed. You may need to log out and back in for group changes to take effect."
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
  echo "Docker Compose not found. Installing it..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
fi

# Check files are present
if [ ! -f "docker-compose.yml" ] || [ ! -f "Dockerfile" ] || [ ! -f "metrics_api_server.py" ] || [ ! -f "requirements.txt" ]; then
  echo "Warning: Some required files are missing. Cannot proceed."
  ls -la
  exit 1
fi

# Add docker group to current user if not already in it
if ! groups | grep -q docker; then
  echo "Adding current user to docker group..."
  sudo usermod -aG docker "$(whoami)"
  echo "You may need to log out and back in for group changes to take effect."
  echo "Alternatively, run the docker commands with sudo."
fi

# Check if docker-compose.yml has docker socket access
if ! grep -q '/var/run/docker.sock:/var/run/docker.sock' docker-compose.yml; then
  echo "Enabling Docker socket access for container metrics..."
  if grep -q '# - /var/run/docker.sock:/var/run/docker.sock' docker-compose.yml; then
    # Uncomment the line if it exists but is commented
    sed -i 's|# - /var/run/docker.sock:/var/run/docker.sock|- /var/run/docker.sock:/var/run/docker.sock|g' docker-compose.yml
  else
    # Add the line if it doesn't exist
    sed -i '/volumes:/a \ \ \ \ - /var/run/docker.sock:/var/run/docker.sock' docker-compose.yml
  fi
fi

# Ensure Docker socket has proper permissions
if [ -e "/var/run/docker.sock" ]; then
  echo "Checking Docker socket permissions..."
  if ! [ -r "/var/run/docker.sock" ] || ! [ -w "/var/run/docker.sock" ]; then
    echo "Fixing Docker socket permissions..."
    sudo chmod 666 /var/run/docker.sock
  fi
fi

# Stop any running container
echo "Stopping any existing containers..."
docker-compose down || true

# Build and start the container
echo "Building and starting container..."
docker-compose up -d --build

# Check if container started
echo "Container status:"
docker-compose ps

# Save API key to file for future reference
echo "API Key: $METRICS_API_KEY" > api_key.txt
echo "API URL: http://localhost:$METRICS_API_PORT/api/v1" >> api_key.txt

# Wait for the API to be ready
echo "Waiting for API to be ready..."
for i in {1..10}; do
  if curl -s "http://localhost:$METRICS_API_PORT/api/v1/health" | grep -q healthy; then
    echo "API is healthy!"
    echo "API is running on port $METRICS_API_PORT with key $METRICS_API_KEY"
    echo "You can check its status at: http://localhost:$METRICS_API_PORT/api/v1/health"
    exit 0
  fi
  echo "Waiting for API to be ready... Attempt $i/10"
  sleep 2
done

echo "API failed to respond to health checks. Check logs with 'docker logs minecraft-metrics-api'"
exit 1 