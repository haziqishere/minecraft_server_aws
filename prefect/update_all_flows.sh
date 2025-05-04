#!/bin/bash
# update_all_flows.sh - Script to update and deploy all flows in Prefect

echo "Updating all Prefect flows..."

# Get list of all Python files in flows directory
FLOW_FILES=$(find flows -maxdepth 1 -name "*.py" -type f | grep -v "__init__" | grep -v "__pycache__")

# Check if any flow files were found
if [ -z "$FLOW_FILES" ]; then
    echo "No flow files found in 'flows/' directory."
    exit 1
fi

# Make sure the work pool exists
echo "Ensuring work pool exists..."
docker exec prefect-server bash -c "prefect work-pool create default -t process || echo 'Work pool already exists'"

# Process each flow file
for FLOW_FILE in $FLOW_FILES; do
    FLOW_NAME=$(basename "$FLOW_FILE" .py)
    FLOW_FILE_NAME=$(basename "$FLOW_FILE")
    
    echo "-------------------------------------------"
    echo "Processing flow: $FLOW_NAME from $FLOW_FILE_NAME"
    
    # Copy file to container
    echo "Copying flow file to server container..."
    docker cp $FLOW_FILE prefect-server:/opt/prefect/flows/$FLOW_FILE_NAME
    
    # Deploy the flow
    echo "Deploying flow..."
    docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_FILE_NAME:$FLOW_NAME -n $FLOW_NAME-deployment --pool default"
    
    echo "Flow $FLOW_NAME updated successfully!"
done

echo "-------------------------------------------"
echo "All flows updated successfully!"
echo "Check the Prefect UI at http://localhost:4200 to view your deployments." 