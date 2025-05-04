#!/bin/bash
# deploy_prefect.sh

# Usage: ./deploy_prefect.sh [command] [image_tag]
# Commands:
#   deploy - Deploy Prefect using Docker Compose
#   status - Check status of Prefect services
#   logs   - View logs of Prefect services
#   update - Update Prefect images and restart services
#   update-flows - Update flow files without rebuilding container
#   register - Register all flows with Prefect
# Options:
#   image_tag - Docker image tag to use (default: latest)
#   flow_name - (For update-flows) Specific flow file to update, e.g., backup_flow.py

COMMAND=${1:-status}
IMAGE_TAG=${2:-latest}
FLOW_NAME=${3:-""}

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
    
  update-flows)
    echo "Updating flow files without rebuilding container..."
    
    # Check if we're updating a specific flow or all flows
    if [ -n "$FLOW_NAME" ]; then
      # Update a specific flow
      FLOW_FILE="flows/$FLOW_NAME"
      if [ -f "$FLOW_FILE" ]; then
        FLOW_BASE=$(basename "$FLOW_NAME" .py)
        echo "Updating flow: $FLOW_BASE"
        
        # Copy flow file to the container
        docker cp $FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_NAME
        
        # Register the flow
        docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect work-pool create default -t process || echo 'Pool already exists'"
        docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_BASE -n $FLOW_BASE-deployment --pool default"
        
        echo "Flow $FLOW_BASE updated successfully!"
      else
        echo "Error: Flow file '$FLOW_FILE' not found!"
        exit 1
      fi
    else
      # Update all flows
      echo "Updating all flows..."
      
      # Create work pool if it doesn't exist
      docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Pool already exists'"
      
      # Copy all flow files and register them
      for FLOW_FILE in flows/*.py; do
        if [[ "$FLOW_FILE" != *"__init__.py"* && "$FLOW_FILE" != *"__pycache__"* ]]; then
          FLOW_NAME=$(basename "$FLOW_FILE")
          FLOW_BASE=$(basename "$FLOW_FILE" .py)
          
          echo "Updating flow: $FLOW_BASE"
          docker cp $FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_NAME
          docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_BASE -n $FLOW_BASE-deployment --pool default"
        fi
      done
      
      echo "All flows updated successfully!"
    fi
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
    
    # Create work pool if it doesn't exist
    docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Pool already exists'"
    
    # Register all flows
    echo "Registering all flows..."
    for FLOW_FILE in flows/*.py; do
      if [[ "$FLOW_FILE" != *"__init__.py"* && "$FLOW_FILE" != *"__pycache__"* ]]; then
        FLOW_NAME=$(basename "$FLOW_FILE")
        FLOW_BASE=$(basename "$FLOW_FILE" .py)
        
        echo "Deploying flow: $FLOW_BASE"
        docker cp $FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_NAME
        docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_BASE -n $FLOW_BASE-deployment --pool default"
      fi
    done
    ;;
    
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: $0 [deploy|status|logs|update|restart|update-flows|register] [image_tag] [flow_name]"
    exit 1
    ;;
esac