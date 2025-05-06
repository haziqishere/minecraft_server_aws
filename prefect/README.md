# Minecraft Server Monitoring with Prefect

This directory contains the Prefect workflows for monitoring the Minecraft server.

## Quick Setup

For a guided setup process, run the quick setup script:

```bash
./quick_setup.sh
```

This script will:
1. Configure SSH access to your EC2 instance
2. Check and start Prefect server if needed
3. Deploy the monitoring flow
4. Run a test to verify everything works

## Directory Structure

- `bin/` - Utility scripts for deployment and setup
- `config/` - Configuration files for EC2 and Prefect
- `flows/` - Prefect workflow definitions
- `utils/` - Utility modules used by the flows

## Key Scripts

### Setup and Deployment

- **`bin/setup_ec2_auth.sh`**: Set up SSH key-based authentication to connect to the EC2 instance.
  ```
  ./bin/setup_ec2_auth.sh <path/to/key.pem> <ec2_hostname> <ssh_user>
  ```

- **`bin/deploy_monitoring.sh`**: Deploy the server monitoring flow to Prefect.
  ```
  ./bin/deploy_monitoring.sh [--interval 300] [--name production]
  ```
  This script also sets up the Prefect containers with the proper SSH configuration.

- **`deploy_prefect.sh`**: Deploy and manage the Prefect server itself.
  ```
  ./deploy_prefect.sh [deploy|status|logs|restart|register]
  ```

### Testing and Troubleshooting

- **`bin/test_monitoring.sh`**: Run the monitoring flow in simulation mode for testing.
  ```
  ./bin/test_monitoring.sh
  ```

- **`bin/config_check.py`**: Check the configuration and verify SSH connectivity.
  ```
  python bin/config_check.py
  ```

## Common Tasks

### First-time Setup

1. Set up SSH authentication for the EC2 instance:
   ```
   ./bin/setup_ec2_auth.sh ~/Downloads/minecraft-key.pem 52.220.65.112 ec2-user
   ```

2. Deploy the Prefect server (if not already running):
   ```
   ./deploy_prefect.sh deploy
   ```

3. Deploy the monitoring flow:
   ```
   ./bin/deploy_monitoring.sh
   ```

### Checking Status

- Check Prefect server status:
  ```
  ./deploy_prefect.sh status
  ```

- Run the monitoring flow manually:
  ```
  prefect deployment run "Kroni Survival Server Monitoring/production"
  ```

### Troubleshooting

If the monitoring flow is not detecting the Minecraft server correctly:

1. Verify SSH connectivity:
   ```
   python bin/config_check.py
   ```

2. Check for proper container configuration:
   ```
   docker exec prefect-worker ls -la /opt/prefect/config/
   docker exec prefect-worker ls -la /root/.ssh/
   ```

3. Try the monitoring in simulation mode:
   ```
   ./bin/test_monitoring.sh
   ```

## Environment Variables

- `KRONI_SIMULATED_MODE=true` - Run in simulation mode with mock data
- `KRONI_EC2_CONFIG` - Path to EC2 configuration file 