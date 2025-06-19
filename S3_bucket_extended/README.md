##S3 Bucket Extended

This project contains a set of shell scripts designed to automate the deployment of a web application to a temporary AWS EC2 instance. The automation handles infrastructure provisioning, application setup, and crucially, archives instance logs to a private S3 bucket upon shutdown. The system is designed to work with different deployment stages, such as development and production, by using stage-specific configuration files.

##Features
Stage-Based Deployment: Utilizes configuration files for different environments (Dev or Prod).
Automated AWS Resource Provisioning:
Creates a unique, private S3 bucket for log storage.
Configures an S3 lifecycle policy to automatically expire logs after 7 days.
Creates IAM Policies and Roles with least-privilege access for S3 read and write operations.
EC2 Instance Management:
Launches an EC2 instance (t2.micro Amazon Linux 2 by default) in the ap-northeast-2 region.
Uses a user_data script to bootstrap the instance with necessary software and application code.
Schedules the instance to automatically stop after a configurable duration (15 minutes by default).

#Log Management:
A shutdown script is installed on the EC2 instance, which activates when the instance is stopped.
This script archives cloud-init and application logs into a .tar.gz file and uploads it to the designated S3 bucket.

#Verification and Testing:
The main script tests if the application is reachable on its public IP after deployment.
It verifies that the S3 read-only role is functioning correctly by attempting to list the uploaded logs and confirming that write access is denied.

#Cleanup Guidance: 
At the end of its execution, the script generates and displays the specific AWS CLI commands required for manual cleanup of all created resources.

#File Structure

ec2_deploy.sh: The main orchestration script that handles resource creation, EC2 launch, and verification.
user_data_script.sh: The bootstrap script that runs on the EC2 instance at launch to set up the environment and application.
dev_config.sh: Configuration file for the "Development" environment.
prod_config.sh: Configuration file for the "Production" environment.

Prerequisites
Before running the deployment script, ensure the following are in place:

1.AWS CLI: The AWS Command Line Interface must be installed and configured with credentials that have sufficient permissions to create IAM roles/policies, EC2 instances, and S3 buckets.
2.jq: A command-line JSON processor is required to parse credentials from AWS CLI output.
3.AWS Key Pair: An EC2 Key Pair must exist in your target AWS region. The script is configured to use a key named techeazy-key.
4.AWS Security Group: An EC2 Security Group named Techeazy SG must exist. It must allow inbound traffic on port 22 (SSH) and port 80 (HTTP) from your IP for testing.

##How to Use
Configure Script Variables:
Open ec2_deploy.sh and modify any variables at the top of the file, such as REGION, AMI_ID, KEY_NAME, or SECURITY_GROUP to match your AWS environment.

Set Script Permissions:
Make the main deployment script executable:

Bash

chmod +x ec2_deploy.sh
Run the Deployment:
Execute the script with the desired stage (Dev or Prod) as an argument.

For a Development deployment:

Bash

./ec2_deploy.sh Dev
For a Production deployment:

Bash

./ec2_deploy.sh Prod

Monitor the Output:
The script will log its progress, including resource creation, instance launch, and verification steps. It will provide the public IP address of the running application.

##Automation Workflow Explained
1.Initiation: A user runs ./ec2_deploy.sh <Stage>.
2.Configuration: The script loads environment variables from the corresponding dev_config.sh or prod_config.sh file.
3.IAM & S3 Setup: The script creates the required IAM roles, policies, and a private S3 bucket for logs.
4.EC2 Launch: An EC2 instance is launched, and the user_data_script.sh is passed to it for execution.
5.Instance Provisioning: The user_data script runs on the instance, installing dependencies (git, python3, java), cloning the application repository, and starting a Python web server. It also sets up a shutdown hook to upload logs.
6.Auto-Stop Schedule: The ec2_deploy.sh script starts a background process that will issue an aws ec2 stop-instances command after 15 minutes.
7.Log Archival: When the instance stops, the shutdown script is triggered, which archives logs and uploads them to S3.
8.Verification: The main script waits for the instance to stop, then assumes the read-only IAM role to verify that logs exist in the S3 bucket.

#Manual Resource Cleanup
IMPORTANT: The script does not automatically delete the AWS resources it creates. You must do this manually to avoid incurring costs. The script will print the exact commands needed for cleanup at the end of its execution.

A sample of the generated cleanup commands:

Bash

INSTANCE_ID="i-0123456789abcdef0"
S3_BUCKET_NAME="techeazy-devops-logs-20250619114510"
AWS_ACCOUNT_ID="123456789012"
S3_WRITE_ROLE_NAME="TecheazyS3WriteRole"
S3_READ_ONLY_ROLE_NAME="TecheazyS3ReadOnlyRole"
EC2_INSTANCE_PROFILE_NAME="TecheazyEC2S3WriteProfile"
REGION="ap-northeast-2"

aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID --region $REGION
aws s3 rm "s3://$S3_BUCKET_NAME/" --recursive --region $REGION
aws s3api delete-bucket --bucket "$S3_BUCKET_NAME" --region $REGION
aws iam detach-role-policy --role-name "$S3_WRITE_ROLE_NAME" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_WRITE_ROLE_NAME}Policy" --region $REGION
aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_WRITE_ROLE_NAME}Policy" --region $REGION
aws iam detach-role-policy --role-name "$S3_READ_ONLY_ROLE_NAME" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_READ_ONLY_ROLE_NAME}Policy" --region $REGION
aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_READ_ONLY_ROLE_NAME}Policy" --region $REGION
aws iam remove-role-from-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" --role-name "$S3_WRITE_ROLE_NAME" --region $REGION
aws iam delete-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" --region $REGION
aws iam delete-role --role-name "$S3_WRITE_ROLE_NAME" --region $REGION
aws iam delete-role --role-name "$S3_READ_ONLY_ROLE_NAME" --region $REGION
