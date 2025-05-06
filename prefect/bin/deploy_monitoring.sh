#!/bin/bash
# Deployment script for Minecraft server monitoring flow
#
# This script deploys the Minecraft server monitoring flow
# to Prefect and schedules it to run at regular intervals.

set -e  # Exit on error

# ANSI color codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Paths
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")/config"
FLOW_DIR="$(dirname "$SCRIPT_DIR")/flows"

# Create banner
function banner() {
  echo -e "${GREEN}=================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}=================================${NC}"
}

# Check if the EC2 config exists
if [ ! -f "$CONFIG_DIR/ec2_config.ini" ]; then
  echo -e "${RED}Error: EC2 configuration file not found at $CONFIG_DIR/ec2_config.ini${NC}"
  echo "Please run setup_ec2_auth.sh first to configure SSH access to your EC2 instance."
  exit 1
fi

# Parse arguments
DEPLOY_NAME="production"
INTERVAL=300  # 5 minutes default
APPLY="true"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      DEPLOY_NAME="$2"
      shift 2
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --apply)
      APPLY="true"
      shift
      ;;
    --dry-run)
      APPLY="false"
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo
      echo "Options:"
      echo "  --name NAME       Deployment name (default: production)"
      echo "  --interval SEC    Monitoring interval in seconds (default: 300)"
      echo "  --dry-run         Show what would be done without applying"
      echo "  --apply           Apply the deployment (default)"
      echo "  --help            Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

banner "Minecraft Server Monitoring Deployment"
echo "Deployment name:   $DEPLOY_NAME"
echo "Interval:          $INTERVAL seconds"
echo "Config directory:  $CONFIG_DIR"
echo "Flow directory:    $FLOW_DIR"
echo "Apply changes:     $APPLY"
echo

# Make sure Prefect is properly configured
echo "Checking Prefect configuration..."
if ! prefect config get PREFECT_API_URL &>/dev/null; then
  echo -e "${YELLOW}Setting default Prefect API URL...${NC}"
  prefect config set PREFECT_API_URL=http://127.0.0.1:4200/api
fi

# Check work-pool
if ! prefect work-pool ls | grep -q "default"; then
  echo -e "${YELLOW}Creating default work pool...${NC}"
  prefect work-pool create default -t process
fi

# Set up environment variables for the deployment
export KRONI_DEV_MODE=true
export KRONI_EC2_CONFIG="$CONFIG_DIR/ec2_config.ini"

# Create deployment command
DEPLOY_CMD="prefect deploy \"$FLOW_DIR/server_monitoring_flow.py:server_monitoring_flow\" -n \"$DEPLOY_NAME\" --pool default --interval $INTERVAL"

# Execute or print the command
if [ "$APPLY" = "true" ]; then
  echo "Creating deployment..."
  cd "$FLOW_DIR"
  
  # Run the command with env variables
  eval "$DEPLOY_CMD"
  
  if [ $? -eq 0 ]; then
    banner "Deployment created successfully!"
    echo "Your monitoring flow is now scheduled to run every $INTERVAL seconds."
    echo
    echo "To run it immediately:"
    echo "  prefect deployment run \"Kroni Survival Server Monitoring/$DEPLOY_NAME\""
    echo
  else
    echo -e "${RED}Deployment failed.${NC}"
    exit 1
  fi
else
  echo -e "${YELLOW}Dry run - commands that would be executed:${NC}"
  echo "  cd $FLOW_DIR"
  echo "  $DEPLOY_CMD"
fi 