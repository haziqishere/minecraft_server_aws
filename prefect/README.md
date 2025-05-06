# Kroni Survival Minecraft Server Monitoring

This module provides a comprehensive monitoring solution for the Kroni Survival Minecraft server running on AWS EC2. It collects server metrics, checks the Minecraft server status, tracks world size growth, and sends notifications to a Discord webhook.

## Directory Structure

```
prefect/
├── bin/                   # Executable scripts
│   ├── deploy_monitoring.sh    # Deploy monitoring flow to Prefect
│   ├── setup_ec2_auth.sh       # Configure SSH access to EC2
│   └── test_monitoring.sh      # Run monitoring in test mode
├── config/                # Configuration files
│   └── ec2_config.ini     # EC2 connection settings
├── flows/                 # Prefect flow definitions
│   └── server_monitoring_flow.py  # Main monitoring flow
└── utils/                 # Utility modules
    └── server_utils.py    # Common utility functions
```

## Setup Instructions

### 1. Setting up SSH Authentication to EC2

To monitor your EC2 instance, you need to set up SSH key-based authentication:

```bash
cd prefect/bin
./setup_ec2_auth.sh path/to/your/ec2-key.pem 52.220.65.112 ec2-user
```

Replace the parameters with your actual EC2 key file path, instance IP, and username.

### 2. Testing the Monitoring

To test the monitoring flow without actually connecting to EC2:

```bash
cd prefect/bin
./test_monitoring.sh
```

This will run in simulation mode and send a test notification to Discord.

### 3. Deploying the Monitoring Flow

To deploy the monitoring flow to Prefect and schedule it:

```bash
cd prefect/bin
./deploy_monitoring.sh --interval 300
```

This deploys the flow to run every 5 minutes (300 seconds).

## Usage

### Running manually

```bash
cd prefect/flows
export KRONI_DEV_MODE=true
python server_monitoring_flow.py
```

### Running a deployed flow

```bash
prefect deployment run "Kroni Survival Server Monitoring/production"
```

## Configuration

The monitoring flow is configured through environment variables and the config file. The key environment variables are:

- `KRONI_DEV_MODE`: Set to "true" to enable remote monitoring mode
- `KRONI_EC2_CONFIG`: Path to the EC2 configuration file
- `KRONI_SIMULATED_MODE`: Set to "true" to run in simulation mode (for testing)

## Troubleshooting

### SSH Connection Issues

If you're having trouble connecting to your EC2 instance:

1. Make sure your key file has the correct permissions (`chmod 600 key.pem`)
2. Verify that your EC2 instance's security group allows SSH from your IP
3. Check that the EC2 user has permissions to run Docker commands

### Discord Webhook Issues

If Discord notifications aren't working:

1. Verify your webhook URL is correct
2. Make sure `DISCORD_WEBHOOK_ENABLED` is set to "true" in your config
3. Check network connectivity to Discord's servers

## Contributing

When extending this monitoring system:

1. Add new metrics in `server_utils.py`
2. Update the `server_monitoring_flow.py` to use your new metrics
3. Test thoroughly with `test_monitoring.sh` before deploying 