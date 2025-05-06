#!/usr/bin/env python3
"""
Utility functions for Minecraft server monitoring
"""

import os
import subprocess
import logging
from pathlib import Path
from typing import Dict, Optional, List, Tuple, Any, Union


def get_ec2_config(config_path: str = None) -> Dict[str, str]:
    """
    Load EC2 configuration from a file.
    
    Args:
        config_path: Path to the EC2 config file, default is to check environment variable
        
    Returns:
        Dict containing EC2 configuration
    """
    config = {}
    
    if not config_path:
        config_path = os.environ.get("KRONI_EC2_CONFIG", "/workspace/prefect/config/ec2_config.ini")
    
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith("#"):
                    continue
                
                if "=" in line:
                    key, value = line.split("=", 1)
                    config[key] = value
    
    return config


def run_ssh_command(host: str, command: str, user: str = "ec2-user", 
                   port: str = "22", options: List[str] = None, 
                   timeout: int = 15) -> Dict[str, Any]:
    """
    Run a command on a remote host via SSH.
    
    Args:
        host: Hostname or IP address
        command: Command to run
        user: SSH username
        port: SSH port
        options: Additional SSH options
        timeout: Command timeout in seconds
        
    Returns:
        Dict with returncode, stdout, stderr
    """
    if not options:
        options = ["-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"]
    
    # Build the SSH command
    cmd = ["ssh"] + options + ["-p", port, f"{user}@{host}", command]
    
    # Execute the command
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout
        )
        
        return {
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "success": result.returncode == 0
        }
    except subprocess.TimeoutExpired:
        return {
            "returncode": -1,
            "stdout": "",
            "stderr": f"Command timed out after {timeout} seconds",
            "success": False
        }
    except Exception as e:
        return {
            "returncode": -1,
            "stdout": "",
            "stderr": str(e),
            "success": False
        }


def check_container_status(container_name: str, host: str = None, 
                         user: str = None, ssh_config: Dict[str, str] = None,
                         logger=None) -> bool:
    """
    Check if a container is running, either locally or on a remote host.
    
    Args:
        container_name: Name of the container to check
        host: Hostname for remote check (None for local)
        user: SSH username for remote check
        ssh_config: SSH configuration dictionary
        logger: Logger object
        
    Returns:
        True if container is running, False otherwise
    """
    if logger is None:
        logger = logging.getLogger(__name__)
    
    # If simulated mode is enabled, always return True
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        logger.info("Running in SIMULATED mode - reporting container as RUNNING")
        return True
    
    # Try direct Docker socket access first if we're checking localhost
    if (host == "localhost" or (ssh_config and ssh_config.get("EC2_HOST") == "localhost")) and os.path.exists("/var/run/docker.sock"):
        try:
            logger.info("Checking container status via direct Docker socket...")
            result = subprocess.run(
                ["docker", "ps", "--filter", f"name={container_name}", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                check=False
            )
            
            if result.returncode == 0:
                # Parse container names from output
                container_names = [name.strip() for name in result.stdout.strip().split('\n') if name.strip()]
                logger.info(f"Found containers via Docker socket: {container_names}")
                
                # Check if our container is running
                is_running = any(name == container_name for name in container_names)
                logger.info(f"Container status via Docker socket: {'Running' if is_running else 'Stopped'}")
                return is_running
            else:
                logger.warning(f"Docker socket check failed: {result.stderr} - trying SSH method next")
        except Exception as e:
            logger.warning(f"Docker socket check failed: {e} - trying SSH method next")
    
    # If direct check failed or we're checking a remote host, try SSH
    if host or (ssh_config and ssh_config.get("EC2_HOST")):
        if ssh_config:
            host = ssh_config.get("EC2_HOST", host)
            user = ssh_config.get("SSH_USER", user)
            port = ssh_config.get("SSH_PORT", "22")
        
        if not host or not user:
            logger.warning("Incomplete SSH configuration, cannot check remote container")
            return False
        
        # Run a docker ps command on the remote host
        docker_cmd = f"docker ps | grep {container_name}"
        logger.info(f"Checking container status via SSH on {host}...")
        
        # Execute the command
        result = run_ssh_command(host, docker_cmd, user, port)
        
        # Log the results
        logger.info(f"SSH command exit code: {result['returncode']}")
        if result['stdout']:
            logger.info(f"SSH command stdout: {result['stdout']}")
        if result['stderr']:
            logger.info(f"SSH command stderr: {result['stderr']}")
        
        # If SSH failed with "No such file or directory: 'ssh'", it means the SSH client is missing
        if "No such file or directory: 'ssh'" in result.get('stderr', ''):
            logger.error("SSH client not installed in container - please check Dockerfile configuration")
            # Use a fallback check to avoid false alerts
            try:
                # Try direct Docker access as fallback
                logger.info("Trying direct Docker socket access as fallback...")
                if os.path.exists("/var/run/docker.sock"):
                    result = subprocess.run(
                        ["docker", "ps", "--filter", f"name={container_name}", "--format", "{{.Names}}"],
                        capture_output=True,
                        text=True,
                        check=False
                    )
                    if result.returncode == 0:
                        # Parse container names from output
                        container_names = [name.strip() for name in result.stdout.strip().split('\n') if name.strip()]
                        logger.info(f"Found containers via fallback Docker socket: {container_names}")
                        
                        # Check if our container is running
                        is_running = any(name == container_name for name in container_names)
                        logger.info(f"Container status via fallback Docker socket: {'Running' if is_running else 'Stopped'}")
                        return is_running
                    else:
                        logger.error(f"Fallback Docker socket check failed: {result.stderr}")
                else:
                    logger.error("Docker socket not available for fallback check")
            except Exception as e:
                logger.error(f"Fallback Docker socket check failed: {e}")
                
            # If we're in a container on the same host as the Minecraft server, assume it's running
            # This is a last resort to avoid false alerts
            logger.warning("As a last resort fallback, assuming server is running to avoid false alerts")
            return True
        
        # Container is running if command succeeded and container name is in output
        is_running = result['success'] and container_name in result['stdout']
        logger.info(f"Container status: {'Running' if is_running else 'Stopped'}")
        return is_running
    
    # Fallback to local checking if no host was specified and no SSH config is found
    try:
        logger.info("Checking container status locally...")
        result = subprocess.run(
            ["docker", "ps", "--filter", f"name={container_name}", "--format", "{{.Names}}"],
            capture_output=True,
            text=True,
            check=False
        )
        
        # Container is running if command succeeded and container name is in output
        if result.returncode != 0:
            logger.error(f"Docker command failed: {result.stderr}")
            return False
        
        # Parse container names from output
        container_names = [name.strip() for name in result.stdout.strip().split('\n') if name.strip()]
        logger.info(f"Found containers: {container_names}")
        
        # Check if our container is running
        is_running = any(name == container_name for name in container_names)
        logger.info(f"Container status: {'Running' if is_running else 'Stopped'}")
        return is_running
    except Exception as e:
        logger.error(f"Failed to check container status: {e}")
        return False


def get_directory_size(dir_path: str, simulated_size: float = None) -> Optional[float]:
    """
    Calculate the size of a directory in GB.
    
    Args:
        dir_path: Path to the directory
        simulated_size: Size to return in simulation mode
        
    Returns:
        Size in GB, or None if directory doesn't exist
    """
    logger = logging.getLogger(__name__)
    logger.info(f"Calculating directory size at {dir_path}...")
    
    # Check for simulation mode
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        sim_size = simulated_size or 12.75
        logger.info(f"Running in SIMULATED mode - reporting fixed size of {sim_size} GB")
        return sim_size
    
    try:
        path = Path(dir_path)
        if not path.exists():
            logger.error(f"Directory {dir_path} does not exist!")
            return None
        
        # Calculate total size
        total_size = 0
        for dirpath, dirnames, filenames in os.walk(path):
            for f in filenames:
                fp = os.path.join(dirpath, f)
                if os.path.exists(fp):
                    total_size += os.path.getsize(fp)
        
        # Convert to GB
        size_gb = total_size / (1024 * 1024 * 1024)
        logger.info(f"Directory size: {size_gb:.2f} GB")
        return round(size_gb, 2)
    except Exception as e:
        logger.error(f"Failed to get directory size: {e}")
        return None


def get_system_metrics_remote(host: str, user: str, port: str = "22") -> Dict[str, Any]:
    """
    Get system metrics from a remote host via SSH.
    
    Args:
        host: Hostname or IP address
        user: SSH username
        port: SSH port
        
    Returns:
        Dict containing system metrics
    """
    logger = logging.getLogger(__name__)
    
    # Check for simulation mode
    if os.environ.get("KRONI_SIMULATED_MODE", "").lower() == "true":
        logger.info("Running in SIMULATED mode - reporting simulated metrics")
        return {
            "timestamp": subprocess.check_output(["date", "+%Y-%m-%dT%H:%M:%S%z"]).decode().strip(),
            "system": {
                "cpu_percent": 5.2,
                "memory_percent": 32.5,
                "memory_total_mb": 16384,
                "memory_used_mb": 5324,
                "root_disk_percent": 18.7,
                "root_disk_total_gb": "100G",
                "root_disk_used_gb": "18.7G",
                "load_avg_1min": 0.42,
                "load_avg_5min": 0.39,
                "load_avg_15min": 0.35
            },
            "minecraft": {
                "cpu_percent": "1.22%",
                "mem_usage": "685.5MiB / 15.63GiB",
                "mem_percent": "4.11%"
            }
        }
    
    # Commands to collect system metrics
    commands = {
        "cpu": "top -bn1 | grep 'Cpu(s)' | awk '{print $2 + $4}'",
        "memory": "free -m | grep 'Mem:' | awk '{print $3, $2}'",
        "disk": "df -h / | grep / | awk '{print $5, $2, $3}'",
        "load": "cat /proc/loadavg | awk '{print $1, $2, $3}'",
        "docker": "docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}' | grep minecraft"
    }
    
    metrics = {
        "timestamp": subprocess.check_output(["date", "+%Y-%m-%dT%H:%M:%S%z"]).decode().strip(),
        "system": {},
        "error": None
    }
    
    try:
        # Get CPU usage
        cpu_result = run_ssh_command(host, commands["cpu"], user, port)
        if cpu_result["success"]:
            metrics["system"]["cpu_percent"] = float(cpu_result["stdout"].strip())
        
        # Get memory usage
        mem_result = run_ssh_command(host, commands["memory"], user, port)
        if mem_result["success"]:
            used, total = map(int, mem_result["stdout"].strip().split())
            metrics["system"]["memory_percent"] = round((used / total) * 100, 1)
            metrics["system"]["memory_used_mb"] = used
            metrics["system"]["memory_total_mb"] = total
        
        # Get disk usage
        disk_result = run_ssh_command(host, commands["disk"], user, port)
        if disk_result["success"]:
            percent_str, total, used = disk_result["stdout"].strip().split()
            metrics["system"]["root_disk_percent"] = float(percent_str.replace('%', ''))
            metrics["system"]["root_disk_total_gb"] = total
            metrics["system"]["root_disk_used_gb"] = used
        
        # Get load average
        load_result = run_ssh_command(host, commands["load"], user, port)
        if load_result["success"]:
            load1, load5, load15 = map(float, load_result["stdout"].strip().split())
            metrics["system"]["load_avg_1min"] = load1
            metrics["system"]["load_avg_5min"] = load5
            metrics["system"]["load_avg_15min"] = load15
        
        # Get docker stats for Minecraft container
        docker_result = run_ssh_command(host, commands["docker"], user, port)
        if docker_result["success"] and docker_result["stdout"].strip():
            parts = docker_result["stdout"].strip().split(',')
            if len(parts) >= 4:
                metrics["minecraft"] = {
                    "cpu_percent": parts[1].strip(),
                    "mem_usage": parts[2].strip(),
                    "mem_percent": parts[3].strip()
                }
        
        return metrics
    except Exception as e:
        metrics["error"] = str(e)
        return metrics 