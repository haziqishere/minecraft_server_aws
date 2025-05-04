#!/bin/bash
# deploy_all_flows.sh
# Script to automatically deploy all Python flow files in the flows directory

# Set the flows directory path (allow override via env var)
FLOWS_DIR=${FLOWS_DIR:-"/opt/prefect/flows"}

# Get all Python files in the flows directory
echo "Searching for flow files in $FLOWS_DIR"
FLOW_FILES=$(find $FLOWS_DIR -name "*.py" | grep -v "__init__.py" | grep -v "__pycache__")

echo "Found the following flow files:"
echo "$FLOW_FILES"

# Create a counter for successful deployments
SUCCESS_COUNT=0
TOTAL_COUNT=0

# Execute each flow file
for flow_file in $FLOW_FILES; do
  flow_name=$(basename "$flow_file")
  echo "Deploying flow: $flow_name"
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  
  # Execute the flow file
  cd $(dirname "$flow_file")
  python "$flow_file"
  
  if [ $? -eq 0 ]; then
    echo "Successfully deployed $flow_name"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    echo "Failed to deploy $flow_name"
  fi
  
  # Add a small delay between deployments
  sleep 1
done

echo "Deployment completed. Successfully deployed $SUCCESS_COUNT out of $TOTAL_COUNT flows."

if [ $SUCCESS_COUNT -eq 0 ] && [ $TOTAL_COUNT -gt 0 ]; then
  echo "WARNING: No flows were deployed successfully!"
  exit 1
fi 