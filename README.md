# Kroni Survival Minecraft Server

A lightweight, cost-effective, self-hosted Minecraft server infrastructure on AWS Lightsail using Infrastructure as Code (Terraform).

## Project Overview

Kroni Survival is a Minecraft server deployment solution that provides:

- AWS Lightsail instance (1 vCPU, 1GB RAM) in Malaysia region
- Docker-based Minecraft server with cracked client support
- Persistent storage for world data
- Automated backups (S3 and Lightsail snapshots)
- Monitoring via CloudWatch and Grafana
- Discord notifications for server events

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) (v1.0.0+)
- [AWS CLI](https://aws.amazon.com/cli/) configured with appropriate credentials
- SSH key pair registered with AWS Lightsail
- S3 bucket for Terraform state (optional but recommended)

## Project Structure

```
minecraft-server-on-aws/
├── terraform/
│   ├── main.tf          # Main Terraform configuration
│   ├── variables.tf     # Input variables
│   ├── outputs.tf       # Output values
│   ├── provider.tf      # AWS provider configuration
│   └── provisioner.sh   # Server provisioning script
├── scripts/
│   ├── docker-install.sh    # Docker installation script
│   ├── backup-to-s3.sh      # S3 backup script
│   └── notify-discord.sh    # Discord notification script
├── prefect/
│   └── snapshot_flow.py     # Prefect workflow for backups
├── .github/
│   └── workflows/
│       └── terraform.yml    # GitHub Actions workflow
├── README.md                # Project documentation
└── .env.example             # Example environment variables
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

The server metrics are available in CloudWatch. If you've set up Grafana Cloud:

1. Log in to your Grafana Cloud account
2. Navigate to the Kroni Survival dashboard

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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.