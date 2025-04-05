output "minecraft_server_ip" {
  description = "Public IP address of the Minecraft server"
  value       = aws_lightsail_static_ip.minecraft_server.ip_address
}

output "minecraft_server_dns" {
  description = "DNS name of the Minecraft server"
  value       = aws_lightsail_instance.minecraft_server.public_dns
}

output "minecraft_server_port" {
  description = "Port of the Minecraft server"
  value       = var.minecraft_server_port
}

output "minecraft_data_volume_path" {
  description = "Path where the Minecraft data volume is mounted"
  value       = var.lightsail_volume_mount_path
}

output "minecraft_world_path" {
  description = "Path to the Minecraft world data"
  value       = var.minecraft_world_path
}

output "s3_backup_bucket" {
  description = "Name of the S3 bucket for Minecraft world backups"
  value       = aws_s3_bucket.minecraft_backups.id
}

output "backup_user_name" {
  description = "Name of the IAM user for backups"
  value       = aws_iam_user.minecraft_backup.name
}

output "backup_user_access_key" {
  description = "Access key ID of the IAM user for backups"
  value       = aws_iam_access_key.minecraft_backup.id
  sensitive   = true
}

output "backup_schedule" {
  description = "Schedule for S3 backups (cron expression)"
  value       = var.backup_schedule_cron
}

output "snapshot_schedule" {
  description = "Schedule for Lightsail snapshots (cron expression)"
  value       = var.snapshot_schedule_cron
}