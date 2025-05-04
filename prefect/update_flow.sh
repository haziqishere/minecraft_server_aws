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

FLOW_FILE=$1
FLOW_NAME=$(basename "$FLOW_FILE" .py)

# Check if the flow file exists
if [ ! -f "flows/$FLOW_FILE" ]; then
    echo "Error: Flow file 'flows/$FLOW_FILE' does not exist."
    exit 1
fi

echo "Updating flow: $FLOW_NAME from $FLOW_FILE"

# Copy file to container
echo "Copying flow file to server container..."
docker cp flows/$FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_FILE

# Deploy the flow
echo "Deploying flow..."
docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect work-pool create default -t process || echo 'Work pool already exists'"
docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_FILE:$FLOW_NAME -n $FLOW_NAME-deployment --pool default"

echo "Flow $FLOW_NAME updated successfully!"
echo "Check the Prefect UI at http://localhost:4200 to view your deployment." 