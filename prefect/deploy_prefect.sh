#!/bin/bash
# deploy_prefect.sh

# Usage: ./deploy_prefect.sh [command] [flow_name]
# Commands:
#   deploy - Deploy Prefect using Docker Compose
#   status - Check status of Prefect services
#   logs   - View logs of Prefect services
#   update-flows - Update flow files without rebuilding container
#   register - Register all flows with Prefect
# Options:
#   flow_name - (For update-flows) Specific flow file to update, e.g., backup_flow.py

COMMAND=${1:-status}
FLOW_NAME=${2:-""}

# Prefect now uses the official image
export PREFECT_IMAGE="prefecthq/prefect:3-latest"

echo "Using Prefect image: ${PREFECT_IMAGE}"

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
    if [ "$2" == "server" ]; then
      docker-compose logs -f prefect-server
    elif [ "$2" == "worker" ]; then
      docker-compose logs -f prefect-worker
    else
      docker-compose logs -f
    fi
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
        
        # Check if the flow file contains the specified flow function
        if ! grep -q "@flow.*def $FLOW_BASE" "$FLOW_FILE"; then
          echo "Warning: File $FLOW_FILE might not contain a flow function named '$FLOW_BASE'"
          echo "Looking for any flow function in the file..."
          FLOW_FUNC=$(grep -o "@flow.*def \w\+" "$FLOW_FILE" | head -1 | awk '{print $NF}')
          
          if [ -n "$FLOW_FUNC" ]; then
            echo "Found flow function: $FLOW_FUNC"
            FLOW_BASE=$FLOW_FUNC
          else
            echo "Error: No flow function found in $FLOW_FILE!"
            exit 1
          fi
        fi
        
        # Copy flow file to the container
        echo "Copying $FLOW_FILE to prefect-server:/opt/prefect/flows/$FLOW_NAME"
        docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
        
        # Register the flow
        echo "Creating work pool if it doesn't exist..."
        docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Pool already exists'"
        
        echo "Deploying flow $FLOW_NAME:$FLOW_BASE..."
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
          
          # Check for flow functions in the file
          FLOW_FUNCS=$(grep -o "@flow.*def \w\+" "$FLOW_FILE" | awk '{print $NF}')
          
          if [ -z "$FLOW_FUNCS" ]; then
            echo "Warning: No flow functions found in $FLOW_NAME, skipping..."
            continue
          fi
          
          echo "Copying $FLOW_FILE to container..."
          docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
          
          # Deploy each flow function found in the file
          for FLOW_FUNC in $FLOW_FUNCS; do
            echo "Deploying flow: $FLOW_NAME:$FLOW_FUNC"
            docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"
          done
        fi
      done
      
      echo "All flows updated successfully!"
    fi
    ;;
    
  register)
    echo "Registering flows with Prefect..."
    # Wait for server to be ready
    MAX_ATTEMPTS=20
    ATTEMPT=0
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      if docker exec prefect-server curl -s http://localhost:4200/api/health | grep -q "healthy"; then
        echo "Server is healthy, registering flows..."
        break
      fi
      
      ATTEMPT=$((ATTEMPT+1))
      echo "Waiting for server to be ready... Attempt $ATTEMPT/$MAX_ATTEMPTS"
      sleep 5
      
      # After 10 attempts, check the logs
      if [ $ATTEMPT -eq 10 ]; then
        echo "Server still not ready, checking logs:"
        docker logs prefect-server --tail=50
      fi
    done
    
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
      echo "Server failed to become ready after $MAX_ATTEMPTS attempts."
      exit 1
    fi
    
    # Create work pool if it doesn't exist
    docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Pool already exists'"
    
    # Register all flows with proper flow detection
    echo "Registering all flows..."
    for FLOW_FILE in flows/*.py; do
      if [[ "$FLOW_FILE" != *"__init__.py"* && "$FLOW_FILE" != *"__pycache__"* ]]; then
        FLOW_NAME=$(basename "$FLOW_FILE")
        
        # Check for flow functions in the file
        FLOW_FUNCS=$(grep -o "@flow.*def \w\+" "$FLOW_FILE" | awk '{print $NF}')
        
        if [ -z "$FLOW_FUNCS" ]; then
          echo "Warning: No flow functions found in $FLOW_NAME, skipping..."
          continue
        fi
        
        echo "Copying $FLOW_FILE to container..."
        docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
        
        # Deploy each flow function found in the file
        for FLOW_FUNC in $FLOW_FUNCS; do
          echo "Deploying flow: $FLOW_NAME:$FLOW_FUNC"
          docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"
        done
      fi
    done
    
    # Start worker if not already running
    echo "Starting worker if not already running..."
    if ! docker ps | grep -q prefect-worker; then
      echo "Worker not running, starting it..."
      docker-compose up -d prefect-worker
    else
      echo "Worker is already running."
    fi
    ;;
    
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: $0 [deploy|status|logs|restart|update-flows|register] [flow_name]"
    exit 1
    ;;
esac