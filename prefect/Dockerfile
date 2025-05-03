FROM python:3.10-slim
WORKDIR /app

# Update the system packages
RUN apt-get update && apt-get install -y \
    gcc \
    git \
    openssh-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Installing Prefect & Other dependencies
RUN pip install --upgrade pip \
    prefect==2.13.0 boto3 requests psutil paramiko python-dotenv griffe>=0.20.0

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

# Create Entrypoint script
RUN echo '#!/bin/bash\n\
    if [ "$1" = "server" ]; then\n\
    echo "Starting Prefect server..."\n\
    prefect server start\n\
    elif [ "$1" = "agent" ]; then\n\
    echo "Starting Prefect agent..."\n\
    prefect agent start -q default\n\
    else\n\
    echo "Unknown command: $1"\n\
    echo "Usage: $0 {server|agent}"\n\
    exit 1\n\
    fi\n\
    ' > /app/entrypoint.sh && chmod +x /app/entrypoint.sh

#Expose Prefect UI port
EXPOSE 4200

# Set entrypoint
ENTRYPOINT ["/app/entrypoint.sh"]

# Default to server mode
CMD ["server"]



