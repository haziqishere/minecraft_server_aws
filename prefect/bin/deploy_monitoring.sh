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
    # After creating deployment, set up containers
    # Setup container environment if running locally
    if [[ $(docker ps -q -f name=prefect-server) ]]; then
      echo "Setting up Prefect container environment..."
      
      # Create required directories in containers
      echo "Creating directories in containers..."
      docker exec prefect-server mkdir -p /opt/prefect/config /opt/prefect/utils /root/.ssh
      docker exec prefect-worker mkdir -p /opt/prefect/config /opt/prefect/utils /root/.ssh
      
      # Copy configuration
      echo "Copying configuration to containers..."
      docker cp "$CONFIG_DIR/ec2_config.ini" prefect-server:/opt/prefect/config/
      docker cp "$CONFIG_DIR/ec2_config.ini" prefect-worker:/opt/prefect/config/
      
      # Get utils path
      UTILS_DIR="$(dirname "$CONFIG_DIR")/utils"
      echo "Copying utility modules to containers..."
      docker cp "$UTILS_DIR/server_utils.py" prefect-server:/opt/prefect/utils/
      docker cp "$UTILS_DIR/server_utils.py" prefect-worker:/opt/prefect/utils/
      
      # Find and copy SSH key
      echo "Setting up SSH in containers..."
      SSH_KEY=""
      
      # First, look for specific EC2 key
      if [ -f ~/.ssh/ec2_minecraft.pem ]; then
        SSH_KEY=~/.ssh/ec2_minecraft.pem
      else
        # Otherwise use any available key
        for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519; do
          if [ -f "$key" ]; then
            SSH_KEY="$key"
            break
          fi
        done
      fi
      
      if [ -n "$SSH_KEY" ]; then
        echo "Using SSH key: $SSH_KEY"
        docker cp "$SSH_KEY" prefect-server:/root/.ssh/id_rsa
        docker cp "$SSH_KEY" prefect-worker:/root/.ssh/id_rsa
        docker exec prefect-server chmod 600 /root/.ssh/id_rsa
        docker exec prefect-worker chmod 600 /root/.ssh/id_rsa
        
        # Get EC2 host from config
        EC2_HOST=$(grep "^EC2_HOST=" "$CONFIG_DIR/ec2_config.ini" | cut -d= -f2)
        
        if [ -n "$EC2_HOST" ]; then
          echo "Adding EC2 host $EC2_HOST to known_hosts..."
          docker exec prefect-server bash -c "ssh-keyscan -H $EC2_HOST >> /root/.ssh/known_hosts"
          docker exec prefect-worker bash -c "ssh-keyscan -H $EC2_HOST >> /root/.ssh/known_hosts"
        fi
      else
        echo -e "${YELLOW}No SSH key found - SSH access may not work${NC}"
      fi
      
      echo "Container setup completed!"
    fi
    
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