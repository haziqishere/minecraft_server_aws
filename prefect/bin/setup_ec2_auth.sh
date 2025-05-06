#!/bin/bash
# EC2 SSH Authentication Setup Script
#
# This script sets up SSH key-based authentication to connect to the
# EC2 instance running the Minecraft server. It should be run once to
# configure the system for production use.
#
# Usage: 
#   ./setup_ec2_auth.sh <path/to/key.pem> [ec2_hostname] [ssh_user]

set -e  # Exit on error

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Config paths
CONFIG_DIR="$(dirname "$(dirname "$(realpath "$0")")")/config"
SSH_CONFIG="$HOME/.ssh/config"
EC2_CONFIG="$CONFIG_DIR/ec2_config.ini"

# Print usage
function print_usage() {
  echo -e "${YELLOW}Usage:${NC} $0 <path/to/key.pem> [ec2_hostname] [ssh_user]"
  echo
  echo "Arguments:"
  echo "  path/to/key.pem   Path to the EC2 private key (.pem file)"
  echo "  ec2_hostname      EC2 instance hostname or IP (default: value from config)"
  echo "  ssh_user          SSH username (default: ec2-user)"
  echo
  echo "Example:"
  echo "  $0 ~/Downloads/minecraft-server.pem 52.220.65.112 ec2-user"
}

# Create banner
function banner() {
  echo -e "${GREEN}=================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}=================================${NC}"
}

# Check if at least the key file was provided
if [ $# -lt 1 ]; then
  echo -e "${RED}Error: Missing required EC2 key file parameter${NC}"
  print_usage
  exit 1
fi

# Get parameters
KEY_PATH="$1"
EC2_HOST="${2:-}"
SSH_USER="${3:-ec2-user}"

# Make sure the key file exists
if [ ! -f "$KEY_PATH" ]; then
  echo -e "${RED}Error: Key file not found at $KEY_PATH${NC}"
  exit 1
fi

# If EC2_HOST wasn't provided, try to get it from the config file
if [ -z "$EC2_HOST" ] && [ -f "$EC2_CONFIG" ]; then
  EC2_HOST=$(grep "^EC2_HOST=" "$EC2_CONFIG" | cut -d= -f2)
fi

# Still need an EC2 host
if [ -z "$EC2_HOST" ]; then
  echo -e "${RED}Error: EC2 hostname/IP not provided and not found in config${NC}"
  print_usage
  exit 1
fi

banner "EC2 SSH Authentication Setup"
echo "Key file:    $KEY_PATH"
echo "EC2 host:    $EC2_HOST" 
echo "SSH user:    $SSH_USER"
echo "Config dir:  $CONFIG_DIR"
echo

# Create SSH directory if it doesn't exist
if [ ! -d "$HOME/.ssh" ]; then
  echo "Creating SSH directory..."
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
fi

# Copy key file to SSH directory
echo "Installing EC2 private key..."
cp "$KEY_PATH" "$HOME/.ssh/ec2_minecraft.pem"
chmod 600 "$HOME/.ssh/ec2_minecraft.pem"

# Create or update SSH config
if [ -f "$SSH_CONFIG" ]; then
  # Remove existing config for this host if present
  sed -i "/^Host minecraft-ec2/,/^$/d" "$SSH_CONFIG"
fi

echo "Updating SSH config..."
cat >> "$SSH_CONFIG" << EOF
Host minecraft-ec2
  HostName $EC2_HOST
  User $SSH_USER
  IdentityFile ~/.ssh/ec2_minecraft.pem
  StrictHostKeyChecking no
  ConnectTimeout 10

EOF

chmod 600 "$SSH_CONFIG"

# Make sure config directory exists
mkdir -p "$CONFIG_DIR"

# Update EC2 config
echo "Updating EC2 configuration..."
cat > "$EC2_CONFIG" << EOF
# EC2 instance connection details - PRODUCTION
# Updated by setup_ec2_auth.sh on $(date)
EC2_HOST=minecraft-ec2
SSH_USER=$SSH_USER
SSH_PORT=22

# Monitor settings
MONITOR_INTERVAL=300  # 5 minutes
DISCORD_WEBHOOK_ENABLED=true
EOF

# Test the connection
echo "Testing SSH connection to EC2 instance..."
if ssh -F "$SSH_CONFIG" minecraft-ec2 "echo Connection successful && uptime && docker ps | grep minecraft"; then
  banner "Setup completed successfully!"
  echo "You can now run the monitoring flow with:"
  echo "  cd prefect/flows"
  echo "  export KRONI_DEV_MODE=true"
  echo "  python server_monitoring_flow.py"
  echo
  echo "To deploy as a scheduled flow:"
  echo "  prefect deploy server_monitoring_flow.py:server_monitoring_flow -n production --pool default"
  echo
else
  echo -e "${RED}SSH connection test failed!${NC}"
  echo "Please check your key file and EC2 host settings and try again."
  exit 1
fi 