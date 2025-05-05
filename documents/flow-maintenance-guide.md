# Minecraft AWS Prefect Flow Maintenance Guide

This guide provides step-by-step instructions for manually maintaining and running Prefect flows for the Minecraft server automation. It covers the entire lifecycle from connecting to the server, checking the status of containers, deploying flows, and running jobs manually.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Connecting to the Server](#connecting-to-the-server)
3. [Checking the Status of Prefect Containers](#checking-the-status-of-prefect-containers)
4. [Working with Prefect Server](#working-with-prefect-server)
5. [Working with Prefect Worker](#working-with-prefect-worker)
6. [Creating and Managing Work Pools](#creating-and-managing-work-pools)
7. [Deploying Flows](#deploying-flows)
8. [Running Flows Manually](#running-flows-manually)
9. [Scheduling Flows](#scheduling-flows)
10. [Viewing Flow Logs](#viewing-flow-logs)
11. [Troubleshooting](#troubleshooting)

## Prerequisites

Before proceeding, ensure you have:

- SSH access to the EC2 instance running the Prefect server
- AWS credentials configured on your local machine
- SSH key file for accessing the EC2 instance

## Connecting to the Server

1. Connect to your EC2 instance using SSH:

```bash
ssh -i path/to/your-key.pem ec2-user@your-ec2-ip-address
```

2. Navigate to the Prefect directory:

```bash
cd prefect
```

## Checking the Status of Prefect Containers

Check the status of your Docker containers:

```bash
docker ps
```

This should show at least two containers:
- `prefect-server`: Running the Prefect API server and UI
- `prefect-worker`: Running the Prefect worker that executes flows

If the containers are not running, start them with:

```bash
docker-compose up -d
```

To check the logs of the containers:

```bash
# View logs of both containers
docker-compose logs

# View logs of only the server
docker-compose logs prefect-server

# View logs of only the worker
docker-compose logs prefect-worker

# Follow logs in real-time
docker-compose logs -f
```

## Working with Prefect Server

### Accessing the Prefect Server Container

To access the Prefect server container's shell:

```bash
docker exec -it prefect-server bash
```

Inside the container, you can run Prefect CLI commands directly:

```bash
# Check Prefect version
prefect version

# List flows
prefect flow ls

# List deployments
prefect deployment ls
```

### Accessing the Prefect UI

The Prefect UI is available at `http://your-ec2-ip-address:4200`. Use this interface to:
- Monitor flow runs
- View logs
- Create new deployments
- Schedule flow runs
- Check work pool status

## Working with Prefect Worker

### Accessing the Prefect Worker Container

To access the Prefect worker container's shell:

```bash
docker exec -it prefect-worker bash
```

Inside the container, you can run commands to manage the worker:

```bash
# Check worker status
prefect worker status

# Restart the worker
prefect worker stop
prefect worker start -p default
```

## Creating and Managing Work Pools

Work pools are used to organize where your flows run. The default setup uses a process-based work pool named "default".

### Check Existing Work Pools

```bash
docker exec -it prefect-server prefect work-pool ls
```

### Create a New Work Pool

```bash
docker exec -it prefect-server prefect work-pool create my-new-pool -t process
```

Available work pool types:
- `process`: Runs flows in separate processes
- `kubernetes`: Runs flows in Kubernetes pods
- `docker`: Runs flows in Docker containers

### Delete a Work Pool

```bash
docker exec -it prefect-server prefect work-pool delete my-new-pool
```

## Deploying Flows

Deployments allow you to register your flows with the Prefect server, enabling scheduled and API-triggered runs.

### Deploy a Single Flow

1. Make sure your flow file is in the `flows` directory.
2. Deploy the flow:

```bash
# Connect to the prefect-server container
docker exec -it prefect-server bash

# Navigate to the flows directory
cd /opt/prefect/flows

# Deploy a flow (replace flow_file.py with your flow's filename)
# Format: prefect deploy [FILENAME]:[FLOW_FUNCTION_NAME] -n [DEPLOYMENT_NAME] --pool [WORK_POOL_NAME]
prefect deploy backup_flow.py:backup_flow -n backup-flow-deployment --pool default
```

### Update prefect.yaml Configuration

The `prefect.yaml` file is used for centralized flow configuration. It's located at `prefect/prefect.yaml`.

Edit this file to add or modify deployments:

```yaml
# Prefect configuration
prefect-version: null
name: minecraft-automation

# Define pull steps to run when deploying
pull:
  - prefect.deployments.steps.set_working_directory:
      directory: /opt/prefect/flows

# Define our deployments
deployments:
  - name: backup-flow
    entrypoint: backup_flow.py:backup_flow
    work_pool:
      name: default
  
  - name: server-monitoring-flow
    entrypoint: server_monitoring_flow.py:server_monitoring_flow
    work_pool:
      name: default
  
  - name: snapshot-flow
    entrypoint: snapshot_flow.py:snapshot_flow
    work_pool:
      name: default
```

### Deploy All Flows at Once

Use the provided helper script to deploy all flows:

```bash
cd prefect
./deploy_all_flows.sh
```

Or manually from the container:

```bash
docker exec -it prefect-server bash -c "cd /opt/prefect/flows && for f in *.py; do if grep -q \"@flow\" \$f; then echo \"Deploying \$f\"; prefect deploy \$f:\$(grep -o \"@flow.*def \\w\\+\" \$f | head -1 | awk '{print \$NF}') -n \$(basename \$f .py)-deployment --pool default; fi; done"
```

## Running Flows Manually

### Run a Flow via CLI

```bash
# Connect to the prefect-server container
docker exec -it prefect-server bash

# Run a flow deployment
# Format: prefect deployment run [DEPLOYMENT_NAME]/[FLOW_NAME]
prefect deployment run backup-flow/backup_flow
```

### Run a Flow with Parameters

```bash
# Run with parameters
prefect deployment run backup-flow/backup_flow -p minecraft_host="your-minecraft-server-ip" -p world_path="/data/world" 
```

### Run a Flow from Python

You can also create a simple Python script to run a flow directly:

```bash
# Connect to the prefect-server container
docker exec -it prefect-server bash

# Create a Python file to run the flow
cat > /tmp/run_backup.py << 'EOF'
from prefect import flow
from flows.backup_flow import backup_flow

if __name__ == "__main__":
    config = {
        "minecraft_host": "your-minecraft-server-ip",
        "world_path": "/data/world",
        "s3_bucket": "your-s3-bucket",
        "region": "ap-southeast-1",
        "discord_webhook_url": "your-discord-webhook-url"
    }
    backup_flow(config=config)
EOF

# Run the Python file
python /tmp/run_backup.py
```

## Scheduling Flows

### Schedule via CLI

```bash
# Connect to the prefect-server container
docker exec -it prefect-server bash

# Add a schedule to a deployment
# Format: prefect deployment set-schedule [DEPLOYMENT_NAME]/[FLOW_NAME] --cron "CRON_EXPRESSION"
prefect deployment set-schedule backup-flow/backup_flow --cron "0 0 */3 * *"  # Every 3 days at midnight
```

Common cron expressions:
- Daily at midnight: `0 0 * * *`
- Weekly on Sunday at 1 AM: `0 1 * * 0`
- Monthly on the 1st at 2 AM: `0 2 1 * *`
- Every 12 hours: `0 */12 * * *`

### Remove a Schedule

```bash
docker exec -it prefect-server prefect deployment set-schedule backup-flow/backup_flow --clear
```

## Viewing Flow Logs

### View Logs via CLI

```bash
# Connect to the prefect-server container
docker exec -it prefect-server bash

# View logs of a specific flow run
# First, list recent flow runs to get the ID
prefect flow-run ls

# Then view logs for a specific flow run ID
prefect flow-run logs VIEW [FLOW_RUN_ID]
```

### View Container Logs

```bash
# View worker logs (this is where most flow execution logs appear)
docker logs prefect-worker

# Follow logs in real-time
docker logs -f prefect-worker
```

## Troubleshooting

### Container Issues

If containers aren't starting:

```bash
# Check container status
docker ps -a

# View startup errors
docker logs prefect-server
docker logs prefect-worker

# Restart containers
docker-compose down
docker-compose up -d
```

### Flow Issues

If flows are failing:

1. Check the worker logs:
```bash
docker logs prefect-worker
```

2. Check if the server and worker can communicate:
```bash
docker exec -it prefect-worker ping prefect-server
```

3. Verify the flow file exists in the correct location:
```bash
docker exec -it prefect-server ls -la /opt/prefect/flows
```

4. Check if the work pool exists and has a worker:
```bash
docker exec -it prefect-server prefect work-pool ls
```

5. Ensure your AWS credentials are correctly set up:
```bash
docker exec -it prefect-server cat /root/.aws/credentials
```

### Networking Issues

If there are connectivity issues:

1. Check if the worker can access the server:
```bash
docker exec -it prefect-worker curl http://172.28.0.2:4200/api/health
```

2. Verify external access to the UI:
```bash
curl http://localhost:4200/api/health
```

3. Restart networking:
```bash
docker-compose down
docker network prune
docker-compose up -d
```

## Reset All Flows and Deployments

If you need to completely reset and start from scratch:

```bash
# Stop and remove containers
docker-compose down

# Remove the volume containing Prefect data
docker volume rm prefect_prefect-data

# Start again
docker-compose up -d

# Redeploy flows
./deploy_all_flows.sh
```

---

## Quick Reference Commands

### Container Management

```bash
# Start containers
docker-compose up -d

# Stop containers
docker-compose down

# Restart containers
docker-compose restart

# Check container status
docker ps
```

### Flow Management

```bash
# List flows
docker exec -it prefect-server prefect flow ls

# List deployments
docker exec -it prefect-server prefect deployment ls

# Run a flow
docker exec -it prefect-server prefect deployment run backup-flow/backup_flow

# Deploy a specific flow
docker exec -it prefect-server bash -c "cd /opt/prefect/flows && prefect deploy backup_flow.py:backup_flow -n backup-flow-deployment --pool default"
```

### Work Pool Management

```bash
# List work pools
docker exec -it prefect-server prefect work-pool ls

# Create work pool
docker exec -it prefect-server prefect work-pool create default -t process

# Start a worker
docker exec -it prefect-worker prefect worker start -p default
```

By following this guide, you should be able to effectively maintain and manage your Prefect flows for Minecraft server automation without relying solely on automation scripts. 