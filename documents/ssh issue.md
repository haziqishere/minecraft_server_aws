# Minecraft Server Monitoring SSH Issues and Solutions

## Initial Problem

The monitoring system was incorrectly reporting the Minecraft server as "Stopped" in Discord notifications when it was actually running. This occurred because:

1. The monitoring script was checking Docker container status locally instead of on the remote EC2 instance
2. SSH connectivity to the EC2 instance was not properly established
3. Configuration for remote monitoring was scattered across multiple files

## Solution Evolution

### Phase 1: Initial Scripts

Two temporary scripts were created to address the SSH connectivity issues:

1. `quick_ec2_setup.sh`: A simplified approach that:
   - Tested direct SSH connection to the EC2 instance
   - Created a basic EC2 configuration file
   - Used simple connection parameters without requiring key file

2. `setup_ec2_key.sh`: A more secure approach that:
   - Set up proper SSH key-based authentication
   - Created SSH config entries 
   - Copied the EC2 key file to the SSH directory
   - Tested the connection with the key file

Both scripts were temporary measures to establish connectivity but had several limitations:
- Hardcoded EC2 IP addresses
- Lack of error handling
- No separation between development and production environments
- Configuration spread across multiple locations

### Phase 2: Restructured Solution

The solution was restructured into a proper organized system:

1. Created `prefect/utils/server_utils.py`:
   - Centralized all SSH-related functions
   - Added proper error handling and logging
   - Implemented a simulation mode for testing
   - Separated configuration from implementation

2. Created `prefect/bin/setup_ec2_auth.sh`:
   - Professional key-based authentication setup
   - Centralized configuration in a standard location
   - Added validation and error handling
   - Created proper SSH config entries

3. Created `prefect/bin/test_monitoring.sh`:
   - Added simulation mode for testing without EC2 access
   - Created dummy data directories for local testing
   - Used temporary configuration for testing

4. Created `prefect/bin/deploy_monitoring.sh`:
   - Added proper deployment to Prefect
   - Scheduled monitoring with configurable intervals
   - Added proper validation

5. Centralized configuration in `prefect/config/ec2_config.ini`

## Problem Resolution

The original issue (incorrect server status) was resolved by:

1. Implementing proper SSH connection handling in `server_utils.py`
2. Adding `check_container_status()` function that:
   - Performs status checks via SSH when in remote mode
   - Handles errors and timeouts gracefully
   - Reports accurate container status
3. Adding simulation mode for testing the solution without requiring actual EC2 access

## Key Improvements

1. **Centralized Configuration**: All connection details moved to `prefect/config/ec2_config.ini`
2. **Proper Error Handling**: Added robust error handling and logging
3. **Testing Mode**: Added simulation capability for development testing
4. **Deployment Automation**: Scripts for automatic deployment to Prefect
5. **Security**: Proper key-based SSH authentication

## Flow Chart of Solution

```
┌────────────────────┐     ┌───────────────────────┐     ┌───────────────────────┐
│                    │     │                       │     │                       │
│  User runs         │     │  bin/setup_ec2_auth.sh│     │  bin/test_monitoring.sh
│  monitoring flow   ├────►│  Sets up SSH keys     ├────►│  Tests in simulation  │
│                    │     │  & configuration      │     │  mode                 │
└────────────────────┘     └───────────────────────┘     └───────────────────────┘
                                                               │
                                                               ▼
┌────────────────────┐     ┌───────────────────────┐     ┌───────────────────────┐
│                    │     │                       │     │                       │
│  server_utils.py   │     │  SSH connection is    │     │  bin/deploy_monitoring.sh
│  Handles SSH &     │◄────┤  established to EC2   │◄────┤  Deploys to Prefect   │
│  remote commands   │     │  instance             │     │  for scheduling       │
└────────────────────┘     └───────────────────────┘     └───────────────────────┘
          │
          ▼
┌────────────────────┐     ┌───────────────────────┐     ┌───────────────────────┐
│                    │     │                       │     │                       │
│  check_container   │     │  get_system_metrics   │     │  Discord webhook      │
│  _status() checks  ├────►│  collects performance ├────►│  shows correct server │
│  server remotely   │     │  metrics via SSH      │     │  status & metrics     │
└────────────────────┘     └───────────────────────┘     └───────────────────────┘
```

## Temporary Scripts (Now Deleted)

The following temporary scripts were used during development but have been replaced by the structured solution:

1. `test_remote_monitoring.sh`: Initial test script for remote connection
2. `prefect/remote_monitor.sh`: Early implementation of remote monitoring
3. `quick_ec2_setup.sh`: Simple SSH testing script
4. `setup_ec2_key.sh`: Initial SSH key setup script

## Current Status

The current implementation properly detects the Minecraft server as "Running" and sends accurate Discord notifications with system metrics. The system is now:

1. Modular and maintainable
2. Secure with proper SSH authentication
3. Configurable for different environments
4. Testable without requiring actual EC2 access
5. Properly scheduled with Prefect
