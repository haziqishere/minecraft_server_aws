#!/bin/bash
# Test script for Minecraft server monitoring
#
# This script runs the server monitoring flow in simulation mode
# for testing purposes in development environments.

set -e  # Exit on error

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Paths
CONFIG_DIR="$(dirname "$(dirname "$(realpath "$0")")")/config"
FLOW_DIR="$(dirname "$(dirname "$(realpath "$0")")")/flows"

# Create banner
function banner() {
  echo -e "${GREEN}=================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}=================================${NC}"
}

banner "Minecraft Server Monitoring Test"
echo "Running in SIMULATION mode"
echo

# Create simulation directories if they don't exist
if [ ! -d "/data/world" ]; then
  echo "Creating simulation directories..."
  mkdir -p /data/world/region
  
  # Create dummy files to simulate Minecraft world
  echo "Creating sample world data..."
  dd if=/dev/urandom of=/data/world/level.dat bs=1M count=2 2>/dev/null
  
  # Create region directory and files
  mkdir -p /data/world/region
  dd if=/dev/urandom of=/data/world/region/r.0.0.mca bs=1M count=10 2>/dev/null
  dd if=/dev/urandom of=/data/world/region/r.0.1.mca bs=1M count=8 2>/dev/null
  
  echo "Simulation data created successfully"
fi

# Create temporary configuration for simulation mode
TMP_CONFIG="$CONFIG_DIR/test_config.ini"
cat > "$TMP_CONFIG" << EOF
# EC2 instance connection details - SIMULATED
# This is a testing configuration - do not use in production
SIMULATED_MODE=true
EC2_HOST=localhost
SSH_USER=ec2-user
SSH_PORT=22

# Monitor settings
MONITOR_INTERVAL=60  # 1 minute for testing
DISCORD_WEBHOOK_ENABLED=true
EOF

# Set environment variables for the test
export KRONI_DEV_MODE=true
export KRONI_EC2_CONFIG="$TMP_CONFIG"
export KRONI_SIMULATED_MODE=true

# Run the flow
banner "Running monitoring flow"
cd "$FLOW_DIR"
python server_monitoring_flow.py

# Check exit code
if [ $? -eq 0 ]; then
  banner "Test completed successfully!"
  echo "Discord notification should have been sent."
  echo
  echo "To run in production mode:"
  echo "  cd $FLOW_DIR"
  echo "  export KRONI_DEV_MODE=true"
  echo "  export KRONI_EC2_CONFIG=$CONFIG_DIR/ec2_config.ini"
  echo "  python server_monitoring_flow.py"
  echo
else
  echo -e "${YELLOW}Test failed. Check the logs for errors.${NC}"
  exit 1
fi 