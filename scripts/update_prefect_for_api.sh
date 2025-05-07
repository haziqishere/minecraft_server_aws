#!/bin/bash
#
# Update Prefect for API-Based Monitoring
# This script updates the Prefect server to use the new API-based monitoring
#

set -e

# Get the IP of the Minecraft server from terraform output
MINECRAFT_SERVER_IP=$(cd terraform && terraform output -json | jq -r '.minecraft_server_ip.value')
PREFECT_SERVER_IP=$(cd terraform && terraform output -json | jq -r '.prefect_orchestration_ip.value')

if [ -z "$MINECRAFT_SERVER_IP" ]; then
    echo "Error: Could not get Minecraft server IP"
    exit 1
fi

if [ -z "$PREFECT_SERVER_IP" ]; then
    echo "Error: Could not get Prefect server IP"
    exit 1
fi

# Get API key from Minecraft server
echo "Getting API key from Minecraft server..."
API_KEY=$(ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@$MINECRAFT_SERVER_IP "cat /opt/metrics-api/api_key.txt | grep 'API Key:' | cut -d' ' -f3")

if [ -z "$API_KEY" ]; then
    echo "Could not get API key. Generating a new one..."
    API_KEY=$(openssl rand -hex 16)
fi

echo "Using API key: $API_KEY"
echo "Minecraft server IP: $MINECRAFT_SERVER_IP"
echo "Prefect server IP: $PREFECT_SERVER_IP"

# Update Prefect environment variables
echo "Updating Prefect environment variables..."
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@$PREFECT_SERVER_IP "cat > ~/prefect/.env << EOF
PREFECT_API_URL=http://${PREFECT_SERVER_IP}:4200/api
METRICS_API_URL=http://${MINECRAFT_SERVER_IP}:8000
METRICS_API_KEY=${API_KEY}
EOF"

# Copy the updated server_monitoring_flow.py to the Prefect server
echo "Copying updated server_monitoring_flow.py to Prefect server..."
scp -i ~/.ssh/kroni-survival-key.pem prefect/flows/server_monitoring_flow.py ec2-user@$PREFECT_SERVER_IP:~/prefect/flows/

# Update Docker containers with new environment variables
echo "Updating Prefect Docker containers..."
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@$PREFECT_SERVER_IP "cd ~/prefect && docker-compose down && docker-compose up -d"

# Wait for Prefect server to start
echo "Waiting for Prefect server to start..."
sleep 10

# Register the server_monitoring_flow
echo "Registering server_monitoring_flow..."
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@$PREFECT_SERVER_IP "docker exec prefect-server bash -c 'cd /opt/prefect/flows && prefect deploy server_monitoring_flow.py:server_monitoring_flow -n server_monitoring_flow-deployment --pool default -v'"

# Run the flow to test it
echo "Running server_monitoring_flow to test it..."
ssh -i ~/.ssh/kroni-survival-key.pem ec2-user@$PREFECT_SERVER_IP "docker exec prefect-server bash -c 'cd /opt/prefect/flows && python server_monitoring_flow.py'"

echo "Prefect server updated successfully!"
echo "You can access the Prefect UI at: http://${PREFECT_SERVER_IP}:4200" 