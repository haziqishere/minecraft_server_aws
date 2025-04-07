# Create Lightsail instance
resource "aws_lightsail_instance" "minecraft_server" {
  name              = var.lightsail_instance_name
  availability_zone = "${var.aws_region}a"
  blueprint_id      = var.lightsail_instance_blueprint
  bundle_id         = var.lightsail_instance_bundle
  key_pair_name     = var.ssh_key_name

  tags = {
    Name = var.lightsail_instance_name
  }
}

# Create a static IP for the Lightsail instance
resource "aws_lightsail_static_ip" "minecraft_server" {
  name = "${var.lightsail_instance_name}-static-ip"

  depends_on = [aws_lightsail_instance.minecraft_server]
}

# Attach static IP to the Lightsail instance
resource "aws_lightsail_static_ip_attachment" "minecraft_server" {
  static_ip_name = aws_lightsail_static_ip.minecraft_server.name
  instance_name  = aws_lightsail_instance.minecraft_server.name
}

# Create a block storage volume for the Minecraft world data
resource "aws_lightsail_disk" "minecraft_data" {
  name              = var.lightsail_volume_name
  size_in_gb        = var.lightsail_volume_size
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = var.lightsail_volume_name
  }
}

# Attach the block storage volume to the Lightsail instance
resource "aws_lightsail_disk_attachment" "minecraft_data" {
  disk_name     = aws_lightsail_disk.minecraft_data.name
  instance_name = aws_lightsail_instance.minecraft_server.name
  disk_path     = "/dev/xvdf"

  depends_on = [
    aws_lightsail_instance.minecraft_server,
    aws_lightsail_disk.minecraft_data
  ]
}

# Configure firewall rules for the Lightsail instance
resource "aws_lightsail_instance_public_ports" "minecraft_server" {
  instance_name = aws_lightsail_instance.minecraft_server.name

  # Allow Minecraft server port
  port_info {
    protocol  = "tcp"
    from_port = var.minecraft_server_port
    to_port   = var.minecraft_server_port
  }

  # Allow SSH access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.ssh_allowed_cidrs
  }
}

# Create S3 bucket for backups
resource "aws_s3_bucket" "minecraft_backups" {
  bucket = var.s3_backup_bucket_name

  tags = {
    Name = var.s3_backup_bucket_name
  }
}

# Configure S3 bucket to prevent public access
resource "aws_s3_bucket_public_access_block" "minecraft_backups" {
  bucket = aws_s3_bucket.minecraft_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Set lifecycle policy for S3 backup objects
resource "aws_s3_bucket_lifecycle_configuration" "minecraft_backups" {
  bucket = aws_s3_bucket.minecraft_backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects in the bucket
    }

    expiration {
      days = 90
    }
  }
}

# Create IAM user for Lightsail snapshots and S3 backups
resource "aws_iam_user" "minecraft_backup" {
  name = "kroni-survival-backup-user"

  tags = {
    Name = "kroni-survival-backup-user"
  }
}

# Create IAM policy for Lightsail snapshots
resource "aws_iam_policy" "lightsail_snapshot_policy" {
  name        = "kroni-survival-lightsail-snapshot-policy"
  description = "Policy for creating and managing Lightsail snapshots"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "lightsail:CreateInstanceSnapshot",
          "lightsail:CreateDiskSnapshot",
          "lightsail:GetInstanceSnapshot",
          "lightsail:GetInstanceSnapshots",
          "lightsail:GetDiskSnapshot",
          "lightsail:GetDiskSnapshots",
          "lightsail:DeleteInstanceSnapshot",
          "lightsail:DeleteDiskSnapshot"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

# Create IAM policy for S3 backups
resource "aws_iam_policy" "s3_backup_policy" {
  name        = "kroni-survival-s3-backup-policy"
  description = "Policy for uploading Minecraft world backups to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_s3_bucket.minecraft_backups.arn}",
          "${aws_s3_bucket.minecraft_backups.arn}/*"
        ]
      }
    ]
  })
}

# Attach policies to IAM user
resource "aws_iam_user_policy_attachment" "lightsail_snapshot_attachment" {
  user       = aws_iam_user.minecraft_backup.name
  policy_arn = aws_iam_policy.lightsail_snapshot_policy.arn
}

resource "aws_iam_user_policy_attachment" "s3_backup_attachment" {
  user       = aws_iam_user.minecraft_backup.name
  policy_arn = aws_iam_policy.s3_backup_policy.arn
}

# Create access key for IAM user
resource "aws_iam_access_key" "minecraft_backup" {
  user = aws_iam_user.minecraft_backup.name
}

# Generate provisioner script using built-in templatefile function
locals {
  provisioner_script = templatefile("${path.module}/provisioner.sh", {
    # Original lowercase variables
    aws_region              = var.aws_region
    volume_device           = "/dev/xvdf"
    volume_mount_path       = var.lightsail_volume_mount_path
    minecraft_world_path    = var.minecraft_world_path
    minecraft_docker_image  = var.minecraft_docker_image
    minecraft_server_port   = var.minecraft_server_port
    backup_schedule_cron    = var.backup_schedule_cron
    snapshot_schedule_cron  = var.snapshot_schedule_cron
    s3_backup_bucket        = var.s3_backup_bucket_name
    discord_webhook_url     = var.discord_webhook_url
    aws_access_key          = aws_iam_access_key.minecraft_backup.id
    aws_secret_key          = aws_iam_access_key.minecraft_backup.secret
    instance_name           = var.lightsail_instance_name
    volume_name             = var.lightsail_volume_name
    snapshot_retention_days = var.snapshot_retention_days

    # Add uppercase variants that are used in the script
    MINECRAFT_SERVER_PORT  = var.minecraft_server_port
    MINECRAFT_WORLD_PATH   = var.minecraft_world_path
    MINECRAFT_DOCKER_IMAGE = var.minecraft_docker_image
  })
}

# Provision the Lightsail instance
resource "null_resource" "provision_server" {
  # Trigger the provisioner when any of these resources change
  triggers = {
    instance_id     = aws_lightsail_instance.minecraft_server.id
    disk_attachment = aws_lightsail_disk_attachment.minecraft_data.id
    script_hash     = sha256(local.provisioner_script)
  }

  # Connect to the Lightsail instance via SSH
  connection {
    type        = "ssh"
    user        = "ec2-user"
    host        = aws_lightsail_static_ip.minecraft_server.ip_address
    private_key = file("~/.ssh/${var.ssh_key_name}.pem")
  }

  # Copy the provisioner script to the server
  provisioner "file" {
    content     = local.provisioner_script
    destination = "/tmp/provisioner.sh"
  }

  # Execute the provisioner script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/provisioner.sh",
      "sudo /tmp/provisioner.sh"
    ]
  }

  depends_on = [
    aws_lightsail_static_ip_attachment.minecraft_server,
    aws_lightsail_disk_attachment.minecraft_data,
    aws_iam_user_policy_attachment.lightsail_snapshot_attachment,
    aws_iam_user_policy_attachment.s3_backup_attachment
  ]
}
