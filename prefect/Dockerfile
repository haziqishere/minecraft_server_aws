FROM python:3.10-slim
WORKDIR /app

# Update the system packages
RUN apt-get update && apt-get install -y \
    gcc \
    git \
    openssh-client \
    curl \
    iputils-ping \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Installing Prefect & Other dependencies
RUN pip install --upgrade pip \
    prefect==3.4.0 boto3==1.38.8 requests==2.32.2 psutil==7.0.0 paramiko==3.5.1 python-dotenv==1.1.0 pydantic==2.11.4 griffe==1.7.3 aiosqlite==0.21.0 sqlalchemy==2.0.40

#-----------------------------------------------------------------------#
# Configure the Prefect server

# Create working directories of prefect, ssh and aws
RUN mkdir -p ~/.prefect && \
    mkdir -p /opt/prefect/flows 
RUN mkdir -p ~/.ssh
RUN mkdir -p ~/.aws


# Configure SSH for remote execution
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
RUN echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

# Set up Env Varaibles
ENV PYTHONUNBUFFERED=1
ENV PATH="/app:${PATH}"

# Create Entrypoint script with improved error handling and debugging
RUN echo '#!/bin/bash\n\
    set -e\n\
    \n\
    function log() {\n\
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1"\n\
    }\n\
    \n\
    # Add host entry if environment variable is set\n\
    if [ -n "$PREFECT_EXTRA_ENTRYPOINT_COMMANDS" ]; then\n\
    log "Running extra entrypoint commands..."\n\
    eval "$PREFECT_EXTRA_ENTRYPOINT_COMMANDS"\n\
    fi\n\
    \n\
    # Add manual host entry for prefect-server\n\
    if ! grep -q "prefect-server" /etc/hosts; then\n\
    log "Adding prefect-server to /etc/hosts..."\n\
    if [ -n "$PREFECT_API_URL" ]; then\n\
    SERVER_HOST=$(echo "$PREFECT_API_URL" | sed -E "s|https?://([^:/]+).*|\1|")\n\
    if [[ "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then\n\
    log "Found IP address in PREFECT_API_URL: $SERVER_HOST"\n\
    echo "$SERVER_HOST prefect-server" >> /etc/hosts\n\
    fi\n\
    fi\n\
    fi\n\
    \n\
    # Print network configuration\n\
    log "Host configuration:"\n\
    cat /etc/hosts\n\
    log "Network configuration:"\n\
    ip addr show\n\
    log "Checking connectivity to prefect-server:"\n\
    ping -c 1 172.28.0.2 || echo "Can'\''t ping server IP"\n\
    ping -c 1 prefect-server || echo "Can'\''t ping server hostname"\n\
    \n\
    function check_prefect_config() {\n\
    log "Checking Prefect configuration..."\n\
    log "PREFECT_API_URL=$PREFECT_API_URL"\n\
    python -c "import os; print(f\"HOME: {os.environ.get('\''HOME'\'')}\"); print(f\"USER: {os.environ.get('\''USER'\'')}\")" \n\
    log "Checking ~/.prefect directory..."\n\
    ls -la ~/.prefect || echo "~/.prefect not found"\n\
    log "Prefect version:"\n\
    prefect version\n\
    }\n\
    \n\
    if [ "$1" = "server" ]; then\n\
    log "Starting Prefect server..."\n\
    check_prefect_config\n\
    log "Current directory: $(pwd)"\n\
    log "Directory contents:"\n\
    ls -la\n\
    \n\
    log "Starting Prefect server with debug output..."\n\
    prefect config view\n\
    \n\
    # Start Prefect server with error trapping\n\
    prefect server start\n\
    exit_code=$?\n\
    if [ $exit_code -ne 0 ]; then\n\
    log "ERROR: Prefect server failed to start with exit code $exit_code"\n\
    log "Creating error file for diagnosis..."\n\
    echo "Exit code: $exit_code" > /opt/prefect/server_error.log\n\
    # Sleep instead of exiting to keep container running for diagnosis\n\
    log "Sleeping to keep container alive for debugging..."\n\
    sleep 3600\n\
    fi\n\
    elif [ "$1" = "worker" ]; then\n\
    log "Starting Prefect worker..."\n\
    check_prefect_config\n\
    \n\
    log "Waiting for server to be ready..."\n\
    # More robust server check\n\
    max_attempts=30\n\
    attempt=0\n\
    while [ $attempt -lt $max_attempts ]; do\n\
    attempt=$((attempt+1))\n\
    log "Checking server availability (attempt $attempt/$max_attempts)..."\n\
    if curl -s "$PREFECT_API_URL/health" | grep -q "healthy"; then\n\
    log "Server is healthy!"\n\
    break\n\
    elif [ $attempt -eq $max_attempts ]; then\n\
    log "ERROR: Server not available after $max_attempts attempts"\n\
    log "Will start worker anyway in case server becomes available later"\n\
    else\n\
    log "Server not ready, waiting..."\n\
    sleep 10\n\
    fi\n\
    done\n\
    \n\
    log "Creating work pool..."\n\
    prefect work-pool create default --type process || log "Work pool may already exist"\n\
    \n\
    log "Starting worker..."\n\
    prefect worker start --pool default\n\
    else\n\
    log "Unknown command: $1"\n\
    log "Usage: $0 {server|worker}"\n\
    exit 1\n\
    fi\n\
    ' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

#Expose Prefect UI port
EXPOSE 4200

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default to server mode
CMD ["server"]



