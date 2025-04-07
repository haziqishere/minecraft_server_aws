#!/bin/bash
set -e

echo "=== Installing Docker on Amazon Linux 2 ==="

# Update system packages
sudo yum update -y

# Install Docker

sudo amazon-linux-extras install docker -y

# Start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add ec2-user to the docker group to run Docker without sudo
sudo usermod -aG docker ec2-user

# Verify Docker installation
docker --version

echo "=== Docker installation completed successfully ==="
echo "=== NOTE: You may need to log out and log back in for group changes to take effect ==="