import paramiko
import logging
import datetime
import os
from typing import Tuple, Optional, Dict, Any

logger = logging.getLogger(__name__)

class RemoteExecutor:
    """Helper class for executing commands on the Minecraft server via SSH."""
    def __init__(self, hostname: str, username: str = "ec2-user", 
                 key_path: str = "~/.ssh/github-action-key"): # TODO: Try change to github-action-key from /.ssh/kroni-survival-key.pem
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
            
            logger.info(f"Downloaded {remote_path} to local path: {local_path}")
            return True
        except Exception as e:
            logger.error(f"Failed to download file: {e}")
            return False
    
    def remove_file(self, path: str) -> bool:
        """
        Remove a file from the remote server.
        
        Args:
            path: Path to the file on the remote server
            
        Returns:
            True if successful, False otherwise
        """
        command = f"rm -f {path}"
        exit_code, _, _ = self.execute_command(command)
        return exit_code == 0
    
    def __enter__(self):
        """Context manager entry point."""
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit point."""
        self.disconnect()