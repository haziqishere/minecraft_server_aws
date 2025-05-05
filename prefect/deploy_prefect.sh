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

# Get the server hostname/IP for external connections
# Set default PREFECT_HOST to public IP or hostname if available, otherwise use localhost
if [ -z "$PREFECT_HOST" ]; then
  # Try to determine public IP from EC2 metadata
  PREFECT_HOST=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
  
  if [ -z "$PREFECT_HOST" ]; then
    # Try to get hostname from system
    PREFECT_HOST=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
  fi
  
  export PREFECT_HOST
  echo "Auto-detected PREFECT_HOST: ${PREFECT_HOST}"
fi

echo "Using Prefect image: ${PREFECT_IMAGE}"
echo "Using Prefect host for external connections: ${PREFECT_HOST}"

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
        
        # Print file content for debugging
        echo "File content (first 15 lines):"
        head -n 15 "$FLOW_FILE"
        
        # Check if the flow file contains the specified flow function using improved pattern
        if ! grep -E "@flow(\s*|\([^)]*\))\s*\n*\s*def\s+$FLOW_BASE" "$FLOW_FILE" > /dev/null; then
          echo "Warning: File $FLOW_FILE might not contain a flow function named '$FLOW_BASE'"
          echo "Looking for any flow function in the file..."
          
          # First try with the enhanced pattern
          FLOW_FUNC=$(grep -E "@flow(\s*|\([^)]*\))\s*\n*\s*def\s+([a-zA-Z0-9_]+)" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | head -1 | cut -d ' ' -f2)
          
          # If no matches, try a more permissive pattern
          if [ -z "$FLOW_FUNC" ]; then
              echo "Trying alternate flow detection method..."
              FLOW_FUNC=$(grep -A 1 "@flow" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | head -1 | cut -d ' ' -f2)
          fi
          
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
        docker exec -e PREFECT_API_URL=http://${PREFECT_HOST}:4200/api prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_BASE -n $FLOW_BASE-deployment --pool default"
        
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
          
          # Print file content for debugging
          echo "File content of $FLOW_NAME (first 15 lines):"
          head -n 15 "$FLOW_FILE"
          
          # First try with the enhanced pattern
          FLOW_FUNCS=$(grep -E "@flow(\s*|\([^)]*\))\s*\n*\s*def\s+([a-zA-Z0-9_]+)" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | cut -d ' ' -f2)
          
          # If no matches, try a more permissive pattern
          if [ -z "$FLOW_FUNCS" ]; then
              echo "Trying alternate flow detection method for $FLOW_NAME..."
              FLOW_FUNCS=$(grep -A 1 "@flow" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | cut -d ' ' -f2)
          fi
          
          if [ -z "$FLOW_FUNCS" ]; then
            echo "Warning: No flow functions found in $FLOW_NAME, skipping..."
            continue
          fi
          
          echo "Found flow functions in $FLOW_NAME: $FLOW_FUNCS"
          echo "Copying $FLOW_FILE to container..."
          docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
          
          # Deploy each flow function found in the file
          for FLOW_FUNC in $FLOW_FUNCS; do
            echo "Deploying flow: $FLOW_NAME:$FLOW_FUNC"
            docker exec -e PREFECT_API_URL=http://${PREFECT_HOST}:4200/api prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"
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
      # Updated health check for Prefect 3.x using python instead of curl
      if docker exec prefect-server python -c "import urllib.request; urllib.request.urlopen('http://0.0.0.0:4200/api/health')" 2>/dev/null; then
        echo "Server is healthy, registering flows..."
        break
      fi
      
      ATTEMPT=$((ATTEMPT+1))
      echo "Waiting for server to be ready... Attempt $ATTEMPT/$MAX_ATTEMPTS"
      sleep 5
      
      # After 5 attempts, check the logs
      if [ $ATTEMPT -eq 5 ]; then
        echo "Server still starting, checking logs:"
        docker logs prefect-server --tail=20
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
        
        # Print file content for debugging
        echo "File content of $FLOW_NAME (first 15 lines):"
        head -n 15 "$FLOW_FILE"
        
        # First try with the enhanced pattern
        FLOW_FUNCS=$(grep -E "@flow(\s*|\([^)]*\))\s*\n*\s*def\s+([a-zA-Z0-9_]+)" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | cut -d ' ' -f2)
        
        # If no matches, try a more permissive pattern
        if [ -z "$FLOW_FUNCS" ]; then
            echo "Trying alternate flow detection method for $FLOW_NAME..."
            FLOW_FUNCS=$(grep -A 1 "@flow" "$FLOW_FILE" | grep -o "def\s\+[a-zA-Z0-9_]\+" | cut -d ' ' -f2)
        fi
        
        if [ -z "$FLOW_FUNCS" ]; then
          echo "Warning: No flow functions found in $FLOW_NAME, skipping..."
          continue
        fi
        
        echo "Found flow functions in $FLOW_NAME: $FLOW_FUNCS"
        echo "Copying $FLOW_FILE to container..."
        docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
        
        # Deploy each flow function found in the file
        for FLOW_FUNC in $FLOW_FUNCS; do
          echo "Deploying flow: $FLOW_NAME:$FLOW_FUNC"
          docker exec -e PREFECT_API_URL=http://${PREFECT_HOST}:4200/api prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"
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