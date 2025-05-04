#!/bin/bash
# deploy_prefect.sh

# Usage: ./deploy_prefect.sh [command] [image_tag]
# Commands:
#   deploy - Deploy Prefect using Docker Compose
#   status - Check status of Prefect services
#   logs   - View logs of Prefect services
#   update - Update Prefect images and restart services
# Options:
#   image_tag - Docker image tag to use (default: latest)

COMMAND=${1:-status}
IMAGE_TAG=${2:-latest}

# Set Docker image with username from environment or default
DOCKER_USERNAME=${DOCKER_USERNAME:-haziqishere}
export DOCKER_IMAGE="${DOCKER_USERNAME}/custom-prefect:${IMAGE_TAG}"

echo "Using Docker image: ${DOCKER_IMAGE}"

case $COMMAND in
  deploy)
    echo "Deploying Prefect services..."
    docker-compose down --remove-orphans
    docker-compose pull
    docker-compose up -d
    
    # Wait for services to start
    echo "Waiting for services to start..."
    sleep 10
    
    # Check service status
    docker-compose ps
    ;;
    
  status)
    echo "Checking Prefect services status..."
    docker-compose ps
    docker ps -a | grep prefect
    ;;

  logs)
    echo "Viewing Prefect logs..."
    if [ "$3" == "server" ]; then
      docker-compose logs -f prefect-server
    elif [ "$3" == "worker" ]; then
      docker-compose logs -f prefect-worker
    else
      docker-compose logs -f
    fi
    ;;
    
  update)
    echo "Updating Prefect services to version ${IMAGE_TAG}..."
    # Pull the latest image
    docker pull ${DOCKER_IMAGE}
    
    # Stop and remove containers
    docker-compose down --remove-orphans
    
    # Start with new image
    docker-compose up -d
    
    # Show running containers
    echo "Containers started:"
    docker-compose ps
    
    # Show logs to verify startup
    echo "Server logs:"
    docker-compose logs --tail=20 prefect-server
    ;;
    
  restart)
    echo "Restarting Prefect services..."
    docker-compose restart
    ;;
    
  register)
    echo "Registering flows with Prefect..."
    # Wait for server to be ready
    MAX_ATTEMPTS=10
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      if docker exec prefect-server curl -s http://localhost:4200/api/health | grep -q "healthy"; then
        echo "Server is healthy, registering flows..."
        break
      fi
      
      ATTEMPT=$((ATTEMPT+1))
      echo "Waiting for server to be ready... Attempt $ATTEMPT/$MAX_ATTEMPTS"
      sleep 5
    done
    
    # Register flows
    docker exec prefect-server bash -c 'cd /opt/prefect/flows && \
      prefect deployment run backup_flow.py:backup_flow -n scheduled-backup -q default && \
      prefect deployment run server_monitoring_flow.py:server_monitoring_flow -n server-monitoring -q default && \
      prefect deployment run snapshot_flow.py:snapshot_flow -n snapshot-flow -q default'
    ;;
    
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: $0 [deploy|status|logs|update|restart|register] [image_tag]"
    exit 1
    ;;
esac