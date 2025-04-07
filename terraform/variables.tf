variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "prod"
}

variable "lightsail_instance_name" {
  description = "Name of the Lightsail instance"
  type        = string
  default     = "kroni-survival-server"
}

variable "lightsail_instance_blueprint" {
  description = "Lightsail instance OS blueprint"
  type        = string
  default     = "amazon_linux_2"
}

variable "lightsail_instance_bundle" {
  description = "Lightsail instance bundle (size)"
  type        = string
  default     = "micro_2_0"
}

variable "lightsail_volume_size" {
  description = "Size of the Lightsail block storage volume in GB"
  type        = number
  default     = 20
}

variable "lightsail_volume_name" {
  description = "Name of the Lightsail block storage volume"
  type        = string
  default     = "kroni-survival-volume"
}

variable "lightsail_volume_mount_path" {
  description = "Path to mount the Lightsail block storage volume"
  type        = string
  default     = "/data"
}

variable "minecraft_world_path" {
  description = "Path to Minecrafat world data inside the volume"
  type        = string
  default     = "/data/world"
}

variable "minecraft_docker_image" {
  description = "Docker image for Minecraft Server"
  type        = string
  default     = "itzg/minecraft-server:latest"
}

variable "minecraft_server_port" {
  description = "Port for Minecraft server"
  type        = number
  default     = 25565
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed for SSH access"
  type        = list(string)
  default     = ["0.0.0.0/0"] # This should be restricted in production
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair for Lightsail instance"
  type        = string
  default     = "kroni-survival-key"
}

variable "s3_backup_bucket_name" {
  description = "Name of the S3 bucket for world backups"
  type        = string
  default     = "kroni-survival-backups"
}

variable "discord_webhook_url" {
  description = "Discord webhook URL for notifications"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_schedule_cron" {
  description = "Cron schedule for S3 backups"
  type        = string
  default     = "0 0 */3 * *" # Every 3 days at midnight
}

variable "snapshot_schedule_cron" {
  description = "Cron schedule for Lightsail snapshots"
  type        = string
  default     = "0 0 */14 * *" # Biweekly at midnight
}

variable "snapshot_retention_days" {
  description = "Number of days to retain snapshots"
  type        = number
  default     = 30
}
