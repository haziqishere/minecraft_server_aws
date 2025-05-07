#!/bin/bash
#
# Deploy script for Minecraft Metrics API server
#

set -e

# Default values
METRICS_API_KEY=${METRICS_API_KEY:-$(openssl rand -hex 16)}
METRICS_API_PORT=${METRICS_API_PORT:-8000}

# Show usage
usage() {
  echo "Usage: $0 [OPTIONS] COMMAND"
  echo
  echo "Commands:"
  echo "  deploy    Deploy the Metrics API server"
  echo "  update    Update the Metrics API server"
  echo "  stop      Stop the Metrics API server"
  echo "  logs      Show logs from the Metrics API server"
  echo "  status    Show status of the Metrics API server"
  echo
  echo "Options:"
  echo "  --api-key KEY  Set the API key (default: randomly generated)"
  echo "  --port PORT    Set the port (default: 8000)"
  echo
  exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)
      METRICS_API_KEY="$2"
      shift 2
      ;;
    --port)
      METRICS_API_PORT="$2"
      shift 2
      ;;
    deploy|update|stop|logs|status)
      COMMAND="$1"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

# Check required command
if [ -z "$COMMAND" ]; then
  usage
fi

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed"
  exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
  echo "Error: Docker Compose is not installed"
  exit 1
fi

# Create metrics API server directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd "$SCRIPT_DIR"

# Export environment variables
export METRICS_API_KEY
export METRICS_API_PORT

# Functions for commands
deploy() {
  echo "Deploying Metrics API server..."
  
  # Check if the server is already running
  if docker ps | grep -q minecraft-metrics-api; then
    echo "Metrics API server is already running. Use 'update' instead."
    exit 1
  fi
  
  # Make sure the metrics_api_server.py file is in the current directory
  if [ ! -f "./metrics_api_server.py" ]; then
    echo "Error: metrics_api_server.py file not found"
    exit 1
  fi
  
  # Run docker-compose to build and start the container
  docker-compose up -d --build
  
  # Check if the container is running
  if docker ps | grep -q minecraft-metrics-api; then
    echo "Metrics API server deployed successfully"
    echo "API Key: $METRICS_API_KEY"
    echo "URL: http://localhost:$METRICS_API_PORT/api/v1/health"
  else
    echo "Error: Failed to deploy Metrics API server"
    docker-compose logs
    exit 1
  fi
}

update() {
  echo "Updating Metrics API server..."
  
  # Update the container
  docker-compose up -d --build
  
  # Check if the container is running
  if docker ps | grep -q minecraft-metrics-api; then
    echo "Metrics API server updated successfully"
  else
    echo "Error: Failed to update Metrics API server"
    docker-compose logs
    exit 1
  fi
}

stop() {
  echo "Stopping Metrics API server..."
  docker-compose down
  echo "Metrics API server stopped"
}

logs() {
  echo "Showing logs from Metrics API server..."
  docker-compose logs --follow
}

status() {
  echo "Checking status of Metrics API server..."
  
  # Check if the container is running
  if docker ps | grep -q minecraft-metrics-api; then
    echo "Metrics API server is running"
    
    # Get the container ID
    CONTAINER_ID=$(docker ps -q -f name=minecraft-metrics-api)
    
    # Get container details
    echo "Container ID: $CONTAINER_ID"
    echo "Status: $(docker inspect -f '{{.State.Status}}' $CONTAINER_ID)"
    echo "Running since: $(docker inspect -f '{{.State.StartedAt}}' $CONTAINER_ID)"
    echo "API URL: http://localhost:$METRICS_API_PORT/api/v1/health"
    
    # Check health
    if curl -s http://localhost:$METRICS_API_PORT/api/v1/health | grep -q "healthy"; then
      echo "Health check: OK"
    else
      echo "Health check: FAILED"
    fi
  else
    echo "Metrics API server is not running"
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