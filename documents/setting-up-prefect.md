# Kroni Survival - Prefect Integration Implementation Plan

## 1. Understanding Current Architecture

Your current architecture consists of:
- AWS Lightsail instance (small_3_0 - 2 vCPU, 2GB RAM) running a Minecraft server in Docker
- 20GB SSD Block Storage for the Minecraft world data
- S3 bucket for backups (kroni-survival-backups-secure)
- Cron jobs that handle:
  - Regular backups to S3 (every 3 days)
  - Lightsail snapshots (biweekly)
  - Discord notifications

The limitations you're facing include:
- Difficult to expand workflows beyond basic bash scripts
- Challenging to implement complex logic and dependencies
- Limited monitoring and observability
- Difficult to manage multiple environments (prod/non-prod)
- Challenges integrating with additional services (Datadog, Kafka)

## 2. Prefect Overview

Prefect is a workflow orchestration platform that will allow you to:
- Define workflows as Python code
- Handle dependencies between tasks
- Provide better visibility into workflow execution
- Implement conditional logic
- Scale to more complex use cases

### Prefect Deployment Options

There are two main options for Prefect:

1. **Prefect Cloud** - Managed service by Prefect
   - Pros: No infrastructure to manage, easy setup
   - Cons: Monthly costs, data leaving your infrastructure

2. **Self-hosted Prefect** - Run Prefect on your own infrastructure
   - Pros: No additional costs (beyond compute), full control
   - Cons: You manage the infrastructure, potential resource competition

For this implementation, we'll use self-hosted Prefect to avoid additional costs and keep all data within your AWS environment.

## 3. Implementation Plan

### 3.1 Architecture Overview

The updated architecture will consist of:

1. **Minecraft Server Instance** (existing)
   - Runs the Minecraft Docker container
   - Hosts game data on attached block storage
   - Continues to serve players without orchestration overhead

2. **Prefect Orchestration Instance** (new)
   - Hosts the Prefect Server and UI
   - Runs the Prefect Agent to execute workflows
   - Communicates with the Minecraft instance via SSH
   - Integrates with AWS services (S3, Lightsail API)
   - Sends notifications to Discord

3. **Shared AWS Resources**
   - S3 Bucket for backups
   - IAM user/role for AWS operations
   - Lightsail snapshots

### 3.2 Prefect Components to Install

1. **Prefect Server**: The backend that stores workflow metadata, schedules runs
2. **Prefect Agent**: Process that executes your workflows
3. **Prefect CLI**: Command-line tool for interacting with Prefect
4. **Prefect Python SDK**: For creating your workflows
5. **Remote Execution Tools**: SSH and AWS SDK for communicating with the Minecraft instance

### 3.2 Infrastructure Changes

We'll implement Option B - using a dedicated orchestration instance:

#### Dedicated Prefect Orchestration Instance
- Create a separate Lightsail instance dedicated to Prefect
- Size recommendation: `nano_3_0` (2 vCPU, 512 MB RAM)
- Region: Same as Minecraft server (ap-southeast-5)
- Blueprint: `amazon_linux_2`
- Configure network to allow communication between instances
- Benefits:
  - Complete resource isolation (no impact on Minecraft performance)
  - Better modularity and separation of concerns
  - Easier to scale orchestration separately from game server
  - Cleaner architecture for future integrations

#### Network Configuration
- Both instances should be in the same AWS region
- Create appropriate security group rules to allow communication:
  - Prefect instance needs to access Minecraft instance (SSH, Docker API)
  - Minecraft instance needs to send metrics to Prefect instance
- Open port 4200 on Prefect instance for UI access (restricted to your IP)

### 3.3 Installation Steps

#### 3.3.1 Create Prefect Orchestration Instance

1. **Create a new Lightsail instance via Terraform**:

```terraform
# Prefect orchestration instance
resource "aws_lightsail_instance" "prefect_orchestration" {
  name              = "kroni-prefect-orchestration"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"  # 2 vCPU, 512 MB RAM
  key_pair_name     = var.ssh_key_name  # Use the same SSH key as Minecraft server

  tags = {
    Name = "kroni-prefect-orchestration"
  }
}

# Static IP for Prefect instance
resource "aws_lightsail_static_ip" "prefect_orchestration" {
  name = "kroni-prefect-static-ip"
}

# Attach static IP to Prefect instance
resource "aws_lightsail_static_ip_attachment" "prefect_orchestration" {
  static_ip_name = aws_lightsail_static_ip.prefect_orchestration.name
  instance_name  = aws_lightsail_instance.prefect_orchestration.name
}

# Configure firewall for Prefect UI access
resource "aws_lightsail_instance_public_ports" "prefect_orchestration" {
  instance_name = aws_lightsail_instance.prefect_orchestration.name

  # Allow Prefect UI port
  port_info {
    protocol  = "tcp"
    from_port = 4200
    to_port   = 4200
    cidrs     = var.prefect_ui_allowed_cidrs
  }

  # Allow SSH access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }
}
```

#### 3.3.2 Install Prefect on the Orchestration Instance

1. **Install Python and Dependencies**:

```bash
# Update system packages
sudo yum update -y

# Install Python 3.8 (Amazon Linux 2)
sudo amazon-linux-extras install python3.8 -y

# Install development tools for Python package building
sudo yum install -y python38-devel gcc git jq

# Set up Python virtual environment
mkdir -p /opt/prefect
cd /opt/prefect
python3.8 -m venv venv
source venv/bin/activate

# Install Prefect and dependencies
pip install --upgrade pip
pip install "prefect==2.13.0" boto3 requests psutil paramiko docker
```

2. **Configure Prefect Server**:

```bash
# Create configuration directory
mkdir -p ~/.prefect

# Configure Prefect for local server
prefect config set PREFECT_API_URL=""

# Start the Prefect server
prefect server start &
```

3. **Create Systemd Services for Reliability**:

Create Prefect Server service:
```bash
sudo tee /etc/systemd/system/prefect-server.service > /dev/null << 'EOF'
[Unit]
Description=Prefect Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect server start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Create Prefect Agent service:
```bash
sudo tee /etc/systemd/system/prefect-agent.service > /dev/null << 'EOF'
[Unit]
Description=Prefect Agent
After=network.target prefect-server.service

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect agent start -q default
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start the services:
```bash
sudo systemctl daemon-reload
sudo systemctl enable prefect-server.service
sudo systemctl enable prefect-agent.service
sudo systemctl start prefect-server.service
sudo systemctl start prefect-agent.service
```

#### 3.3.3 Set Up SSH Key-Based Authentication

Set up passwordless SSH access from the Prefect instance to the Minecraft instance:

1. **Generate SSH key pair on Prefect instance**:

```bash
# Generate SSH key (without passphrase)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft_access -N ""

# Display the public key
cat ~/.ssh/minecraft_access.pub
```

2. **Add the public key to the Minecraft server's authorized keys**:

```bash
# On the Minecraft server instance
mkdir -p ~/.ssh
echo "PUBLIC_KEY_FROM_PREFECT_INSTANCE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

This can be automated through Terraform:

```terraform
# Add Prefect instance's SSH public key to Minecraft server
resource "null_resource" "setup_ssh_access" {
  depends_on = [
    aws_lightsail_instance.minecraft_server,
    aws_lightsail_instance.prefect_orchestration,
    aws_lightsail_static_ip_attachment.minecraft_server,
    aws_lightsail_static_ip_attachment.prefect_orchestration
  ]

  # Generate SSH key on Prefect instance
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft_access -N \"\"",
      "cat ~/.ssh/minecraft_access.pub > /tmp/prefect_pubkey.txt"
    ]
  }

  # Copy the public key from Prefect instance to local
  provisioner "local-exec" {
    command = "scp -i ~/.ssh/${var.ssh_key_name}.pem -o StrictHostKeyChecking=no ec2-user@${aws_lightsail_static_ip.prefect_orchestration.ip_address}:/tmp/prefect_pubkey.txt /tmp/prefect_pubkey.txt"
  }

  # Add the public key to Minecraft server
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "mkdir -p ~/.ssh",
      "cat /tmp/minecraft_prefect_pubkey.txt >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys"
    ]
  }

  # Copy the public key from local to Minecraft server
  provisioner "file" {
    source      = "/tmp/prefect_pubkey.txt"
    destination = "/tmp/minecraft_prefect_pubkey.txt"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }
  }
}
```

#### 3.3.4 Configure AWS Access

1. **Create a dedicated IAM user for Prefect**:

```terraform
# IAM user for Prefect orchestration
resource "aws_iam_user" "prefect_orchestration" {
  name = "kroni-prefect-orchestration-user"

  tags = {
    Name = "kroni-prefect-orchestration-user"
  }
}

# Create access key for the IAM user
resource "aws_iam_access_key" "prefect_orchestration" {
  user = aws_iam_user.prefect_orchestration.name
}

# Attach required policies
resource "aws_iam_user_policy_attachment" "prefect_s3_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn  # Reuse existing S3 policy
}

resource "aws_iam_user_policy_attachment" "prefect_lightsail_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.lightsail_snapshot_policy.arn  # Reuse existing Lightsail policy
}
```

2. **Configure AWS credentials on the Prefect instance**:

```bash
# Configure AWS CLI with Prefect IAM credentials
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
region = ap-southeast-5
EOF
```

This can be done via Terraform:

```terraform
# Configure AWS credentials on Prefect instance
resource "null_resource" "configure_aws_credentials" {
  depends_on = [
    aws_lightsail_instance.prefect_orchestration,
    aws_iam_access_key.prefect_orchestration
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
    private_key = file("~/.ssh/${var.ssh_key_name}.pem")
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/.aws",
      "cat > ~/.aws/credentials << EOF",
      "[default]",
      "aws_access_key_id = ${aws_iam_access_key.prefect_orchestration.id}",
      "aws_secret_access_key = ${aws_iam_access_key.prefect_orchestration.secret}",
      "region = ${var.aws_region}",
      "EOF",
      "chmod 600 ~/.aws/credentials"
    ]
  }
}
```

### 3.4 Workflow Implementation

Since we're now using a separate instance for Prefect, we need to modify our workflows to use SSH for remote execution on the Minecraft server. Here's how we'll implement each flow:

#### 3.4.1 Remote Execution Helper

First, let's create a helper module for executing commands remotely via SSH:

```python
# remote_executor.py
import paramiko
import logging
import io
import os
from typing import Tuple, Optional, Dict, Any

logger = logging.getLogger(__name__)

class RemoteExecutor:
    """Helper class for executing commands on the Minecraft server via SSH."""
    
    def __init__(self, hostname: str, username: str = "ec2-user", 
                 key_path: str = "~/.ssh/minecraft_access"):
        """Initialize SSH connection parameters."""
        self.hostname = hostname
        self.username = username
        self.key_path = os.path.expanduser(key_path)
        self._client = None
    
    def connect(self) -> None:
        """Establish SSH connection to the Minecraft server."""
        if self._client is not None:
            return
            
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                hostname=self.hostname,
                username=self.username,
                key_filename=self.key_path
            )
            self._client = client
            logger.info(f"Connected to {self.username}@{self.hostname}")
        except Exception as e:
            logger.error(f"Failed to connect to {self.hostname}: {e}")
            raise
    
    def disconnect(self) -> None:
        """Close the SSH connection."""
        if self._client:
            self._client.close()
            self._client = None
            logger.info(f"Disconnected from {self.hostname}")
    
    def execute_command(self, command: str) -> Tuple[int, str, str]:
        """
        Execute a command on the remote server.
        
        Args:
            command: The command to execute
            
        Returns:
            Tuple of (exit_code, stdout, stderr)
        """
        if not self._client:
            self.connect()
            
        try:
            logger.info(f"Executing command: {command}")
            stdin, stdout, stderr = self._client.exec_command(command)
            exit_code = stdout.channel.recv_exit_status()
            
            stdout_str = stdout.read().decode('utf-8')
            stderr_str = stderr.read().decode('utf-8')
            
            if exit_code != 0:
                logger.warning(f"Command exited with code {exit_code}")
                logger.warning(f"stderr: {stderr_str}")
            else:
                logger.info(f"Command completed successfully")
                
            return exit_code, stdout_str, stderr_str
        except Exception as e:
            logger.error(f"Failed to execute command: {e}")
            return 1, "", str(e)
    
    def check_docker_container(self, container_name: str) -> bool:
        """
        Check if a Docker container is running.
        
        Args:
            container_name: Name of the container to check
            
        Returns:
            True if the container is running, False otherwise
        """
        command = f"docker ps --filter name={container_name} --format '{{{{.Names}}}}'"
        exit_code, stdout, _ = self.execute_command(command)
        
        if exit_code != 0:
            return False
            
        return container_name in stdout.strip()
    
    def docker_stop_container(self, container_name: str) -> bool:
        """
        Stop a Docker container.
        
        Args:
            container_name: Name of the container to stop
            
        Returns:
            True if successful, False otherwise
        """
        command = f"docker stop {container_name}"
        exit_code, _, _ = self.execute_command(command)
        return exit_code == 0
    
    def docker_start_container(self, container_name: str) -> bool:
        """
        Start a Docker container.
        
        Args:
            container_name: Name of the container to start
            
        Returns:
            True if successful, False otherwise
        """
        command = f"docker start {container_name}"
        exit_code, _, _ = self.execute_command(command)
        return exit_code == 0
    
    def create_backup(self, world_path: str, backup_dir: str = "/tmp") -> Optional[str]:
        """
        Create a backup of the Minecraft world on the remote server.
        
        Args:
            world_path: Path to the Minecraft world directory
            backup_dir: Directory to store the backup file
            
        Returns:
            Path to the backup file if successful, None otherwise
        """
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_filename = f"minecraft-world-backup-{timestamp}.tar.gz"
        backup_path = f"{backup_dir}/{backup_filename}"
        
        # Create backup directory if it doesn't exist
        self.execute_command(f"mkdir -p {backup_dir}")
        
        # Check if world directory exists
        _, stdout, _ = self.execute_command(f"ls -la {world_path}")
        if "No such file or directory" in stdout:
            logger.error(f"World directory {world_path} does not exist!")
            return None
        
        # Create backup
        command = f"tar -czf {backup_path} -C $(dirname {world_path}) $(basename {world_path})"
        exit_code, _, stderr = self.execute_command(command)
        
        if exit_code != 0:
            logger.error(f"Failed to create backup: {stderr}")
            return None
            
        logger.info(f"Backup created at {backup_path}")
        return backup_path
    
    def download_file(self, remote_path: str, local_path: str) -> bool:
        """
        Download a file from the remote server.
        
        Args:
            remote_path: Path to the file on the remote server
            local_path: Path where the file should be saved locally
            
        Returns:
            True if successful, False otherwise
        """
        if not self._client:
            self.connect()
            
        try:
            sftp = self._client.open_sftp()
            sftp.get(remote_path, local_path)
            sftp.close()
            
            logger.info(f"Downloaded {remote_path}

#### Snapshot Flow (Lightsail Instance and Volume Snapshots)

```python
from prefect import flow, task
import boto3
import datetime
import logging
import requests

logger = logging.getLogger(__name__)

@task(name="Create Lightsail Snapshots")
def create_lightsail_snapshots(instance_name: str, disk_name: str, region: str):
    """Create snapshots of the Lightsail instance and disk."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    instance_snapshot_name = f"{instance_name}-{timestamp}"
    disk_snapshot_name = f"{disk_name}-{timestamp}"
    
    try:
        logger.info("Creating Lightsail snapshots...")
        lightsail_client = boto3.client('lightsail', region_name=region)
        
        # Create instance snapshot
        logger.info(f"Creating instance snapshot: {instance_snapshot_name}")
        lightsail_client.create_instance_snapshot(
            instanceName=instance_name,
            instanceSnapshotName=instance_snapshot_name
        )
        
        # Create disk snapshot
        logger.info(f"Creating disk snapshot: {disk_snapshot_name}")
        lightsail_client.create_disk_snapshot(
            diskName=disk_name,
            diskSnapshotName=disk_snapshot_name
        )
        
        logger.info("Snapshots created successfully")
        return True, instance_snapshot_name, disk_snapshot_name
    except Exception as e:
        logger.error(f"Failed to create Lightsail snapshots: {e}")
        return False, "", ""

@task(name="Clean Up Old Snapshots")
def cleanup_old_snapshots(instance_name: str, disk_name: str, region: str, retention_days: int):
    """Clean up old Lightsail snapshots based on retention policy."""
    try:
        logger.info(f"Cleaning up old snapshots (older than {retention_days} days)...")
        
        lightsail_client = boto3.client('lightsail', region_name=region)
        cutoff_date = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=retention_days)
        deleted_count = 0
        
        # Clean up instance snapshots
        instance_snapshots = lightsail_client.get_instance_snapshots()
        for snapshot in instance_snapshots['instanceSnapshots']:
            if snapshot['fromInstanceName'] == instance_name and snapshot['createdAt'] < cutoff_date:
                logger.info(f"Deleting old instance snapshot: {snapshot['name']}")
                lightsail_client.delete_instance_snapshot(instanceSnapshotName=snapshot['name'])
                deleted_count += 1
                
        # Clean up disk snapshots
        disk_snapshots = lightsail_client.get_disk_snapshots()
        for snapshot in disk_snapshots['diskSnapshots']:
            if snapshot['fromDiskName'] == disk_name and snapshot['createdAt'] < cutoff_date:
                logger.info(f"Deleting old disk snapshot: {snapshot['name']}")
                lightsail_client.delete_disk_snapshot(diskSnapshotName=snapshot['name'])
                deleted_count += 1
                
        logger.info(f"Deleted {deleted_count} old snapshots")
        return deleted_count
    except Exception as e:
        logger.error(f"Failed to clean up old snapshots: {e}")
        return 0

@task(name="Send Discord Notification")
def send_discord_notification(webhook_url: str, status: str, message: str, details: dict = None):
    """Send notification to Discord webhook."""
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping notification")
        return False
    
    try:
        logger.info(f"Sending Discord notification: {status}")
        
        # Set emoji based on status
        emoji = "✅" if status == "SUCCESS" else "❌"
        
        # Set color based on status (success: green, failure: red)
        color = 5763719 if status == "SUCCESS" else 15548997
        
        # Create payload with embed
        payload = {
            "embeds": [
                {
                    "title": f"{emoji} Kroni Survival - {status}",
                    "description": message,
                    "color": color,
                    "timestamp": datetime.datetime.now().isoformat(),
                    "footer": {
                        "text": "Kroni Survival Minecraft Server"
                    }
                }
            ]
        }
        
        # Add fields if details are provided
        if details:
            fields = []
            for key, value in details.items():
                fields.append({
                    "name": key,
                    "value": str(value),
                    "inline": True
                })
            payload["embeds"][0]["fields"] = fields
        
        # Send the notification
        response = requests.post(webhook_url, json=payload)
        response.raise_for_status()
        
        logger.info("Discord notification sent successfully")
        return True
    except Exception as e:
        logger.error(f"Failed to send Discord notification: {e}")
        return False

@flow(name="Lightsail Snapshot Flow")
def snapshot_flow(config: dict = None):
    """
    Main flow for creating and managing Lightsail snapshots.
    
    Args:
        config: Configuration dictionary with the following keys:
            - instance_name: Name of the Lightsail instance
            - disk_name: Name of the Lightsail disk
            - region: AWS region
            - retention_days: Number of days to retain snapshots
            - discord_webhook_url: Discord webhook URL for notifications
    """
    # Default configuration
    default_config = {
        "instance_name": "kroni-survival-server",
        "disk_name": "kroni-survival-volume",
        "region": "ap-southeast-5",
        "retention_days": 30,
        "discord_webhook_url": "",
    }
    
    # Merge provided config with defaults
    cfg = default_config.copy()
    if config:
        cfg.update(config)
    
    # Create snapshots
    snapshot_success, instance_snapshot, disk_snapshot = create_lightsail_snapshots(
        cfg["instance_name"],
        cfg["disk_name"],
        cfg["region"]
    )
    
    # Clean up old snapshots
    deleted_snapshots = cleanup_old_snapshots(
        cfg["instance_name"],
        cfg["disk_name"],
        cfg["region"],
        cfg["retention_days"]
    )
    
    # Prepare notification details
    notification_details = {
        "Instance Snapshot": instance_snapshot if snapshot_success else "Failed",
        "Disk Snapshot": disk_snapshot if snapshot_success else "Failed",
        "Deleted Snapshots": deleted_snapshots,
        "Timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    # Determine status
    if snapshot_success:
        status = "SUCCESS"
        message = "Lightsail snapshots created successfully!"
    else:
        status = "FAILURE"
        message = "Failed to create Lightsail snapshots."
    
    # Send notification
    send_discord_notification(
        cfg["discord_webhook_url"],
        status,
        message,
        notification_details
    )
    
    return status
```

#### Server Monitoring Flow

```python
from prefect import flow, task
import psutil
import subprocess
import requests
import datetime
import json
import logging
import boto3

logger = logging.getLogger(__name__)

@task(name="Check System Resources")
def check_system_resources():
    """Check the system's CPU, memory, and disk usage."""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory_percent = psutil.virtual_memory().percent
    disk_percent = psutil.disk_usage('/').percent
    
    logger.info(f"System resources: CPU: {cpu_percent}%, Memory: {memory_percent}%, Disk: {disk_percent}%")
    
    return {
        "cpu_percent": cpu_percent,
        "memory_percent": memory_percent,
        "disk_percent": disk_percent,
        "timestamp": datetime.datetime.now().isoformat()
    }

@task(name="Check Minecraft Server Status")
def check_minecraft_status():
    """Check if the Minecraft server is running and get player count."""
    try:
        # Check if the container is running
        docker_ps_result = subprocess.run(
            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=True
        )
        is_running = "minecraft-server" in docker_ps_result.stdout
        
        player_count = 0
        if is_running:
            # Get the server logs to check for player count
            # This is a simple approach - a more robust solution would use the RCON protocol
            docker_logs_result = subprocess.run(
                ["docker", "logs", "--tail", "100", "minecraft-server"],
                capture_output=True,
                text=True,
                check=True
            )
            
            # This is a very basic way to estimate player count - might need adjustment
            player_count = docker_logs_result.stdout.count("joined the game") - docker_logs_result.stdout.count("left the game")
            if player_count < 0:
                player_count = 0
        
        return {
            "is_running": is_running,
            "player_count": player_count,
            "timestamp": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Failed to check Minecraft server status: {e}")
        return {
            "is_running": False,
            "player_count": 0,
            "error": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

@task(name="Check Instance Health")
def check_instance_health(instance_name: str, region: str):
    """Check the Lightsail instance health."""
    try:
        lightsail_client = boto3.client('lightsail', region_name=region)
        response = lightsail_client.get_instance(instanceName=instance_name)
        
        state = response['instance']['state']['name']
        public_ip = response['instance']['publicIpAddress']
        
        return {
            "state": state,
            "public_ip": public_ip,
            "timestamp": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Failed to check instance health: {e}")
        return {
            "state": "unknown",
            "error": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

@task(name="Send Alert")
def send_alert(webhook_url: str, alert_data: dict, threshold_config: dict):
    """Send alert to Discord if any metrics exceed thresholds."""
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping alert")
        return False
    
    # Check if any metrics exceed thresholds
    alerts = []
    
    # Check system resources
    if alert_data["system"]["cpu_percent"] > threshold_config["cpu_percent"]:
        alerts.append(f"⚠️ CPU usage is high: {alert_data['system']['cpu_percent']}% (threshold: {threshold_config['cpu_percent']}%)")
    
    if alert_data["system"]["memory_percent"] > threshold_config["memory_percent"]:
        alerts.append(f"⚠️ Memory usage is high: {alert_data['system']['memory_percent']}% (threshold: {threshold_config['memory_percent']}%)")
    
    if alert_data["system"]["disk_percent"] > threshold_config["disk_percent"]:
        alerts.append(f"⚠️ Disk usage is high: {alert_data['system']['disk_percent']}% (threshold: {threshold_config['disk_percent']}%)")
    
    # Check server status
    if not alert_data["minecraft"]["is_running"]:
        alerts.append("🛑 Minecraft server is not running!")
    
    # Send alert if any thresholds are exceeded
    if alerts:
        try:
            logger.info(f"Sending alert to Discord: {', '.join(alerts)}")
            
            # Create message with all alerts
            message = "\n".join(alerts)
            
            # Add instance info
            message += f"\n\nInstance: {alert_data['instance']['state']} ({alert_data['instance']['public_ip']})"
            
            # Add player count
            if alert_data["minecraft"]["is_running"]:
                message += f"\nPlayers online: {alert_data['minecraft']['player_count']}"
            
            # Create payload
            payload = {
                "embeds": [
                    {
                        "title": "🚨 Kroni Survival - Server Alert",
                        "description": message,
                        "color": 16711680,  # Red
                        "timestamp": datetime.datetime.now().isoformat(),
                        "footer": {
                            "text": "Kroni Survival Monitoring"
                        }
                    }
                ]
            }
            
            # Send the alert
            response = requests.post(webhook_url, json=payload)
            response.raise_for_status()
            
            logger.info("Alert sent successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to send alert: {e}")
            return False
    else:
        logger.info("No alerts to send")
        return False

@flow(name="Server Monitoring Flow")
def server_monitoring_flow(config: dict = None):
    """
    Main flow for monitoring the Minecraft server and infrastructure.
    
    Args:
        config: Configuration dictionary with the following keys:
            - instance_name: Name of the Lightsail instance
            - region: AWS region
            - discord_webhook_url: Discord webhook URL for alerts
            - thresholds: Dictionary of alert thresholds
    """
    # Default configuration
    default_config = {
        "instance_name": "kroni-survival-server",
        "region": "ap-southeast-5",
        "discord_webhook_url": "",
        "thresholds": {
            "cpu_percent": 90,
            "memory_percent": 90,
            "disk_percent": 85
        }
    }
    
    # Merge provided config with defaults
    cfg = default_config.copy()
    if config:
        cfg.update(config)
        # Ensure thresholds dict exists and is properly merged
        if "thresholds" in config:
            cfg["thresholds"] = {**default_config["thresholds"], **config["thresholds"]}
    
    # Collect monitoring data
    system_data = check_system_resources()
    minecraft_data = check_minecraft_status()
    instance_data = check_instance_health(cfg["instance_name"], cfg["region"])
    
    # Combine all data
    monitoring_data = {
        "system": system_data,
        "minecraft": minecraft_data,
        "instance": instance_data
    }
    
    # Check for alerts
    send_alert(cfg["discord_webhook_url"], monitoring_data, cfg["thresholds"])
    
    return monitoring_data
```

### 3.5 Deployment Setup

Now that we have our workflows defined, let's create the deployment scripts that will schedule them to run automatically.

#### 3.5.1 Environment Configuration

First, let's create an environment file to store configuration:

```bash
# /opt/prefect/.env
MINECRAFT_HOST=kroni-survival-server
MINECRAFT_INSTANCE_NAME=kroni-survival-server
MINECRAFT_VOLUME_NAME=kroni-survival-volume
MINECRAFT_WORLD_PATH=/data/world
MINECRAFT_DATA_PATH=/data
S3_BUCKET=kroni-survival-backups-secure
AWS_REGION=ap-southeast-5
DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/your-webhook-url
```

#### 3.5.2 Backup Flow Deployment

```python
# deploy_backup_flow.py
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from backup_flow import backup_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "minecraft_host": os.getenv("MINECRAFT_HOST"),
    "world_path": os.getenv("MINECRAFT_WORLD_PATH"),
    "s3_bucket": os.getenv("S3_BUCKET"),
    "region": os.getenv("AWS_REGION"),
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL")
}

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=backup_flow,
    name="scheduled-minecraft-backup",
    schedule=CronSchedule(cron="0 0 */3 * *"),  # Every 3 days at midnight
    parameters={"config": config},
    tags=["minecraft", "backup"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Minecraft backup flow deployment created successfully.")
```

#### 3.5.3 Snapshot Flow Deployment

```python
# deploy_snapshot_flow.py
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from snapshot_flow import snapshot_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "instance_name": os.getenv("MINECRAFT_INSTANCE_NAME"),
    "disk_name": os.getenv("MINECRAFT_VOLUME_NAME"),
    "region": os.getenv("AWS_REGION"),
    "retention_days": 30,  # Keep snapshots for 30 days
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL")
}

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=snapshot_flow,
    name="scheduled-lightsail-snapshots",
    schedule=CronSchedule(cron="0 0 */14 * *"),  # Biweekly at midnight
    parameters={"config": config},
    tags=["minecraft", "snapshot", "lightsail"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Lightsail snapshot flow deployment created successfully.")
```

#### 3.5.4 Monitoring Flow Deployment

```python
# deploy_monitoring_flow.py
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import IntervalSchedule
from datetime import timedelta
from server_monitoring_flow import server_monitoring_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "minecraft_host": os.getenv("MINECRAFT_HOST"),
    "instance_name": os.getenv("MINECRAFT_INSTANCE_NAME"),
    "region": os.getenv("AWS_REGION"),
    "data_path": os.getenv("MINECRAFT_DATA_PATH"),
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL"),
    "thresholds": {
        "cpu_percent": 90,
        "memory_percent": 90,
        "disk_percent": 85
    }
}

# Create a deployment with an interval schedule
deployment = Deployment.build_from_flow(
    flow=server_monitoring_flow,
    name="scheduled-server-monitoring",
    schedule=IntervalSchedule(interval=timedelta(minutes=30)),  # Every 30 minutes
    parameters={"config": config},
    tags=["minecraft", "monitoring"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Server monitoring flow deployment created successfully.")
```

### 3.6 Terraform Integration

Let's update our Terraform configuration to provision both instances and set up the Prefect orchestration:

#### 3.6.1 Main Terraform Configuration

```terraform
# main.tf

# Existing Minecraft server resources...

# Create a dedicated Prefect orchestration instance
resource "aws_lightsail_instance" "prefect_orchestration" {
  name              = "kroni-prefect-orchestration"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"  # 2 vCPU, 512 MB RAM
  key_pair_name     = var.ssh_key_name  # Use the same SSH key as Minecraft server

  tags = {
    Name = "kroni-prefect-orchestration"
  }
}

# Static IP for Prefect instance
resource "aws_lightsail_static_ip" "prefect_orchestration" {
  name = "kroni-prefect-static-ip"
}

# Attach static IP to Prefect instance
resource "aws_lightsail_static_ip_attachment" "prefect_orchestration" {
  static_ip_name = aws_lightsail_static_ip.prefect_orchestration.name
  instance_name  = aws_lightsail_instance.prefect_orchestration.name
}

# Configure firewall for Prefect UI access
resource "aws_lightsail_instance_public_ports" "prefect_orchestration" {
  instance_name = aws_lightsail_instance.prefect_orchestration.name

  # Allow Prefect UI port
  port_info {
    protocol  = "tcp"
    from_port = 4200
    to_port   = 4200
    cidrs     = var.prefect_ui_allowed_cidrs
  }

  # Allow SSH access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }
}

# IAM user for Prefect orchestration
resource "aws_iam_user" "prefect_orchestration" {
  name = "kroni-prefect-orchestration-user"

  tags = {
    Name = "kroni-prefect-orchestration-user"
  }
}

# Create access key for the Prefect IAM user
resource "aws_iam_access_key" "prefect_orchestration" {
  user = aws_iam_user.prefect_orchestration.name
}

# Attach S3 backup policy to Prefect IAM user
resource "aws_iam_user_policy_attachment" "prefect_s3_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn  # Reuse existing S3 policy
}

# Attach Lightsail snapshot policy to Prefect IAM user
resource "aws_iam_user_policy_attachment" "prefect_lightsail_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.lightsail_snapshot_policy.arn  # Reuse existing Lightsail policy
}

locals {
  # Prefect setup script
  prefect_setup_script = templatefile("${path.module}/prefect_setup.sh", {
    minecraft_host       = aws_lightsail_instance.minecraft_server.name
    minecraft_ip         = aws_lightsail_static_ip.minecraft_server.ip_address
    minecraft_instance   = var.lightsail_instance_name
    minecraft_volume     = var.lightsail_volume_name
    minecraft_world_path = var.minecraft_world_path
    minecraft_data_path  = var.lightsail_volume_mount_path
    s3_bucket            = var.s3_backup_bucket_name
    aws_region           = var.aws_region
    aws_access_key       = aws_iam_access_key.prefect_orchestration.id
    aws_secret_key       = aws_iam_access_key.prefect_orchestration.secret
    discord_webhook_url  = var.discord_webhook_url
    backup_schedule      = var.backup_schedule_cron
    snapshot_schedule    = var.snapshot_schedule_cron
    monitoring_interval  = var.monitoring_interval
  })
}

# Provision the Prefect orchestration instance
resource "null_resource" "provision_prefect" {
  depends_on = [
    aws_lightsail_instance.prefect_orchestration,
    aws_lightsail_static_ip_attachment.prefect_orchestration,
    aws_iam_user_policy_attachment.prefect_s3_attachment,
    aws_iam_user_policy_attachment.prefect_lightsail_attachment
  ]

  triggers = {
    instance_id = aws_lightsail_instance.prefect_orchestration.id
    script_hash = sha256(local.prefect_setup_script)
  }

  # Connect to the Prefect instance via SSH
  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
    private_key = file("~/.ssh/${var.ssh_key_name}.pem")
  }

  # Create directories for Prefect flows
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/prefect/flows",
      "echo 'Created Prefect directories'"
    ]
  }

  # Copy Python flow files to the instance
  provisioner "file" {
    source      = "${path.module}/../prefect/remote_executor.py"
    destination = "/tmp/prefect/flows/remote_executor.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/backup_flow.py"
    destination = "/tmp/prefect/flows/backup_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/snapshot_flow.py" 
    destination = "/tmp/prefect/flows/snapshot_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/server_monitoring_flow.py"
    destination = "/tmp/prefect/flows/server_monitoring_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/deploy_backup_flow.py"
    destination = "/tmp/prefect/flows/deploy_backup_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/deploy_snapshot_flow.py" 
    destination = "/tmp/prefect/flows/deploy_snapshot_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/deploy_monitoring_flow.py"
    destination = "/tmp/prefect/flows/deploy_monitoring_flow.py"
  }

  # Copy the Prefect setup script
  provisioner "file" {
    content     = local.prefect_setup_script
    destination = "/tmp/prefect_setup.sh"
  }

  # Execute the Prefect setup script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/prefect_setup.sh",
      "sudo /tmp/prefect_setup.sh"
    ]
  }
}

# Set up SSH key-based authentication between Prefect and Minecraft instances
resource "null_resource" "setup_ssh_access" {
  depends_on = [
    aws_lightsail_instance.minecraft_server,
    aws_lightsail_instance.prefect_orchestration,
    aws_lightsail_static_ip_attachment.minecraft_server,
    aws_lightsail_static_ip_attachment.prefect_orchestration,
    null_resource.provision_prefect
  ]

  # Generate SSH key on Prefect instance
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft_access -N \"\"",
      "cat ~/.ssh/minecraft_access.pub > /tmp/prefect_pubkey.txt"
    ]
  }

  # Copy the public key from Prefect instance to local
  provisioner "local-exec" {
    command = "scp -i ~/.ssh/${var.ssh_key_name}.pem -o StrictHostKeyChecking=no ec2-user@${aws_lightsail_static_ip.prefect_orchestration.ip_address}:/tmp/prefect_pubkey.txt /tmp/prefect_pubkey.txt"
  }

  # Copy the public key from local to Minecraft server
  provisioner "file" {
    source      = "/tmp/prefect_pubkey.txt"
    destination = "/tmp/minecraft_prefect_pubkey.txt"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }
  }

  # Add the public key to Minecraft server
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "mkdir -p ~/.ssh",
      "cat /tmp/minecraft_prefect_pubkey.txt >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys"
    ]
  }
}
```

#### 3.6.2 Variables File

```terraform
# variables.tf

# ... Existing variables ...

# Prefect-specific variables
variable "prefect_ui_allowed_cidrs" {
  description = "CIDR blocks allowed for Prefect UI access"
  type        = list(string)
  default     = ["0.0.0.0/0"]  # Should be restricted to your IP in production
}

variable "monitoring_interval" {
  description = "Interval in minutes for server monitoring"
  type        = number
  default     = 30
}
```

#### 3.6.3 Prefect Setup Script

```bash
#!/bin/bash
set -e

# Variables passed from Terraform
MINECRAFT_HOST="${minecraft_host}"
MINECRAFT_IP="${minecraft_ip}"
MINECRAFT_INSTANCE="${minecraft_instance}"
MINECRAFT_VOLUME="${minecraft_volume}"
MINECRAFT_WORLD_PATH="${minecraft_world_path}"
MINECRAFT_DATA_PATH="${minecraft_data_path}"
S3_BUCKET="${s3_bucket}"
AWS_REGION="${aws_region}"
AWS_ACCESS_KEY="${aws_access_key}"
AWS_SECRET_KEY="${aws_secret_key}"
DISCORD_WEBHOOK_URL="${discord_webhook_url}"
BACKUP_SCHEDULE="${backup_schedule}"
SNAPSHOT_SCHEDULE="${snapshot_schedule}"
MONITORING_INTERVAL="${monitoring_interval}"

echo "=== Starting Kroni Survival Prefect Orchestration Setup ==="

# Update system packages
sudo yum update -y

# Install Python 3.8 and dependencies
sudo amazon-linux-extras install python3.8 -y
sudo yum install -y python38-devel gcc git jq

# Create Python virtual environment
mkdir -p /opt/prefect
cd /opt/prefect
python3.8 -m venv venv
source venv/bin/activate

# Install Prefect and dependencies
pip install --upgrade pip
pip install "prefect==2.13.0" boto3 requests psutil paramiko python-dotenv

# Configure AWS credentials
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY
aws_secret_access_key = $AWS_SECRET_KEY
region = $AWS_REGION
EOF
chmod 600 ~/.aws/credentials

# Create environment file
cat > /opt/prefect/.env << EOF
MINECRAFT_HOST=$MINECRAFT_HOST
MINECRAFT_IP=$MINECRAFT_IP
MINECRAFT_INSTANCE_NAME=$MINECRAFT_INSTANCE
MINECRAFT_VOLUME_NAME=$MINECRAFT_VOLUME
MINECRAFT_WORLD_PATH=$MINECRAFT_WORLD_PATH
MINECRAFT_DATA_PATH=$MINECRAFT_DATA_PATH
S3_BUCKET=$S3_BUCKET
AWS_REGION=$AWS_REGION
DISCORD_WEBHOOK_URL=$DISCORD_WEBHOOK_URL
EOF
chmod 600 /opt/prefect/.env

# Create Prefect server configuration
mkdir -p ~/.prefect
prefect config set PREFECT_API_URL=""

# Create Prefect flows directory
mkdir -p /opt/prefect/flows

# Copy flow files from temporary location
cp -r /tmp/prefect/flows/* /opt/prefect/flows/

# Create systemd service file for Prefect server
cat > /tmp/prefect-server.service << EOF
[Unit]
Description=Prefect Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect server start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/prefect-server.service /etc/systemd/system/

# Create systemd service file for Prefect agent
cat > /tmp/prefect-agent.service << EOF
[Unit]
Description=Prefect Agent
After=network.target prefect-server.service

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect agent start -q default
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/prefect-agent.service /etc/systemd/system/

# Enable and start Prefect services
sudo systemctl daemon-reload
sudo systemctl enable prefect-server
sudo systemctl enable prefect-agent
sudo systemctl start prefect-server

# Wait for Prefect server to start
echo "Waiting for Prefect server to start..."
sleep 30

# Deploy Prefect flows
cd /opt/prefect/flows
source /opt/prefect/venv/bin/activate

# Generate deployment script for backup flow
cat > deploy_backup_flow.py << EOF
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from backup_flow import backup_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "minecraft_host": os.getenv("MINECRAFT_IP"),  # Use IP address for direct connection
    "world_path": os.getenv("MINECRAFT_WORLD_PATH"),
    "s3_bucket": os.getenv("S3_BUCKET"),
    "region": os.getenv("AWS_REGION"),
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL")
}

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=backup_flow,
    name="scheduled-minecraft-backup",
    schedule=CronSchedule(cron="$BACKUP_SCHEDULE"),
    parameters={"config": config},
    tags=["minecraft", "backup"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Minecraft backup flow deployment created successfully.")
EOF

# Generate deployment script for snapshot flow
cat > deploy_snapshot_flow.py << EOF
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from snapshot_flow import snapshot_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "instance_name": os.getenv("MINECRAFT_INSTANCE_NAME"),
    "disk_name": os.getenv("MINECRAFT_VOLUME_NAME"),
    "region": os.getenv("AWS_REGION"),
    "retention_days": 30,  # Keep snapshots for 30 days
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL")
}

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=snapshot_flow,
    name="scheduled-lightsail-snapshots",
    schedule=CronSchedule(cron="$SNAPSHOT_SCHEDULE"),
    parameters={"config": config},
    tags=["minecraft", "snapshot", "lightsail"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Lightsail snapshot flow deployment created successfully.")
EOF

# Generate deployment script for monitoring flow
cat > deploy_monitoring_flow.py << EOF
import os
from dotenv import load_dotenv
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import IntervalSchedule
from datetime import timedelta
from server_monitoring_flow import server_monitoring_flow

# Load environment variables
load_dotenv("/opt/prefect/.env")

# Create configuration from environment variables
config = {
    "minecraft_host": os.getenv("MINECRAFT_IP"),  # Use IP address for direct connection
    "instance_name": os.getenv("MINECRAFT_INSTANCE_NAME"),
    "region": os.getenv("AWS_REGION"),
    "data_path": os.getenv("MINECRAFT_DATA_PATH"),
    "discord_webhook_url": os.getenv("DISCORD_WEBHOOK_URL"),
    "thresholds": {
        "cpu_percent": 90,
        "memory_percent": 90,
        "disk_percent": 85
    }
}

# Create a deployment with an interval schedule
deployment = Deployment.build_from_flow(
    flow=server_monitoring_flow,
    name="scheduled-server-monitoring",
    schedule=IntervalSchedule(interval=timedelta(minutes=$MONITORING_INTERVAL)),
    parameters={"config": config},
    tags=["minecraft", "monitoring"]
)

if __name__ == "__main__":
    deployment.apply()
    print("Server monitoring flow deployment created successfully.")
EOF

# Start Prefect agent
sudo systemctl start prefect-agent

# Wait for Prefect agent to start
echo "Waiting for Prefect agent to start..."
sleep 10

# Deploy the flows
python deploy_backup_flow.py
python deploy_snapshot_flow.py
python deploy_monitoring_flow.py

# Create a script to check Prefect status
cat > /opt/prefect/check_prefect.sh << 'EOF'
#!/bin/bash
cd /opt/prefect
source venv/bin/activate

echo "=== Prefect Server Status ==="
systemctl status prefect-server

echo -e "\n=== Prefect Agent Status ==="
systemctl status prefect-agent

echo -e "\n=== Prefect Deployments ==="
prefect deployment ls

echo -e "\n=== Prefect UI Address ==="
echo "http://$(curl -s http://checkip.amazonaws.com):4200"
EOF
chmod +x /opt/prefect/check_prefect.sh

echo "=== Prefect orchestration setup completed! ==="
echo "The Prefect UI is available at http://$(curl -s http://checkip.amazonaws.com):4200"
```

### 3.7 GitHub Actions Integration

Update your GitHub Actions workflow to deploy both Minecraft and Prefect instances:

```yaml
# .github/workflows/terraform.yml

# ... Existing configuration ...

jobs:
  terraform:
    name: "Terraform"
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ./terraform

    steps:
      # ... Existing steps ...

      # Copy Prefect files to terraform directory
      - name: Copy Prefect files to terraform directory
        run: |
          mkdir -p ./prefect/flows
          cp ../prefect/*.py ./prefect/flows/

      # ... Existing steps ...

  verify_prefect:
    name: "Verify Prefect Deployments"
    needs: terraform
    runs-on: ubuntu-latest
    if: github.event.inputs.action == 'apply'
    
    steps:
      - name: Checkout
        uses: actions/checkout@v3
        
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
          
      - name: Get Prefect instance IP
        id: prefect_ip
        run: |
          PREFECT_IP=$(terraform -chdir=./terraform output -raw prefect_orchestration_ip)
          echo "PREFECT_IP=$PREFECT_IP" >> $GITHUB_ENV
          
      - name: Verify Prefect deployments
        run: |
          # Wait for deployments to be fully created
          sleep 60
          
          # SSH to check Prefect deployments
          ssh -i ~/.ssh/${{ secrets.SSH_KEY_NAME }}.pem -o StrictHostKeyChecking=no ec2-user@$PREFECT_IP "/opt/prefect/check_prefect.sh"
```

## 4. Implementation Roadmap

### Phase 1: Infrastructure Setup (Days 1-2)
- Create Terraform code for the Prefect orchestration instance
- Set up SSH key-based authentication between instances
- Configure IAM permissions for Prefect
- Test basic connectivity between instances

### Phase 2: Core Workflow Development (Days 3-5)
- Develop and test the RemoteExecutor class
- Create and test the backup flow
- Create and test the snapshot flow
- Verify both flows work end-to-end with manual execution

### Phase 3: Monitoring Implementation (Days 6-7)
- Develop and test the server monitoring flow
- Configure appropriate thresholds
- Test alerts and notifications
- Set up appropriate schedule

### Phase 4: Deployment Automation (Days 8-10)
- Create automated deployment scripts
- Set up scheduling for all flows
- Test full automation of workflows
- Verify Discord notifications

### Phase 5: CI/CD Integration (Days 11-12)
- Update GitHub Actions workflow
- Test automated deployment of both instances
- Verify Prefect deployments are created correctly
- Document CI/CD process

### Phase
 6: Testing and Documentation (Days 13-14)
- Perform comprehensive testing of all workflows
- Create detailed documentation
- Set up monitoring for the Prefect instance itself
- Create runbook for common operations

## 5. Advanced Features (Future Phases)

After the initial implementation, consider these additional modular components:

### 5.1 Multi-Environment Support
- Create separate Minecraft instances for different environments (dev, test, prod)
- Implement workflows to manage and sync between environments
- Use Prefect to orchestrate promotion between environments

### 5.2 Datadog Integration
- Set up a Datadog agent on the Minecraft server
- Create Prefect flows to collect and send custom metrics to Datadog
- Build dashboards in Datadog for monitoring

### 5.3 Kafka Integration
- Deploy a Kafka instance or use AWS MSK
- Create Prefect flows that produce events to Kafka
- Implement consumers for the events (e.g., for analytics)

### 5.4 Advanced Prefect Features
- Implement custom storage for flow code (e.g., GitHub)
- Set up Prefect Cloud for remote monitoring (optional)
- Create custom task runners for better performance

## 6. Monitoring and Maintenance

### 6.1 Prefect Health Monitoring
- Monitor the Prefect agent and server health
- Set up alerts for failed workflows
- Regularly check for failed runs in the Prefect UI

### 6.2 Common Maintenance Tasks

**Updating Prefect**
```bash
# Connect to the Prefect instance
ssh -i ~/.ssh/your-key.pem ec2-user@prefect-instance-ip

# Activate the virtual environment
cd /opt/prefect
source venv/bin/activate

# Update Prefect
pip install --upgrade prefect

# Restart services
sudo systemctl restart prefect-server
sudo systemctl restart prefect-agent
```

**Viewing Flow Run Logs**
```bash
# Connect to the Prefect instance
ssh -i ~/.ssh/your-key.pem ec2-user@prefect-instance-ip

# Activate the virtual environment
cd /opt/prefect
source venv/bin/activate

# List recent flow runs
prefect flow-run ls

# View logs for a specific run
prefect flow-run logs <run-id>
```

**Running a Flow Manually**
```bash
# Connect to the Prefect instance
ssh -i ~/.ssh/your-key.pem ec2-user@prefect-instance-ip

# Activate the virtual environment
cd /opt/prefect
source venv/bin/activate

# Run a deployment
prefect deployment run scheduled-minecraft-backup
```

## 7. Conclusion

This implementation plan provides a comprehensive approach to setting up a modular Prefect orchestration system for your Minecraft server. By using a separate instance for Prefect, you achieve better resource isolation and a cleaner architectural separation of concerns.

The key benefits of this implementation include:

1. **Complete Resource Isolation**: The Minecraft server and Prefect orchestration run on separate instances, ensuring game performance isn't affected by workflow processes.

2. **Clean Modular Architecture**: Each component has a well-defined role, making the system easier to maintain and extend.

3. **Centralized Workflow Management**: All workflows are managed from a single point, providing better visibility and control.

4. **Future Extensibility**: The modular approach makes it easier to add new components like Datadog or Kafka in the future.

5. **Improved Reliability**: Each instance can be scaled and maintained independently, improving overall system reliability.

By following this implementation plan, you'll be able to replace your current cron-based system with a more powerful workflow orchestration solution while maintaining complete separation between the game server and the orchestration logic.
# Kroni Survival - Prefect Integration Implementation Plan

## 1. Understanding Current Architecture

Your current architecture consists of:
- AWS Lightsail instance (small_3_0 - 2 vCPU, 2GB RAM) running a Minecraft server in Docker
- 20GB SSD Block Storage for the Minecraft world data
- S3 bucket for backups (kroni-survival-backups-secure)
- Cron jobs that handle:
  - Regular backups to S3 (every 3 days)
  - Lightsail snapshots (biweekly)
  - Discord notifications

The limitations you're facing include:
- Difficult to expand workflows beyond basic bash scripts
- Challenging to implement complex logic and dependencies
- Limited monitoring and observability
- Difficult to manage multiple environments (prod/non-prod)
- Challenges integrating with additional services (Datadog, Kafka)

## 2. Prefect Overview

Prefect is a workflow orchestration platform that will allow you to:
- Define workflows as Python code
- Handle dependencies between tasks
- Provide better visibility into workflow execution
- Implement conditional logic
- Scale to more complex use cases

### Prefect Deployment Options

There are two main options for Prefect:

1. **Prefect Cloud** - Managed service by Prefect
   - Pros: No infrastructure to manage, easy setup
   - Cons: Monthly costs, data leaving your infrastructure

2. **Self-hosted Prefect** - Run Prefect on your own infrastructure
   - Pros: No additional costs (beyond compute), full control
   - Cons: You manage the infrastructure, potential resource competition

For this implementation, we'll use self-hosted Prefect to avoid additional costs and keep all data within your AWS environment.

## 3. Implementation Plan

### 3.1 Architecture Overview

The updated architecture will consist of:

1. **Minecraft Server Instance** (existing)
   - Runs the Minecraft Docker container
   - Hosts game data on attached block storage
   - Continues to serve players without orchestration overhead

2. **Prefect Orchestration Instance** (new)
   - Hosts the Prefect Server and UI
   - Runs the Prefect Agent to execute workflows
   - Communicates with the Minecraft instance via SSH
   - Integrates with AWS services (S3, Lightsail API)
   - Sends notifications to Discord

3. **Shared AWS Resources**
   - S3 Bucket for backups
   - IAM user/role for AWS operations
   - Lightsail snapshots

### 3.2 Prefect Components to Install

1. **Prefect Server**: The backend that stores workflow metadata, schedules runs
2. **Prefect Agent**: Process that executes your workflows
3. **Prefect CLI**: Command-line tool for interacting with Prefect
4. **Prefect Python SDK**: For creating your workflows
5. **Remote Execution Tools**: SSH and AWS SDK for communicating with the Minecraft instance

### 3.2 Infrastructure Changes

We'll implement Option B - using a dedicated orchestration instance:

#### Dedicated Prefect Orchestration Instance
- Create a separate Lightsail instance dedicated to Prefect
- Size recommendation: `nano_3_0` (2 vCPU, 512 MB RAM)
- Region: Same as Minecraft server (ap-southeast-5)
- Blueprint: `amazon_linux_2`
- Configure network to allow communication between instances
- Benefits:
  - Complete resource isolation (no impact on Minecraft performance)
  - Better modularity and separation of concerns
  - Easier to scale orchestration separately from game server
  - Cleaner architecture for future integrations

#### Network Configuration
- Both instances should be in the same AWS region
- Create appropriate security group rules to allow communication:
  - Prefect instance needs to access Minecraft instance (SSH, Docker API)
  - Minecraft instance needs to send metrics to Prefect instance
- Open port 4200 on Prefect instance for UI access (restricted to your IP)

### 3.3 Installation Steps

#### 3.3.1 Create Prefect Orchestration Instance

1. **Create a new Lightsail instance via Terraform**:

```terraform
# Prefect orchestration instance
resource "aws_lightsail_instance" "prefect_orchestration" {
  name              = "kroni-prefect-orchestration"
  availability_zone = "${var.aws_region}a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"  # 2 vCPU, 512 MB RAM
  key_pair_name     = var.ssh_key_name  # Use the same SSH key as Minecraft server

  tags = {
    Name = "kroni-prefect-orchestration"
  }
}

# Static IP for Prefect instance
resource "aws_lightsail_static_ip" "prefect_orchestration" {
  name = "kroni-prefect-static-ip"
}

# Attach static IP to Prefect instance
resource "aws_lightsail_static_ip_attachment" "prefect_orchestration" {
  static_ip_name = aws_lightsail_static_ip.prefect_orchestration.name
  instance_name  = aws_lightsail_instance.prefect_orchestration.name
}

# Configure firewall for Prefect UI access
resource "aws_lightsail_instance_public_ports" "prefect_orchestration" {
  instance_name = aws_lightsail_instance.prefect_orchestration.name

  # Allow Prefect UI port
  port_info {
    protocol  = "tcp"
    from_port = 4200
    to_port   = 4200
    cidrs     = var.prefect_ui_allowed_cidrs
  }

  # Allow SSH access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }
}
```

#### 3.3.2 Install Prefect on the Orchestration Instance

1. **Install Python and Dependencies**:

```bash
# Update system packages
sudo yum update -y

# Install Python 3.8 (Amazon Linux 2)
sudo amazon-linux-extras install python3.8 -y

# Install development tools for Python package building
sudo yum install -y python38-devel gcc git jq

# Set up Python virtual environment
mkdir -p /opt/prefect
cd /opt/prefect
python3.8 -m venv venv
source venv/bin/activate

# Install Prefect and dependencies
pip install --upgrade pip
pip install "prefect==2.13.0" boto3 requests psutil paramiko docker
```

2. **Configure Prefect Server**:

```bash
# Create configuration directory
mkdir -p ~/.prefect

# Configure Prefect for local server
prefect config set PREFECT_API_URL=""

# Start the Prefect server
prefect server start &
```

3. **Create Systemd Services for Reliability**:

Create Prefect Server service:
```bash
sudo tee /etc/systemd/system/prefect-server.service > /dev/null << 'EOF'
[Unit]
Description=Prefect Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect server start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Create Prefect Agent service:
```bash
sudo tee /etc/systemd/system/prefect-agent.service > /dev/null << 'EOF'
[Unit]
Description=Prefect Agent
After=network.target prefect-server.service

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect agent start -q default
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start the services:
```bash
sudo systemctl daemon-reload
sudo systemctl enable prefect-server.service
sudo systemctl enable prefect-agent.service
sudo systemctl start prefect-server.service
sudo systemctl start prefect-agent.service
```

#### 3.3.3 Set Up SSH Key-Based Authentication

Set up passwordless SSH access from the Prefect instance to the Minecraft instance:

1. **Generate SSH key pair on Prefect instance**:

```bash
# Generate SSH key (without passphrase)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft_access -N ""

# Display the public key
cat ~/.ssh/minecraft_access.pub
```

2. **Add the public key to the Minecraft server's authorized keys**:

```bash
# On the Minecraft server instance
mkdir -p ~/.ssh
echo "PUBLIC_KEY_FROM_PREFECT_INSTANCE" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

This can be automated through Terraform:

```terraform
# Add Prefect instance's SSH public key to Minecraft server
resource "null_resource" "setup_ssh_access" {
  depends_on = [
    aws_lightsail_instance.minecraft_server,
    aws_lightsail_instance.prefect_orchestration,
    aws_lightsail_static_ip_attachment.minecraft_server,
    aws_lightsail_static_ip_attachment.prefect_orchestration
  ]

  # Generate SSH key on Prefect instance
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "ssh-keygen -t rsa -b 4096 -f ~/.ssh/minecraft_access -N \"\"",
      "cat ~/.ssh/minecraft_access.pub > /tmp/prefect_pubkey.txt"
    ]
  }

  # Copy the public key from Prefect instance to local
  provisioner "local-exec" {
    command = "scp -i ~/.ssh/${var.ssh_key_name}.pem -o StrictHostKeyChecking=no ec2-user@${aws_lightsail_static_ip.prefect_orchestration.ip_address}:/tmp/prefect_pubkey.txt /tmp/prefect_pubkey.txt"
  }

  # Add the public key to Minecraft server
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }

    inline = [
      "mkdir -p ~/.ssh",
      "cat /tmp/minecraft_prefect_pubkey.txt >> ~/.ssh/authorized_keys",
      "chmod 600 ~/.ssh/authorized_keys"
    ]
  }

  # Copy the public key from local to Minecraft server
  provisioner "file" {
    source      = "/tmp/prefect_pubkey.txt"
    destination = "/tmp/minecraft_prefect_pubkey.txt"

    connection {
      type        = "ssh"
      user        = "ec2-user"
      host        = aws_lightsail_static_ip.minecraft_server.ip_address
      private_key = file("~/.ssh/${var.ssh_key_name}.pem")
    }
  }
}
```

#### 3.3.4 Configure AWS Access

1. **Create a dedicated IAM user for Prefect**:

```terraform
# IAM user for Prefect orchestration
resource "aws_iam_user" "prefect_orchestration" {
  name = "kroni-prefect-orchestration-user"

  tags = {
    Name = "kroni-prefect-orchestration-user"
  }
}

# Create access key for the IAM user
resource "aws_iam_access_key" "prefect_orchestration" {
  user = aws_iam_user.prefect_orchestration.name
}

# Attach required policies
resource "aws_iam_user_policy_attachment" "prefect_s3_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn  # Reuse existing S3 policy
}

resource "aws_iam_user_policy_attachment" "prefect_lightsail_attachment" {
  user       = aws_iam_user.prefect_orchestration.name
  policy_arn = aws_iam_policy.lightsail_snapshot_policy.arn  # Reuse existing Lightsail policy
}
```

2. **Configure AWS credentials on the Prefect instance**:

```bash
# Configure AWS CLI with Prefect IAM credentials
mkdir -p ~/.aws
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
region = ap-southeast-5
EOF
```

This can be done via Terraform:

```terraform
# Configure AWS credentials on Prefect instance
resource "null_resource" "configure_aws_credentials" {
  depends_on = [
    aws_lightsail_instance.prefect_orchestration,
    aws_iam_access_key.prefect_orchestration
  ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_lightsail_static_ip.prefect_orchestration.ip_address
    private_key = file("~/.ssh/${var.ssh_key_name}.pem")
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/.aws",
      "cat > ~/.aws/credentials << EOF",
      "[default]",
      "aws_access_key_id = ${aws_iam_access_key.prefect_orchestration.id}",
      "aws_secret_access_key = ${aws_iam_access_key.prefect_orchestration.secret}",
      "region = ${var.aws_region}",
      "EOF",
      "chmod 600 ~/.aws/credentials"
    ]
  }
}
```

### 3.4 Workflow Implementation

Since we're now using a separate instance for Prefect, we need to modify our workflows to use SSH for remote execution on the Minecraft server. Here's how we'll implement each flow:

#### 3.4.1 Remote Execution Helper

First, let's create a helper module for executing commands remotely via SSH:

```python
# remote_executor.py
import paramiko
import logging
import io
import os
from typing import Tuple, Optional, Dict, Any

logger = logging.getLogger(__name__)

class RemoteExecutor:
    """Helper class for executing commands on the Minecraft server via SSH."""
    
    def __init__(self, hostname: str, username: str = "ec2-user", 
                 key_path: str = "~/.ssh/minecraft_access"):
        """Initialize SSH connection parameters."""
        self.hostname = hostname
        self.username = username
        self.key_path = os.path.expanduser(key_path)
        self._client = None
    
    def connect(self) -> None:
        """Establish SSH connection to the Minecraft server."""
        if self._client is not None:
            return
            
        try:
            client = paramiko.SSHClient()
            client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            client.connect(
                hostname=self.hostname,
                username=self.username,
                key_filename=self.key_path
            )
            self._client = client
            logger.info(f"Connected to {self.username}@{self.hostname}")
        except Exception as e:
            logger.error(f"Failed to connect to {self.hostname}: {e}")
            raise
    
    def disconnect(self) -> None:
        """Close the SSH connection."""
        if self._client:
            self._client.close()
            self._client = None
            logger.info(f"Disconnected from {self.hostname}")
    
    def execute_command(self, command: str) -> Tuple[int, str, str]:
        """
        Execute a command on the remote server.
        
        Args:
            command: The command to execute
            
        Returns:
            Tuple of (exit_code, stdout, stderr)
        """
        if not self._client:
            self.connect()
            
        try:
            logger.info(f"Executing command: {command}")
            stdin, stdout, stderr = self._client.exec_command(command)
            exit_code = stdout.channel.recv_exit_status()
            
            stdout_str = stdout.read().decode('utf-8')
            stderr_str = stderr.read().decode('utf-8')
            
            if exit_code != 0:
                logger.warning(f"Command exited with code {exit_code}")
                logger.warning(f"stderr: {stderr_str}")
            else:
                logger.info(f"Command completed successfully")
                
            return exit_code, stdout_str, stderr_str
        except Exception as e:
            logger.error(f"Failed to execute command: {e}")
            return 1, "", str(e)
    
    def check_docker_container(self, container_name: str) -> bool:
        """
        Check if a Docker container is running.
        
        Args:
            container_name: Name of the container to check
            
        Returns:
            True if the container is running, False otherwise
        """
        command = f"docker ps --filter name={container_name} --format '{{{{.Names}}}}'"
        exit_code, stdout, _ = self.execute_command(command)
        
        if exit_code != 0:
            return False
            
        return container_name in stdout.strip()
    
    def docker_stop_container(self, container_name: str) -> bool:
        """
        Stop a Docker container.
        
        Args:
            container_name: Name of the container to stop
            
        Returns:
            True if successful, False otherwise
        """
        command = f"docker stop {container_name}"
        exit_code, _, _ = self.execute_command(command)
        return exit_code == 0
    
    def docker_start_container(self, container_name: str) -> bool:
        """
        Start a Docker container.
        
        Args:
            container_name: Name of the container to start
            
        Returns:
            True if successful, False otherwise
        """
        command = f"docker start {container_name}"
        exit_code, _, _ = self.execute_command(command)
        return exit_code == 0
    
    def create_backup(self, world_path: str, backup_dir: str = "/tmp") -> Optional[str]:
        """
        Create a backup of the Minecraft world on the remote server.
        
        Args:
            world_path: Path to the Minecraft world directory
            backup_dir: Directory to store the backup file
            
        Returns:
            Path to the backup file if successful, None otherwise
        """
        timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_filename = f"minecraft-world-backup-{timestamp}.tar.gz"
        backup_path = f"{backup_dir}/{backup_filename}"
        
        # Create backup directory if it doesn't exist
        self.execute_command(f"mkdir -p {backup_dir}")
        
        # Check if world directory exists
        _, stdout, _ = self.execute_command(f"ls -la {world_path}")
        if "No such file or directory" in stdout:
            logger.error(f"World directory {world_path} does not exist!")
            return None
        
        # Create backup
        command = f"tar -czf {backup_path} -C $(dirname {world_path}) $(basename {world_path})"
        exit_code, _, stderr = self.execute_command(command)
        
        if exit_code != 0:
            logger.error(f"Failed to create backup: {stderr}")
            return None
            
        logger.info(f"Backup created at {backup_path}")
        return backup_path
    
    def download_file(self, remote_path: str, local_path: str) -> bool:
        """
        Download a file from the remote server.
        
        Args:
            remote_path: Path to the file on the remote server
            local_path: Path where the file should be saved locally
            
        Returns:
            True if successful, False otherwise
        """
        if not self._client:
            self.connect()
            
        try:
            sftp = self._client.open_sftp()
            sftp.get(remote_path, local_path)
            sftp.close()
            
            logger.info(f"Downloaded {remote_path}

#### Snapshot Flow (Lightsail Instance and Volume Snapshots)

```python
from prefect import flow, task
import boto3
import datetime
import logging
import requests

logger = logging.getLogger(__name__)

@task(name="Create Lightsail Snapshots")
def create_lightsail_snapshots(instance_name: str, disk_name: str, region: str):
    """Create snapshots of the Lightsail instance and disk."""
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    instance_snapshot_name = f"{instance_name}-{timestamp}"
    disk_snapshot_name = f"{disk_name}-{timestamp}"
    
    try:
        logger.info("Creating Lightsail snapshots...")
        lightsail_client = boto3.client('lightsail', region_name=region)
        
        # Create instance snapshot
        logger.info(f"Creating instance snapshot: {instance_snapshot_name}")
        lightsail_client.create_instance_snapshot(
            instanceName=instance_name,
            instanceSnapshotName=instance_snapshot_name
        )
        
        # Create disk snapshot
        logger.info(f"Creating disk snapshot: {disk_snapshot_name}")
        lightsail_client.create_disk_snapshot(
            diskName=disk_name,
            diskSnapshotName=disk_snapshot_name
        )
        
        logger.info("Snapshots created successfully")
        return True, instance_snapshot_name, disk_snapshot_name
    except Exception as e:
        logger.error(f"Failed to create Lightsail snapshots: {e}")
        return False, "", ""

@task(name="Clean Up Old Snapshots")
def cleanup_old_snapshots(instance_name: str, disk_name: str, region: str, retention_days: int):
    """Clean up old Lightsail snapshots based on retention policy."""
    try:
        logger.info(f"Cleaning up old snapshots (older than {retention_days} days)...")
        
        lightsail_client = boto3.client('lightsail', region_name=region)
        cutoff_date = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=retention_days)
        deleted_count = 0
        
        # Clean up instance snapshots
        instance_snapshots = lightsail_client.get_instance_snapshots()
        for snapshot in instance_snapshots['instanceSnapshots']:
            if snapshot['fromInstanceName'] == instance_name and snapshot['createdAt'] < cutoff_date:
                logger.info(f"Deleting old instance snapshot: {snapshot['name']}")
                lightsail_client.delete_instance_snapshot(instanceSnapshotName=snapshot['name'])
                deleted_count += 1
                
        # Clean up disk snapshots
        disk_snapshots = lightsail_client.get_disk_snapshots()
        for snapshot in disk_snapshots['diskSnapshots']:
            if snapshot['fromDiskName'] == disk_name and snapshot['createdAt'] < cutoff_date:
                logger.info(f"Deleting old disk snapshot: {snapshot['name']}")
                lightsail_client.delete_disk_snapshot(diskSnapshotName=snapshot['name'])
                deleted_count += 1
                
        logger.info(f"Deleted {deleted_count} old snapshots")
        return deleted_count
    except Exception as e:
        logger.error(f"Failed to clean up old snapshots: {e}")
        return 0

@task(name="Send Discord Notification")
def send_discord_notification(webhook_url: str, status: str, message: str, details: dict = None):
    """Send notification to Discord webhook."""
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping notification")
        return False
    
    try:
        logger.info(f"Sending Discord notification: {status}")
        
        # Set emoji based on status
        emoji = "✅" if status == "SUCCESS" else "❌"
        
        # Set color based on status (success: green, failure: red)
        color = 5763719 if status == "SUCCESS" else 15548997
        
        # Create payload with embed
        payload = {
            "embeds": [
                {
                    "title": f"{emoji} Kroni Survival - {status}",
                    "description": message,
                    "color": color,
                    "timestamp": datetime.datetime.now().isoformat(),
                    "footer": {
                        "text": "Kroni Survival Minecraft Server"
                    }
                }
            ]
        }
        
        # Add fields if details are provided
        if details:
            fields = []
            for key, value in details.items():
                fields.append({
                    "name": key,
                    "value": str(value),
                    "inline": True
                })
            payload["embeds"][0]["fields"] = fields
        
        # Send the notification
        response = requests.post(webhook_url, json=payload)
        response.raise_for_status()
        
        logger.info("Discord notification sent successfully")
        return True
    except Exception as e:
        logger.error(f"Failed to send Discord notification: {e}")
        return False

@flow(name="Lightsail Snapshot Flow")
def snapshot_flow(config: dict = None):
    """
    Main flow for creating and managing Lightsail snapshots.
    
    Args:
        config: Configuration dictionary with the following keys:
            - instance_name: Name of the Lightsail instance
            - disk_name: Name of the Lightsail disk
            - region: AWS region
            - retention_days: Number of days to retain snapshots
            - discord_webhook_url: Discord webhook URL for notifications
    """
    # Default configuration
    default_config = {
        "instance_name": "kroni-survival-server",
        "disk_name": "kroni-survival-volume",
        "region": "ap-southeast-5",
        "retention_days": 30,
        "discord_webhook_url": "",
    }
    
    # Merge provided config with defaults
    cfg = default_config.copy()
    if config:
        cfg.update(config)
    
    # Create snapshots
    snapshot_success, instance_snapshot, disk_snapshot = create_lightsail_snapshots(
        cfg["instance_name"],
        cfg["disk_name"],
        cfg["region"]
    )
    
    # Clean up old snapshots
    deleted_snapshots = cleanup_old_snapshots(
        cfg["instance_name"],
        cfg["disk_name"],
        cfg["region"],
        cfg["retention_days"]
    )
    
    # Prepare notification details
    notification_details = {
        "Instance Snapshot": instance_snapshot if snapshot_success else "Failed",
        "Disk Snapshot": disk_snapshot if snapshot_success else "Failed",
        "Deleted Snapshots": deleted_snapshots,
        "Timestamp": datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    # Determine status
    if snapshot_success:
        status = "SUCCESS"
        message = "Lightsail snapshots created successfully!"
    else:
        status = "FAILURE"
        message = "Failed to create Lightsail snapshots."
    
    # Send notification
    send_discord_notification(
        cfg["discord_webhook_url"],
        status,
        message,
        notification_details
    )
    
    return status
```

#### Server Monitoring Flow

```python
from prefect import flow, task
import psutil
import subprocess
import requests
import datetime
import json
import logging
import boto3

logger = logging.getLogger(__name__)

@task(name="Check System Resources")
def check_system_resources():
    """Check the system's CPU, memory, and disk usage."""
    cpu_percent = psutil.cpu_percent(interval=1)
    memory_percent = psutil.virtual_memory().percent
    disk_percent = psutil.disk_usage('/').percent
    
    logger.info(f"System resources: CPU: {cpu_percent}%, Memory: {memory_percent}%, Disk: {disk_percent}%")
    
    return {
        "cpu_percent": cpu_percent,
        "memory_percent": memory_percent,
        "disk_percent": disk_percent,
        "timestamp": datetime.datetime.now().isoformat()
    }

@task(name="Check Minecraft Server Status")
def check_minecraft_status():
    """Check if the Minecraft server is running and get player count."""
    try:
        # Check if the container is running
        docker_ps_result = subprocess.run(
            ["docker", "ps", "--filter", "name=minecraft-server", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=True
        )
        is_running = "minecraft-server" in docker_ps_result.stdout
        
        player_count = 0
        if is_running:
            # Get the server logs to check for player count
            # This is a simple approach - a more robust solution would use the RCON protocol
            docker_logs_result = subprocess.run(
                ["docker", "logs", "--tail", "100", "minecraft-server"],
                capture_output=True,
                text=True,
                check=True
            )
            
            # This is a very basic way to estimate player count - might need adjustment
            player_count = docker_logs_result.stdout.count("joined the game") - docker_logs_result.stdout.count("left the game")
            if player_count < 0:
                player_count = 0
        
        return {
            "is_running": is_running,
            "player_count": player_count,
            "timestamp": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Failed to check Minecraft server status: {e}")
        return {
            "is_running": False,
            "player_count": 0,
            "error": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

@task(name="Check Instance Health")
def check_instance_health(instance_name: str, region: str):
    """Check the Lightsail instance health."""
    try:
        lightsail_client = boto3.client('lightsail', region_name=region)
        response = lightsail_client.get_instance(instanceName=instance_name)
        
        state = response['instance']['state']['name']
        public_ip = response['instance']['publicIpAddress']
        
        return {
            "state": state,
            "public_ip": public_ip,
            "timestamp": datetime.datetime.now().isoformat()
        }
    except Exception as e:
        logger.error(f"Failed to check instance health: {e}")
        return {
            "state": "unknown",
            "error": str(e),
            "timestamp": datetime.datetime.now().isoformat()
        }

@task(name="Send Alert")
def send_alert(webhook_url: str, alert_data: dict, threshold_config: dict):
    """Send alert to Discord if any metrics exceed thresholds."""
    if not webhook_url:
        logger.info("No Discord webhook URL provided, skipping alert")
        return False
    
    # Check if any metrics exceed thresholds
    alerts = []
    
    # Check system resources
    if alert_data["system"]["cpu_percent"] > threshold_config["cpu_percent"]:
        alerts.append(f"⚠️ CPU usage is high: {alert_data['system']['cpu_percent']}% (threshold: {threshold_config['cpu_percent']}%)")
    
    if alert_data["system"]["memory_percent"] > threshold_config["memory_percent"]:
        alerts.append(f"⚠️ Memory usage is high: {alert_data['system']['memory_percent']}% (threshold: {threshold_config['memory_percent']}%)")
    
    if alert_data["system"]["disk_percent"] > threshold_config["disk_percent"]:
        alerts.append(f"⚠️ Disk usage is high: {alert_data['system']['disk_percent']}% (threshold: {threshold_config['disk_percent']}%)")
    
    # Check server status
    if not alert_data["minecraft"]["is_running"]:
        alerts.append("🛑 Minecraft server is not running!")
    
    # Send alert if any thresholds are exceeded
    if alerts:
        try:
            logger.info(f"Sending alert to Discord: {', '.join(alerts)}")
            
            # Create message with all alerts
            message = "\n".join(alerts)
            
            # Add instance info
            message += f"\n\nInstance: {alert_data['instance']['state']} ({alert_data['instance']['public_ip']})"
            
            # Add player count
            if alert_data["minecraft"]["is_running"]:
                message += f"\nPlayers online: {alert_data['minecraft']['player_count']}"
            
            # Create payload
            payload = {
                "embeds": [
                    {
                        "title": "🚨 Kroni Survival - Server Alert",
                        "description": message,
                        "color": 16711680,  # Red
                        "timestamp": datetime.datetime.now().isoformat(),
                        "footer": {
                            "text": "Kroni Survival Monitoring"
                        }
                    }
                ]
            }
            
            # Send the alert
            response = requests.post(webhook_url, json=payload)
            response.raise_for_status()
            
            logger.info("Alert sent successfully")
            return True
        except Exception as e:
            logger.error(f"Failed to send alert: {e}")
            return False
    else:
        logger.info("No alerts to send")
        return False

@flow(name="Server Monitoring Flow")
def server_monitoring_flow(config: dict = None):
    """
    Main flow for monitoring the Minecraft server and infrastructure.
    
    Args:
        config: Configuration dictionary with the following keys:
            - instance_name: Name of the Lightsail instance
            - region: AWS region
            - discord_webhook_url: Discord webhook URL for alerts
            - thresholds: Dictionary of alert thresholds
    """
    # Default configuration
    default_config = {
        "instance_name": "kroni-survival-server",
        "region": "ap-southeast-5",
        "discord_webhook_url": "",
        "thresholds": {
            "cpu_percent": 90,
            "memory_percent": 90,
            "disk_percent": 85
        }
    }
    
    # Merge provided config with defaults
    cfg = default_config.copy()
    if config:
        cfg.update(config)
        # Ensure thresholds dict exists and is properly merged
        if "thresholds" in config:
            cfg["thresholds"] = {**default_config["thresholds"], **config["thresholds"]}
    
    # Collect monitoring data
    system_data = check_system_resources()
    minecraft_data = check_minecraft_status()
    instance_data = check_instance_health(cfg["instance_name"], cfg["region"])
    
    # Combine all data
    monitoring_data = {
        "system": system_data,
        "minecraft": minecraft_data,
        "instance": instance_data
    }
    
    # Check for alerts
    send_alert(cfg["discord_webhook_url"], monitoring_data, cfg["thresholds"])
    
    return monitoring_data
```

### 3.5 Deployment Setup

Create the following deployment scripts to schedule your workflows:

#### Deploy Backup Flow
```python
# deploy_backup_flow.py
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from backup_flow import backup_flow

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=backup_flow,
    name="scheduled-minecraft-backup",
    schedule=CronSchedule(cron="0 0 */3 * *"),  # Every 3 days at midnight
    parameters={
        "config": {
            "world_path": "/data/world",
            "s3_bucket": "kroni-survival-backups-secure",
            "region": "ap-southeast-5",
            "discord_webhook_url": "your-discord-webhook-here"
        }
    },
    tags=["minecraft", "backup"]
)

if __name__ == "__main__":
    deployment.apply()
```

#### Deploy Snapshot Flow
```python
# deploy_snapshot_flow.py
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from snapshot_flow import snapshot_flow

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=snapshot_flow,
    name="scheduled-lightsail-snapshots",
    schedule=CronSchedule(cron="0 0 */14 * *"),  # Biweekly at midnight
    parameters={
        "config": {
            "instance_name": "kroni-survival-server",
            "disk_name": "kroni-survival-volume",
            "region": "ap-southeast-5",
            "retention_days": 30,
            "discord_webhook_url": "your-discord-webhook-here"
        }
    },
    tags=["minecraft", "snapshot", "lightsail"]
)

if __name__ == "__main__":
    deployment.apply()
```

#### Deploy Monitoring Flow
```python
# deploy_monitoring_flow.py
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import IntervalSchedule
from datetime import timedelta
from server_monitoring_flow import server_monitoring_flow

# Create a deployment with an interval schedule
deployment = Deployment.build_from_flow(
    flow=server_monitoring_flow,
    name="scheduled-server-monitoring",
    schedule=IntervalSchedule(interval=timedelta(minutes=30)),  # Every 30 minutes
    parameters={
        "config": {
            "instance_name": "kroni-survival-server",
            "region": "ap-southeast-5",
            "discord_webhook_url": "your-discord-webhook-here",
            "thresholds": {
                "cpu_percent": 90,
                "memory_percent": 90,
                "disk_percent": 85
            }
        }
    },
    tags=["minecraft", "monitoring"]
)

if __name__ == "__main__":
    deployment.apply()
```

### 3.6 Terraform Integration

Update your Terraform setup to install Prefect automatically during server provisioning:

1. **Add a Prefect installation script**: Create a dedicated script for installing and configuring Prefect.

```bash
# prefect_setup.sh
#!/bin/bash
set -e

# Variables passed from Terraform
AWS_REGION="${aws_region}"
DISCORD_WEBHOOK_URL="${discord_webhook_url}"
INSTANCE_NAME="${instance_name}"
VOLUME_NAME="${volume_name}"
S3_BUCKET="${s3_bucket}"
WORLD_PATH="${world_path}"
MONITORING_INTERVAL="${monitoring_interval}"

echo "=== Setting up Prefect for Kroni Survival ==="

# Install Python and dependencies
sudo amazon-linux-extras install python3.8 -y
sudo yum install -y python38-pip python38-devel gcc

# Set up virtual environment
sudo mkdir -p /opt/prefect
sudo chown ec2-user:ec2-user /opt/prefect
cd /opt/prefect
python3.8 -m venv venv
source venv/bin/activate

# Install Prefect and dependencies
pip install --upgrade pip
pip install "prefect==2.13.0" boto3 requests psutil

# Create directories for Prefect flows
mkdir -p ~/.prefect
mkdir -p /opt/prefect/flows

# Configure Prefect for local server
prefect config set PREFECT_API_URL=""

# Copy flow files
cp /tmp/prefect/*.py /opt/prefect/flows/

# Create systemd services
cat > /tmp/prefect-server.service << EOF
[Unit]
Description=Prefect Server
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect server start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /tmp/prefect-agent.service << EOF
[Unit]
Description=Prefect Agent
After=network.target prefect-server.service

[Service]
User=ec2-user
WorkingDirectory=/opt/prefect
ExecStart=/opt/prefect/venv/bin/prefect agent start -q default
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/prefect-server.service /etc/systemd/system/
sudo mv /tmp/prefect-agent.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable prefect-server
sudo systemctl enable prefect-agent

# Start Prefect server
sudo systemctl start prefect-server

# Give the server time to start
sleep 20

# Deploy flows
cd /opt/prefect/flows

# Create deployment scripts
cat > deploy_backup.py << EOF
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from backup_flow import backup_flow

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=backup_flow,
    name="scheduled-minecraft-backup",
    schedule=CronSchedule(cron="0 0 */3 * *"),  # Every 3 days at midnight
    parameters={
        "config": {
            "world_path": "${WORLD_PATH}",
            "s3_bucket": "${S3_BUCKET}",
            "region": "${AWS_REGION}",
            "discord_webhook_url": "${DISCORD_WEBHOOK_URL}"
        }
    }
)

if __name__ == "__main__":
    deployment.apply()
EOF

cat > deploy_snapshot.py << EOF
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import CronSchedule
from snapshot_flow import snapshot_flow

# Create a deployment with a cron schedule
deployment = Deployment.build_from_flow(
    flow=snapshot_flow,
    name="scheduled-lightsail-snapshots",
    schedule=CronSchedule(cron="0 0 */14 * *"),  # Biweekly at midnight
    parameters={
        "config": {
            "instance_name": "${INSTANCE_NAME}",
            "disk_name": "${VOLUME_NAME}",
            "region": "${AWS_REGION}",
            "retention_days": 30,
            "discord_webhook_url": "${DISCORD_WEBHOOK_URL}"
        }
    }
)

if __name__ == "__main__":
    deployment.apply()
EOF

cat > deploy_monitoring.py << EOF
from prefect.deployments import Deployment
from prefect.server.schemas.schedules import IntervalSchedule
from datetime import timedelta
from server_monitoring_flow import server_monitoring_flow

# Create a deployment with an interval schedule
deployment = Deployment.build_from_flow(
    flow=server_monitoring_flow,
    name="scheduled-server-monitoring",
    schedule=IntervalSchedule(interval=timedelta(minutes=${MONITORING_INTERVAL})),
    parameters={
        "config": {
            "instance_name": "${INSTANCE_NAME}",
            "region": "${AWS_REGION}",
            "discord_webhook_url": "${DISCORD_WEBHOOK_URL}",
            "thresholds": {
                "cpu_percent": 90,
                "memory_percent": 90,
                "disk_percent": 85
            }
        }
    }
)

if __name__ == "__main__":
    deployment.apply()
EOF

# Deploy the flows
source /opt/prefect/venv/bin/activate
python deploy_backup.py
python deploy_snapshot.py
python deploy_monitoring.py

# Start the agent
sudo systemctl start prefect-agent

echo "=== Prefect setup completed! ==="
echo "The Prefect UI is available at http://$(curl -s http://checkip.amazonaws.com):4200"
```

2. **Update terraform/variables.tf** to add Prefect configuration:

```terraform
# Prefect variables
variable "monitoring_interval" {
  description = "Interval in minutes for server monitoring"
  type        = number
  default     = 30
}

variable "deploy_prefect_monitoring" {
  description = "Enable Prefect monitoring flow deployment"
  type        = bool
  default     = true
}

variable "deploy_prefect_backup" {
  description = "Enable Prefect backup flow deployment"
  type        = bool
  default     = true
}

variable "prefect_ui_allowed_cidrs" {
  description = "CIDR blocks allowed for Prefect UI access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # You should restrict this in production
}
```

3. **Add Prefect UI port rule** to allow access to the web interface:

```terraform
# Open port 4200 for Prefect UI
resource "aws_lightsail_instance_public_ports" "prefect_ui" {
  instance_name = aws_lightsail_instance.minecraft_server.name

  port_info {
    protocol  = "tcp"
    from_port = 4200
    to_port   = 4200
    cidrs     = var.prefect_ui_allowed_cidrs
  }

  depends_on = [
    aws_lightsail_instance_public_ports.minecraft_server
  ]
}
```

4. **Update main.tf** to include the Prefect setup resource:

```terraform
# Setup Prefect on the Lightsail instance
resource "null_resource" "setup_prefect" {
  triggers = {
    instance_id = aws_lightsail_instance.minecraft_server.id
    script_hash = sha256(local.prefect_setup_script)
  }

  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_lightsail_static_ip.minecraft_server.ip_address
    private_key = file("~/.ssh/${var.ssh_key_name}.pem")
  }

  # Create remote directory and copy files
  provisioner "remote-exec" {
    inline = [
      "mkdir -p /tmp/prefect",
      "echo 'Created prefect directory'"
    ]
  }

  # Copy Prefect flow files
  provisioner "file" {
    source      = "${path.module}/../prefect/backup_flow.py"
    destination = "/tmp/prefect/backup_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/snapshot_flow.py"
    destination = "/tmp/prefect/snapshot_flow.py"
  }

  provisioner "file" {
    source      = "${path.module}/../prefect/server_monitoring_flow.py"
    destination = "/tmp/prefect/server_monitoring_flow.py"
  }

  # Copy the Prefect setup script
  provisioner "file" {
    content     = local.prefect_setup_script
    destination = "/tmp/prefect_setup.sh"
  }

  # Execute the Prefect setup script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/prefect_setup.sh",
      "sudo /tmp/prefect_setup.sh"
    ]
  }

  depends_on = [
    null_resource.provision_server
  ]
}
```

5. **Add Prefect script template** to your locals block:

```terraform
locals {
  # Your existing provisioner_script and other locals here...

  # Prefect setup script template
  prefect_setup_script = templatefile("${path.module}/prefect_setup.sh", {
    aws_region          = var.aws_region
    discord_webhook_url = var.discord_webhook_url
    instance_name       = var.lightsail_instance_name
    volume_name         = var.lightsail_volume_name
    s3_bucket           = var.s3_backup_bucket_name
    world_path          = var.minecraft_world_path
    monitoring_interval = var.monitoring_interval
  })
}
```

### 3.7 GitHub Actions Integration

Update your `.github/workflows/terraform.yml` file to handle Prefect flow deployment:

```yaml
# Add a new job for Prefect flows deployment
jobs:
  # Your existing terraform job here...
  
  deploy_prefect_flows:
    name: "Deploy Prefect Flows"
    needs: terraform
    runs-on: ubuntu-latest
    if: github.event.inputs.action == 'apply'
    
    steps:
      - name: Checkout
        uses: actions/checkout@v3
        
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.8'
          
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install prefect boto3 requests psutil
          
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
          
      - name: Get server info for Prefect connection
        id: server_info
        run: |
          SERVER_IP=$(terraform -chdir=./terraform output -raw minecraft_server_ip)
          echo "SERVER_IP=$SERVER_IP" >> $GITHUB_ENV
          
      - name: Deploy Prefect flows remotely
        run: |
          # This step uses SSH to connect to the server and deploy flows
          # You'll need to set up SSH keys in GitHub Actions secrets
          ssh -i ~/.ssh/${{ secrets.SSH_KEY_NAME }}.pem ec2-user@$SERVER_IP "cd /opt/prefect/flows && source /opt/prefect/venv/bin/activate && python deploy_backup.py && python deploy_snapshot.py && python deploy_monitoring.py"
```

## 4. Implementation Timeline

### Phase 1: Environment Setup (Day 1-2)
- Install Prefect on the Minecraft server
- Configure systemd services for Prefect
- Test basic connectivity and UI access
- Set up development environment for workflow development

### Phase 2: Initial Flow Development (Day 3-5)
- Develop backup flow and test manually
- Develop snapshot flow and test manually
- Compare results with existing cron job-based solution
- Verify Discord notifications are working

### Phase 3: Monitoring Flow Development (Day 6-7)
- Develop server monitoring flow
- Configure appropriate thresholds
- Test alerts and notifications
- Set up appropriate schedule

### Phase 4: Terraform Integration (Day 8-10)
- Update Terraform scripts to automate Prefect installation
- Test provisioning with Prefect
- Open necessary ports for UI access
- Document Terraform changes

### Phase 5: CI/CD Integration (Day 11-12)
- Update GitHub Actions workflow
- Test automated deployment of flows
- Document CI/CD process
- Create user guide for workflow management

### Phase 6: Testing and Documentation (Day 13-14)
- Comprehensive testing of all workflows
- Create documentation for the new system
- Knowledge transfer to team members
- Create runbook for common operations

## 5. Advanced Features (Future Phases)

After the initial implementation, consider these additional features:

### 5.1 Multi-Environment Support
- Create workflows for managing dev/test/prod environments
- Implement world cloning between environments
- Add configuration management for each environment

### 5.2 Enhanced Monitoring
- Add detailed metrics collection
- Create a Grafana dashboard for visualization
- Set up anomaly detection

### 5.3 Player Activity Analysis
- Track and analyze player activity
- Generate reports on server usage
- Identify peak usage times

### 5.4 Auto-Scaling
- Dynamically adjust server resources based on player count
- Scale down during inactive periods to save costs
- Scale up prior to scheduled events

### 5.5 Mod and Plugin Management
- Automated mod updates
- A/B testing of server configurations
- Backup before mod changes

## 6. Recommendations for Implementation

### 6.1 Resource Considerations
- Monitor resource usage closely during the first week
- Prefect Server and Agent together typically use about 200-300MB RAM
- Consider upgrading from small_3_0 to medium_1_0 if resource contention occurs

### 6.2 Backup Strategy
- Maintain both cron jobs and Prefect workflows during initial rollout
- Gradually transition from cron to Prefect
- Verify each workflow thoroughly before disabling corresponding cron job

### 6.3 Security Considerations
- Restrict Prefect UI access to your IP address only
- Consider implementing authentication for the Prefect UI
- Run Prefect with the minimum required privileges
- Use IAM roles with least privilege

### 6.4 Monitoring and Alerts
- Set up monitoring for Prefect itself
- Configure alerts for failed workflows
- Regularly review workflow execution logs

## 7. Troubleshooting and Maintenance

### 7.1 Common Issues and Solutions

**Prefect Server Won't Start**
```bash
# Check the status
systemctl status prefect-server

# View logs
journalctl -u prefect-server

# Restart the service
sudo systemctl restart prefect-server
```

**Prefect Agent Not Running**
```bash
# Check the status
systemctl status prefect-agent

# View logs
journalctl -u prefect-agent

# Restart the service
sudo systemctl restart prefect-agent
```

**Flow Deployment Issues**
```bash
# Check Prefect deployment status
prefect deployment ls

# Inspect a specific deployment
prefect deployment inspect scheduled-minecraft-backup

# Run a deployment manually
prefect deployment run scheduled-minecraft-backup
```

### 7.2 Maintenance Tasks

**Backup Prefect Database**
```bash
# Stop Prefect server
sudo systemctl stop prefect-server

# Back up the database (SQLite by default)
cp ~/.prefect/orion.db ~/.prefect/orion.db.bak

# Restart Prefect server
sudo systemctl start prefect-server
```

**Updating Prefect**
```bash
# Activate virtual environment
source /opt/prefect/venv/bin/activate

# Update Prefect
pip install --upgrade prefect

# Restart services
sudo systemctl restart prefect-server
sudo systemctl restart prefect-agent
```

**Checking Flow Status**
```bash
# List all flow runs
prefect flow-run ls

# View logs for a specific run
prefect flow-run logs <run-id>
```

## 8. Conclusion

Implementing Prefect for workflow orchestration will significantly improve the flexibility, reliability, and visibility of your Minecraft server management processes. The modular approach allows for incremental adoption while maintaining the existing functionality during the transition.

By following this implementation plan, you'll be able to replace your current cron-based system with a more powerful workflow orchestration solution, enabling future expansion and integration with additional services like Datadog and Kafka.

The key benefits of this implementation include:
- Better visibility into workflow execution through the Prefect UI
- More complex workflows with proper dependency management
- Improved error handling and retry mechanisms
- Easier extensibility for future requirements
- Centralized management of all server operations

This implementation serves as a foundation for more advanced features while maintaining the core functionality of your existing solution.

## 9. References

- [Prefect Documentation](https://docs.prefect.io/)
- [AWS Lightsail Documentation](https://docs.aws.amazon.com/lightsail/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Minecraft Server](https://github.com/itzg/docker-minecraft-server)