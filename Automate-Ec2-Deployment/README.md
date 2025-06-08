# AWS EC2 Auto Deployment

This project provides a simple Bash script (`ec2-deploy.sh`) to launch an EC2 instance on AWS, automatically install dependencies, clone a GitHub repository, and deploy a basic Python HTTP server (`main.py`). The instance is automatically stopped after a specified time.

---

## 📁 Project Structure

├── ec2-deploy.sh # Script to launch and deploy the app on EC2

├── main.py # Basic Python HTTP server (serves files over HTTP)

└── README.md # Project documentation

yaml

---

## 🚀 Deployment Overview

The script performs the following actions:

   1. Launches a new EC2 instance using Amazon Linux 2.
   2. Waits until the instance is up and running.
   3. Connects via SSH and:
   - Updates the system.
   - Installs `git` and `python3`.
   - Clones your GitHub repository.
   - Starts a Python HTTP server in the background using `nohup`.
   4. Automatically stops the EC2 instance after a specified    number of minutes.

---

## 🔧 Prerequisites

- AWS CLI installed and configured (`aws configure`)
- Valid AWS credentials with permission to launch EC2 instances
- An existing EC2 key pair
- The security group (`Techeazy SG`) should allow:
  - SSH (port 22)
  - HTTP (port 80)
- Key file saved at: `~/.ssh/techeazy-key.pem`

---

## ⚙️ Configuration

Update the following variables in `ec2-deploy.sh` as needed:

```bash
AMI_ID="ami-09a38f1a6411fbe1a"
INSTANCE_TYPE="t2.micro"
KEY_NAME="techeazy-key"
KEY_PATH="$HOME/.ssh/techeazy-key.pem"
SECURITY_GROUP="Techeazy SG"
REPO_URL="https://github.com/Atharva116hub/tech_eazy_Atharva116hub_aws_internship.git"
STOP_AFTER=15  # Stop instance after 15 minutes
REGION="ap-northeast-2"


## Usage

Run the deployment script:
chmod +x ec2-deploy.sh
./ec2-deploy.sh

If successful, the script will output:
App deployed at: http://<EC2_PUBLIC_IP>


##Notes

Port Binding: Ensure your EC2 instance runs the Python app with appropriate permissions. Port 80 may require sudo.

SSH Permissions: Make sure the key file has restricted permissions:

chmod 400 ~/.ssh/techeazy-key.pem

Instance Cost: The instance is only stopped, not terminated. Consider adding logic to terminate if desired.

Logs: Application output is sent to nohup.out on the EC2 instance. You can modify the script to redirect it elsewhere if needed.




## Optional Enhancements

Automatically terminate the EC2 instance after use.

Add logging and monitoring via AWS CloudWatch.

Use a higher port (e.g., 8000) to avoid using sudo.

Tag instances for easier management.
