#!/usr/bin/env python3
"""
Configuration Check Script

This script validates the EC2 configuration and SSH connectivity from inside 
a Prefect container to make sure monitoring will work correctly.
"""

import os
import sys
import logging
import subprocess
from pathlib import Path

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

def get_ec2_config():
    """Find and load the EC2 configuration file."""
    # Possible locations for the config file
    config_paths = [
        "/opt/prefect/config/ec2_config.ini",  # Container path
        os.path.expanduser("~/prefect/config/ec2_config.ini"),  # User home path
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config/ec2_config.ini")  # Relative to script
    ]
    
    for path in config_paths:
        if os.path.exists(path):
            logger.info(f"Found EC2 config at: {path}")
            return load_config(path)
    
    logger.error("No EC2 configuration file found!")
    return {}

def load_config(config_path):
    """Load the configuration from a file."""
    config = {}
    try:
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith("#"):
                    continue
                
                if "=" in line:
                    key, value = line.split("=", 1)
                    config[key.strip()] = value.strip()
        return config
    except Exception as e:
        logger.error(f"Failed to load config: {e}")
        return {}

def check_ssh_connectivity(host, user="ec2-user", port="22"):
    """Test SSH connectivity to the target host."""
    try:
        logger.info(f"Testing SSH connectivity to {user}@{host}:{port}...")
        
        # Check if .ssh directory exists
        ssh_dir = os.path.expanduser("~/.ssh")
        if not os.path.exists(ssh_dir):
            logger.warning(f"SSH directory not found at {ssh_dir}")
            # Try alternate location in container
            ssh_dir = "/opt/prefect/.ssh"
            if not os.path.exists(ssh_dir):
                logger.error("No SSH directory found!")
            else:
                logger.info(f"Using alternate SSH directory: {ssh_dir}")
        
        # Find SSH key files
        key_files = []
        for file in Path(ssh_dir).glob("id_*"):
            if file.is_file() and not file.name.endswith(".pub"):
                key_files.append(str(file))
        
        for file in Path(ssh_dir).glob("ec2_*"):
            if file.is_file() and not file.name.endswith(".pub"):
                key_files.append(str(file))
        
        if not key_files:
            logger.warning("No SSH key files found!")
        else:
            logger.info(f"Found SSH keys: {key_files}")
        
        # Test SSH connection
        cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", 
               "-o", "StrictHostKeyChecking=no", f"{user}@{host}", "echo 'SSH test successful'"]
        
        logger.info(f"Running command: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            logger.info("✅ SSH connection successful!")
            logger.info(f"Output: {result.stdout.strip()}")
            return True
        else:
            logger.error("❌ SSH connection failed!")
            logger.error(f"Error: {result.stderr.strip()}")
            
            # Try with each key explicitly
            for key_file in key_files:
                logger.info(f"Trying with key file: {key_file}")
                cmd_with_key = ["ssh", "-i", key_file, "-o", "BatchMode=yes", 
                              "-o", "ConnectTimeout=5", "-o", "StrictHostKeyChecking=no", 
                              f"{user}@{host}", "echo 'SSH test successful'"]
                
                result = subprocess.run(cmd_with_key, capture_output=True, text=True)
                if result.returncode == 0:
                    logger.info(f"✅ SSH connection successful with key {key_file}!")
                    return True
            
            return False
    except Exception as e:
        logger.error(f"Error testing SSH connectivity: {e}")
        return False

def check_docker_access(host, user="ec2-user"):
    """Check if we can access Docker on the remote host."""
    try:
        logger.info(f"Testing Docker access on {host}...")
        
        cmd = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", 
               "-o", "StrictHostKeyChecking=no", f"{user}@{host}", 
               "docker ps --filter 'name=minecraft-server' --format '{{.Names}}'"]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        if result.returncode == 0:
            output = result.stdout.strip()
            logger.info("✅ Docker command executed successfully!")
            
            if "minecraft-server" in output:
                logger.info("✅ Minecraft server container is running!")
                return True
            else:
                logger.warning("⚠️ Minecraft server container not found or not running")
                logger.info(f"Docker output: '{output}'")
                return False
        else:
            logger.error("❌ Docker command failed!")
            logger.error(f"Error: {result.stderr.strip()}")
            return False
    except Exception as e:
        logger.error(f"Error testing Docker access: {e}")
        return False

def main():
    """Main function to check configuration and connectivity."""
    logger.info("Starting configuration check...")
    
    # Get EC2 configuration
    config = get_ec2_config()
    if not config:
        logger.error("Failed to load EC2 configuration. Exiting.")
        sys.exit(1)
    
    # Check required configuration
    host = config.get("EC2_HOST")
    user = config.get("SSH_USER", "ec2-user")
    port = config.get("SSH_PORT", "22")
    
    if not host:
        logger.error("EC2_HOST not found in configuration. Exiting.")
        sys.exit(1)
    
    logger.info(f"EC2 Configuration: host={host}, user={user}, port={port}")
    
    # Check SSH connectivity
    if not check_ssh_connectivity(host, user, port):
        logger.error("SSH connectivity check failed. Server monitoring will not work!")
        sys.exit(1)
    
    # Check Docker access
    if not check_docker_access(host, user):
        logger.warning("Docker access check failed. Container status will not be detected!")
    
    logger.info("✅ Configuration check completed successfully!")

if __name__ == "__main__":
    main() 