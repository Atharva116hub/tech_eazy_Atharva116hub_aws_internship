#ec2-deploy.sh

#!/bin/bash

AMI_ID="ami-09a38f1a6411fbe1a"  # Amazon Linux 2
INSTANCE_TYPE="t2.micro"
KEY_NAME="techeazy-key"
KEY_PATH="$HOME/.ssh/techeazy-key.pem"
SECURITY_GROUP="Techeazy SG"
REPO_URL="https://github.com/Atharva116hub/tech_eazy_Atharva116hub_aws_internship.git"
STOP_AFTER=15  # minutes
REGION="ap-northeast-2"

echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region $REGION \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-groups "$SECURITY_GROUP" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Instance ID: $INSTANCE_ID"

aws ec2 wait instance-status-ok --region $REGION --instance-ids $INSTANCE_ID

sleep 20  # give AWS some buffer time to assign IP

PUBLIC_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --instance-ids $INSTANCE_ID \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "Public IP: $PUBLIC_IP"

# Check if public IP is missing
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "[✗] Could not get Public IP, retrying after delay..."
  sleep 20
  PUBLIC_IP=$(aws ec2 describe-instances \
    --region $REGION \
    --instance-ids $INSTANCE_ID \
    --query "Reservations[0].Instances[0].PublicIpAddress" \
    --output text)
fi

# Exit if still no IP
if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
  echo "[✗] Still failed to fetch Public IP. Exiting."
  exit 1
fi

echo "Connecting to EC2 and deploying..."
ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" ec2-user@$PUBLIC_IP <<EOF
sudo yum update -y
sudo yum install -y git python3
git clone $REPO_URL app
cd app
sudo nohup python3 main.py &
EOF

echo "App deployed at: http://$PUBLIC_IP"

(sleep $(($STOP_AFTER * 60)) && aws ec2 stop-instances --region $REGION --instance-ids $INSTANCE_ID) &


