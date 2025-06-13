# AWS EC2 Auto Deployment with Terraform and GitHub Actions

## Features
- Infrastructure provisioning with Terraform (EC2 + IAM + S3)
- App deployment using Bash (`ec2-deploy.sh`)
- CI/CD via GitHub Actions on push or tag
- Upload logs to S3
- Auto health check of deployed app

## Usage

1. Configure AWS credentials in GitHub Actions Secrets.
2. Push to `main` or tag as `deploy-dev` or `deploy-prod`.
3. App deploys automatically and validates port 80.

