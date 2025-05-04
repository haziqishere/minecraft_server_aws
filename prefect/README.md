# Minecraft Server Prefect Automation

This directory contains Prefect flows and deployment configurations for automating the Minecraft server.

## Overview

The Prefect setup consists of:

- **prefect-server**: Runs the Prefect UI and API
- **prefect-worker**: Executes the scheduled flows
- **flows/**: Python scripts containing the flow definitions
- **helper scripts**: To make deployment and updates easier

## Flows

The main flows are:

1. **backup_flow.py**: Creates backups of the Minecraft world and uploads them to S3
2. **server_monitoring_flow.py**: Monitors server health and sends alerts
3. **snapshot_flow.py**: Creates scheduled snapshots of the AWS Lightsail instance

## Deployment

### Initial Deployment

To set up Prefect for the first time:

```bash
# Deploy Prefect server and worker
./deploy_prefect.sh deploy

# Register all flows with Prefect
./deploy_prefect.sh register
```

### Updating Flows

You can update flow files without rebuilding the Docker image:

**Option 1: Using the update-flows command:**

```bash
# Update all flows
./deploy_prefect.sh update-flows

# Update a specific flow
./deploy_prefect.sh update-flows latest backup_flow.py
```

**Option 2: Using the dedicated helper scripts:**

```bash
# Update a single flow
./update_flow.sh backup_flow.py

# Update all flows
./update_all_flows.sh
```

**Option 3: Using GitHub Actions workflow:**

Push changes to the `prefect/flows/` directory in the repository, and the GitHub Actions workflow will automatically update the flows on the server.

You can also manually trigger the workflow in the GitHub Actions UI and specify a specific flow to update.

## Managing Prefect

```bash
# Check status
./deploy_prefect.sh status

# View logs
./deploy_prefect.sh logs

# View logs for a specific service
./deploy_prefect.sh logs server
./deploy_prefect.sh logs worker

# Restart services
./deploy_prefect.sh restart

# Update to a new image version
./deploy_prefect.sh update latest
```

## Prefect UI

The Prefect UI is available at:
- Local: http://localhost:4200
- Server: http://<server-ip>:4200

## Configuration

The Prefect server and worker configuration is defined in:
- `docker-compose.yaml`: Container configuration
- `prefect.yaml`: Deployment configuration
- `.prefect/flows`: Flow registration and metadata 