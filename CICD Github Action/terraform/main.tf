provider "aws" {
  region = var.region
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.stage}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.stage}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.stage}-ec2-log-bucket"
}

resource "aws_instance" "web" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [var.sg_id]

  tags = {
    Name  = "${var.stage}-ec2-instance"
    Stage = var.stage
  }
}
