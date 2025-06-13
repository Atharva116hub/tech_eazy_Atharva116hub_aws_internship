provider "aws" {
  region = var.region
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "techeazy_sg" {
  name   = var.security_group_name
  vpc_id = data.aws_vpc.default.id
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "app_logs_bucket" {
  bucket = "techeazy-${var.stage}-logs-${data.aws_caller_identity.current.account_id}-${timestamp()}"
  acl    = "private"

  tags = {
    Name    = "${var.stage}-AppLogsBucket"
    Project = "TecheazyDevOps"
    Stage   = var.stage
  }
}

resource "aws_s3_bucket_public_access_block" "app_logs_bucket_block" {
  bucket = aws_s3_bucket.app_logs_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "log_retention_rule" {
  bucket = aws_s3_bucket.app_logs_bucket.id

  rule {
    id     = "DeleteOldLogs"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_iam_policy" "s3_read_only_policy" {
  name        = "${var.stage}-TecheazyS3ReadOnlyPolicy"
  description = "IAM policy for S3 read-only access to app logs bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.app_logs_bucket.arn
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.app_logs_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "s3_read_only_role" {
  name = "${var.stage}-TecheazyS3ReadOnlyRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read_only_attach" {
  role       = aws_iam_role.s3_read_only_role.name
  policy_arn = aws_iam_policy.s3_read_only_policy.arn
}

resource "aws_iam_policy" "s3_write_policy" {
  name        = "${var.stage}-TecheazyS3WritePolicy"
  description = "IAM policy for S3 write access to app logs bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.app_logs_bucket.arn,
          "${aws_s3_bucket.app_logs_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = aws_s3_bucket.app_logs_bucket.arn
      }
    ]
  })
}

resource "aws_iam_role" "s3_write_role" {
  name = "${var.stage}-TecheazyS3WriteRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_write_attach" {
  role       = aws_iam_role.s3_write_role.name
  policy_arn = aws_iam_policy.s3_write_policy.arn
}

resource "aws_iam_instance_profile" "ec2_s3_write_profile" {
  name = "${var.stage}-TecheazyEC2S3WriteProfile"
  role = aws_iam_role.s3_write_role.name
}

locals {
  stage_config_path    = "templates/${lower(var.stage)}_config.sh.tpl"
  stage_config_content = templatefile(local.stage_config_path, {
    app_env = var.app_env,
    db_host = var.db_host,
    api_key = var.api_key
  })
}

resource "aws_instance" "app_server" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  vpc_security_group_ids      = [data.aws_security_group.techeazy_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3_write_profile.name
  associate_public_ip_address = true

  user_data = templatefile("templates/user_data.sh.tpl", {
    s3_bucket_name     = aws_s3_bucket.app_logs_bucket.id
    repo_url           = var.repo_url
    region             = var.region
    app_name           = var.app_name
    app_port           = var.app_port
    stage              = var.stage
    stop_after_minutes = var.stop_after_minutes
    app_env            = var.app_env
    db_host            = var.db_host
    api_key            = var.api_key
  })

  tags = {
    Name    = "${var.stage}-AppServer"
    Project = "TecheazyDevOps"
    Stage   = var.stage
  }
}
