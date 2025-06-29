# 🎮 Kroni Survival Minecraft Server on AWS

## Project Overview

Kroni Survival is a Minecraft server deployment solution that provides:

- AWS Lightsail instance (4 vCPU, 4GB RAM) in Singapore region
- Docker-based Minecraft server with cracked client support
- Persistent storage for world data
- Automated backups (S3 and Lightsail snapshots)
- Monitoring via CloudWatch and Grafana
- Discord notifications for server events


## 📝 Key Features

- **AWS Lightsail Instance** with Docker
- **Minecraft Server** (with cracked client support)
- **Persistent Storage** with Lightsail Block Storage
- **Automated Backups**:
  - Lightsail snapshots (biweekly)
  - S3 backups
- **Discord Notifications** for backups and monitoring
- **Prefect Workflows** for server monitoring and backup automation

## 🏗️ Architecture

![Kroni Survival AWS Architecture](documents/Phase%202%20Architecture.png)

```
                   ┌──────────────────────────────┐
                   │       You & Friends          │
                   │       (Singapore)            │
                   └────────────┬─────────────────┘
                                │
                                ▼
                   ┌──────────────────────────────┐
                   │     Lightsail Firewall       │
                   │   - Port 25565 (MC)          │
                   │   - Port 22 (optional SSH)   │
                   │   - Port 4200 (Prefect UI)   │
                   └────────────┬─────────────────┘
                                ▼
                   ┌──────────────────────────────┐
                   │  Lightsail Instance          │
                   │  - 2vCPU, 2GB RAM (small_3_0) │
                   │  - Docker                    │
                   │  - Minecraft Container       │
                   └────────────┬─────────────────┘
                                │
                                ▼
                   ┌──────────────────────────────┐
                   │  Lightsail Block Storage     │
                   │  - Mounted to /data          │
                   │  - World stored at /data/world │
                   └────────────┬─────────────────┘
                                ▼
       ┌────────────────────────┴────────────────────────┐
       │              Automation & Monitoring            │
       │ ┌────────────────┐ ┌─────────────────────────┐  │
       │ │ Prefect (DAG)  │ │ GitHub Actions (CI/CD)  │  │
       │ └────────────────┘ └─────────────────────────┘  │
       │ ┌────────────────────────────────────────────┐  │
       │ │ Cron Jobs (Snapshots + S3 backup scripts)  │  │
       │ └────────────────────────────────────────────┘  │
       │ ┌────────────────────────────────────────────┐  │
       │ │ CloudWatch Agent → Grafana Cloud Dashboard │  │
       │ └────────────────────────────────────────────┘  │
       └─────────────────────────────────────────────────┘
```

## 🏗️ Prerequisites
- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0+)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- SSH key pair registered with AWS Lightsail
- S3 bucket for Terraform state (optional but recommended)

 prefect/
│   └── snapshot_flow.py     # Prefect workflow for backups
├── .github/
│   └── workflows/
│       └── terraform.yml    # GitHub Actions workflow
├── README.md                # Project documentation
└── .env.example             # Example environment variables

- Discord webhook URL (for notification)

# Minecraft Server Monitoring

## Prefect Monitoring System

This repository contains a Prefect-based monitoring system for Minecraft servers running on AWS EC2. The system:

1. Checks if the Minecraft server is running
2. Collects system metrics (CPU, memory, disk usage)
3. Measures world size growth
4. Sends notifications to Discord

For detailed setup and usage instructions, see [prefect/README.md](prefect/README.md).

### Quick Start

For a guided setup process, use the quick setup script:

```bash
cd prefect
./quick_setup.sh
```

Or for manual setup:

```bash
# Set up SSH authentication
cd prefect/bin
./setup_ec2_auth.sh <path_to_key.pem> <ec2_ip> ec2-user

# Deploy the monitoring flow
./deploy_monitoring.sh
```

## Deployment Instructions


### Initial Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/minecraft-server-on-aws.git
   cd minecraft-server-on-aws
   ```

2. Create a copy of `.env.example` as `.env` and fill in your settings:
   ```bash
   cp .env.example .env
   # Edit .env with your preferred text editor
   ```

3. Initialize Terraform:
   ```bash
   cd terraform
   terraform init
   ```

### Deployment

4. Review the Terraform plan:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

6. Once deployed, Terraform will output the server IP address and other important information.

## Accessing the Minecraft Server

Connect to the server using the IP address from the Terraform output and port 25565.

## Backup and Restore

Two types of backups are configured:

- S3 Backups: Daily tar-compressed world data
- Lightsail Snapshots: Biweekly snapshots of both instance and data volume

### Manual Backup

To manually trigger a backup:

```bash
ssh ec2-user@<server-ip>
sudo /opt/kroni-survival/scripts/backup-to-s3.sh
```

### Restore from Backup

To restore from an S3 backup:

```bash
# Instructions for restoration will be added
```

## Monitoring

📊 Monitoring
The system includes a Prefect dashboard for monitoring server status and scheduled tasks:

Prefect UI: Access at http://your-server-ip:4200
CloudWatch Metrics: View in AWS Console or Grafana dashboard
Discord Notifications: Regular updates on server health and backups

## Maintenance

### Stopping the Server

```bash
ssh ec2-user@<server-ip>
sudo docker stop minecraft-server
```

### Starting the Server

```bash
ssh ec2-user@<server-ip>
sudo docker start minecraft-server
```

### Viewing Logs

```bash
ssh ec2-user@<server-ip>
sudo docker logs minecraft-server
```

## Cost Estimates

- AWS Lightsail micro_2_0: ~$5/month
- Block Storage (20GB): ~$2/month
- S3 Storage for backups: Varies based on world size
- Data Transfer: Varies based on player count


## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgements

- [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server) Docker image
- [Prefect](https://www.prefect.io/) for workflow automation
- [Terraform](https://www.terraform.io/) for infrastructure as code