#!/bin/bash
# update_flow.sh - Script to update and deploy a specific flow in Prefect

# Usage: ./update_flow.sh <flow_file_name>
# Example: ./update_flow.sh backup_flow.py

# Check if a flow file name was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <flow_file_name>"
    echo "Example: $0 backup_flow.py"
    exit 1
fi

# Check if Prefect server is healthy
echo "Checking if Prefect server is healthy..."
MAX_ATTEMPTS=10
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if docker exec prefect-server curl -s http://localhost:4200/api/health | grep -q "ok"; then
        echo "Prefect server is healthy"
        break
    fi
    
    ATTEMPT=$((ATTEMPT+1))
    echo "Waiting for server to be ready... Attempt $ATTEMPT/$MAX_ATTEMPTS"
    sleep 5
    
    if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "Server failed to become ready. Check server logs with: docker logs prefect-server"
        exit 1
    fi
done

FLOW_FILE=$1
FLOW_NAME=$(basename "$FLOW_FILE" .py)

# Check if the flow file exists
if [ ! -f "flows/$FLOW_FILE" ]; then
    echo "Error: Flow file 'flows/$FLOW_FILE' does not exist."
    exit 1
fi

echo "Examining flow: $FLOW_NAME from $FLOW_FILE"

# Detect flow functions in the file
FLOW_FUNCS=$(grep -o "@flow.*def \w\+" "flows/$FLOW_FILE" | awk '{print $NF}')

if [ -z "$FLOW_FUNCS" ]; then
    echo "Error: No flow functions found in $FLOW_FILE!"
    exit 1
fi

echo "Found flow functions: $FLOW_FUNCS"

# Copy file to container
echo "Copying flow file to server container..."
docker cp flows/$FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_FILE

# Create work pool if needed
echo "Creating work pool if needed..."
docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Work pool already exists'"

# Deploy each flow function
for FLOW_FUNC in $FLOW_FUNCS; do
    echo "--------------------------------------"
    echo "Deploying flow: $FLOW_FUNC from $FLOW_FILE"
    
    # Deploy the flow
    docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_FILE:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"
    
    echo "Flow $FLOW_FUNC deployed successfully!"
done

echo "--------------------------------------"
echo "All flows in $FLOW_FILE updated successfully!"
echo "Check the Prefect UI at http://localhost:4200 to view your deployments." 