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
TOTAL_FLOWS=0
SUCCESS_FLOWS=0

for FLOW_FILE in $FLOW_FILES; do
    FLOW_NAME=$(basename "$FLOW_FILE")
    
    echo "-------------------------------------------"
    echo "Processing file: $FLOW_NAME"
    
    # Find flow functions in the file
    FLOW_FUNCS=$(grep -o "@flow.*def \w\+" "$FLOW_FILE" | awk '{print $NF}')
    
    if [ -z "$FLOW_FUNCS" ]; then
        echo "Warning: No flow functions found in $FLOW_NAME, skipping..."
        continue
    fi
    
    echo "Found flow functions: $FLOW_FUNCS"
    
    # Copy file to container
    echo "Copying flow file to server container..."
    docker cp "$FLOW_FILE" prefect-server:/opt/prefect/flows/"$FLOW_NAME"
    
    # Deploy each flow function
    for FLOW_FUNC in $FLOW_FUNCS; do
        TOTAL_FLOWS=$((TOTAL_FLOWS + 1))
        
        echo "Deploying flow: $FLOW_FUNC from $FLOW_NAME"
        if docker exec prefect-server bash -c "cd /opt/prefect/flows && prefect deploy $FLOW_NAME:$FLOW_FUNC -n $FLOW_FUNC-deployment --pool default"; then
            echo "Flow $FLOW_FUNC deployed successfully!"
            SUCCESS_FLOWS=$((SUCCESS_FLOWS + 1))
        else
            echo "ERROR: Failed to deploy $FLOW_FUNC!"
        fi
    done
done

echo "-------------------------------------------"
echo "Flow deployment complete: $SUCCESS_FLOWS/$TOTAL_FLOWS flows deployed successfully."

# Check if worker is running
if ! docker ps | grep -q "prefect-worker"; then
    echo "Worker is not running. Starting worker..."
    docker-compose up -d prefect-worker
else
    echo "Worker is already running."
fi

echo "Check the Prefect UI at http://localhost:4200 to view your deployments." 