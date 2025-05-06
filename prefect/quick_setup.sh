#!/bin/bash
# quick_setup.sh - Quick setup script for Minecraft server monitoring
#
# This script provides a guided setup for the monitoring system,
# automating the key steps required to get monitoring working.

set -e  # Exit on error

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create banner
function banner() {
  echo -e "${GREEN}================================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}================================================${NC}"
}

# Step function
function step() {
  echo -e "${BLUE}>> $1${NC}"
}

banner "Minecraft Server Monitoring - Quick Setup"
echo "This script will guide you through setting up the monitoring system."
echo

# Get EC2 key file and host
step "Step 1: Configure SSH access to EC2 instance"
echo "Please provide the following information:"

EC2_KEY_FILE=""
while [ -z "$EC2_KEY_FILE" ] || [ ! -f "$EC2_KEY_FILE" ]; do
  read -p "Path to EC2 key file (.pem): " EC2_KEY_FILE
  if [ ! -f "$EC2_KEY_FILE" ]; then
    echo -e "${RED}Error: Key file not found at $EC2_KEY_FILE${NC}"
  fi
done

read -p "EC2 instance IP or hostname: " EC2_HOST
read -p "SSH username (default: ec2-user): " EC2_USER
EC2_USER=${EC2_USER:-ec2-user}

# Set up EC2 authentication
echo
step "Step 2: Setting up EC2 authentication"
cd "$(dirname "$0")"
bash bin/setup_ec2_auth.sh "$EC2_KEY_FILE" "$EC2_HOST" "$EC2_USER"

# Check if Prefect is running
echo
step "Step 3: Checking Prefect server status"
if ! docker ps | grep -q prefect-server; then
  echo "Prefect server is not running. Would you like to start it?"
  read -p "Start Prefect server? (y/n): " START_PREFECT
  if [[ "$START_PREFECT" =~ ^[Yy]$ ]]; then
    echo "Starting Prefect server..."
    bash deploy_prefect.sh deploy
  else
    echo "Skipping Prefect server startup."
  fi
else
  echo "Prefect server is already running."
fi

# Deploy monitoring flow
echo
step "Step 4: Deploying monitoring flow"
echo "How often should the monitoring run?"
read -p "Interval in seconds (default: 300): " INTERVAL
INTERVAL=${INTERVAL:-300}

echo "Deploying monitoring flow to run every $INTERVAL seconds..."
bash bin/deploy_monitoring.sh --interval "$INTERVAL"

# Run manually for testing
echo
step "Step 5: Testing"
echo "Would you like to run the monitoring flow now to test it?"
read -p "Run now? (y/n): " RUN_NOW
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
  echo "Running monitoring flow..."
  prefect deployment run "Kroni Survival Server Monitoring/production"
  echo "Check your Discord for the notification."
fi

# All done
banner "Setup Complete!"
echo "Your Minecraft server monitoring is now set up and will run every $INTERVAL seconds."
echo 
echo "For more information and troubleshooting, see README.md" 