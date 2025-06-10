#!/bin/bash
set -e
set -u
set -o pipefail

AMI_ID="ami-09a38f1a6411fbe1a" # Amazon Linux 2 in ap-northeast-2
INSTANCE_TYPE="t2.micro"
KEY_NAME="techeazy-key"
KEY_PATH="$HOME/.ssh/techeazy-key.pem"
SECURITY_GROUP="Techeazy SG"
REPO_URL="https://github.com/techeazy-consulting/techeazy-devops"
STOP_AFTER=15 # Minutes
REGION="ap-northeast-2" # Seoul
APP_NAME="techeazy-devops"
APP_PORT=80 # Python SimpleHTTPServer runs on port 80

S3_BUCKET_NAME="techeazy-devops-logs-$(date +%Y%m%d%H%M%S)" # Unique bucket name
S3_READ_ONLY_ROLE_NAME="TecheazyS3ReadOnlyRole"
S3_WRITE_ROLE_NAME="TecheazyS3WriteRole"
EC2_INSTANCE_PROFILE_NAME="TecheazyEC2S3WriteProfile"
LOG_RETENTION_DAYS=7

# Get AWS Account ID dynamically
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    echo "[✗] ERROR: Could not retrieve AWS Account ID. Ensure AWS CLI is configured."
    exit 1
fi
echo "AWS Account ID: $AWS_ACCOUNT_ID"

STAGE=""
CONFIG_FILE=""

if [ -n "$1" ]; then
    STAGE="$1"
    CONFIG_FILE="${STAGE}_config.sh"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[✗] ERROR: Configuration file '$CONFIG_FILE' not found for stage '$STAGE'."
        exit 1
    fi
    echo "Loading configuration for stage: $STAGE from $CONFIG_FILE"
    source "$CONFIG_FILE" # Load stage-specific configurations
else
    echo "[✗] ERROR: No stage parameter provided. Usage: ./ec2-deploy.sh <Dev|Prod>"
    exit 1
fi

echo "--- Starting EC2 Deployment Automation (Stage: $STAGE) ---"

# Create S3 Read-Only Policy and Role
echo "Creating S3 Read-Only Policy and Role: $S3_READ_ONLY_ROLE_NAME..."
aws iam create-policy --policy-name "${S3_READ_ONLY_ROLE_NAME}Policy" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        { "Effect": "Allow", "Action": ["s3:ListBucket"], "Resource": "arn:aws:s3:::'"$S3_BUCKET_NAME"'" },
        { "Effect": "Allow", "Action": ["s3:GetObject"], "Resource": "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*" }
    ]
}' --region "$REGION"
aws iam create-role --role-name "$S3_READ_ONLY_ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{ "Effect": "Allow", "Principal": { "AWS": "arn:aws:iam::'"$AWS_ACCOUNT_ID"':root" }, "Action": "sts:AssumeRole" }]
}' --region "$REGION"
aws iam attach-role-policy --role-name "$S3_READ_ONLY_ROLE_NAME" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_READ_ONLY_ROLE_NAME}Policy" --region "$REGION"

# Create S3 Write Policy and Role for EC2
echo "Creating S3 Write Policy and Role for EC2: $S3_WRITE_ROLE_NAME..."
aws iam create-policy --policy-name "${S3_WRITE_ROLE_NAME}Policy" --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{ "Effect": "Allow", "Action": ["s3:CreateBucket", "s3:PutObject", "s3:PutObjectAcl", "s3:ListBucket"], "Resource": ["arn:aws:s3:::'"$S3_BUCKET_NAME"'", "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*"] }]
}' --region "$REGION"
aws iam create-role --role-name "$S3_WRITE_ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{ "Effect": "Allow", "Principal": { "Service": "ec2.amazonaws.com" }, "Action": "sts:AssumeRole" }]
}' --region "$REGION"
aws iam attach-role-policy --role-name "$S3_WRITE_ROLE_NAME" --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${S3_WRITE_ROLE_NAME}Policy" --region "$REGION"

# Attach role to EC2 via instance profile
echo "Creating EC2 Instance Profile: $EC2_INSTANCE_PROFILE_NAME and associating role..."
aws iam create-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" --region "$REGION"
aws iam add-role-to-instance-profile --instance-profile-name "$EC2_INSTANCE_PROFILE_NAME" --role-name "$S3_WRITE_ROLE_NAME" --region "$REGION"

echo "Waiting for IAM changes to propagate (approx. 10 seconds)..."
sleep 10

# Create private S3 bucket
echo "Creating private S3 bucket: $S3_BUCKET_NAME..."
if [[ -z "$S3_BUCKET_NAME" ]]; then
    echo "[✗] ERROR: S3_BUCKET_NAME must be configured. Terminating."
    exit 1
fi
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" 2>/dev/null; then
    echo "Bucket '$S3_BUCKET_NAME' already exists. Skipping creation."
else
    aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION"
    aws s3api put-public-access-block --bucket "$S3_BUCKET_NAME" --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" --region "$REGION"
    echo "S3 bucket '$S3_BUCKET_NAME' created and public access blocked."
fi

# Add S3 lifecycle rule
echo "Adding S3 lifecycle rule to delete logs after $LOG_RETENTION_DAYS days..."
aws s3api put-bucket-lifecycle-configuration --bucket "$S3_BUCKET_NAME" --lifecycle-configuration '{
    "Rules": [{ "ID": "DeleteOldLogs", "Filter": { "Prefix": "" }, "Status": "Enabled", "Expiration": { "Days": '$LOG_RETENTION_DAYS' } }]
}' --region "$REGION"
echo "S3 lifecycle rule applied to bucket '$S3_BUCKET_NAME'."

# Prepare User Data Script
echo "Preparing user_data_script.sh for EC2 instance..."
cp user_data_script.sh temp_user_data_script.sh
sed -i "s|YOUR_S3_BUCKET_NAME|$S3_BUCKET_NAME|g" temp_user_data_script.sh
sed -i "s|YOUR_REPO_URL|$REPO_URL|g" temp_user_data_script.sh
sed -i "s|YOUR_AWS_REGION|$REGION|g" temp_user_data_script.sh
sed -i "s|YOUR_APP_NAME|$APP_NAME|g" temp_user_data_script.sh
sed -i "s|YOUR_APP_PORT|$APP_PORT|g" temp_user_data_script.sh
sed -i "s|YOUR_STAGE|$STAGE|g" temp_user_data_script.sh

# Launch EC2 Instance
echo "Launching EC2 instance with instance profile and user data..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-groups "$SECURITY_GROUP" \
  --iam-instance-profile Name="$EC2_INSTANCE_PROFILE_NAME" \
  --user-data file://temp_user_data_script.sh \
  --query "Instances[0].InstanceId" \
  --output text)
echo "Instance ID: $INSTANCE_ID"
rm temp_user_data_script.sh

echo "Waiting for instance to be ready and status checks to pass..."
aws ec2 wait instance-status-ok --region "$REGION" --instance-ids "$INSTANCE_ID"

sleep 20 # Give AWS a buffer time to assign a public IP
PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
    sleep 20
    PUBLIC_IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE_ID" --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
fi

if [[ -z "$PUBLIC_IP" || "$PUBLIC_IP" == "None" ]]; then
    echo "[✗] Still failed to fetch Public IP. Exiting."
    exit 1
fi
echo "App deployment initiated via user-data. App accessible at: http://$PUBLIC_IP"

# Test if app is reachable
echo "Testing if app is reachable via http://$PUBLIC_IP:$APP_PORT..."
sleep 30 # Give some time for the server to start
if curl --fail --silent --show-error "http://$PUBLIC_IP:$APP_PORT"; then
    echo "[✓] Application is reachable!"
else
    echo "[✗] Application is NOT reachable on port $APP_PORT."
fi

# Schedule instance to stop
echo "EC2 instance will automatically stop after $STOP_AFTER minutes for log archival."
(sleep "$(($STOP_AFTER * 60))" && aws ec2 stop-instances --region "$REGION" --instance-ids "$INSTANCE_ID") &

# Use Read-Only role to verify S3 (after instance stops and logs upload)
echo "Waiting for instance to stop and logs to potentially be uploaded (will wait for instance stop time + 2 minutes for upload)..."
sleep "$(($STOP_AFTER * 60 + 120))" # Wait for instance stop time + 2 minutes buffer

echo "Verifying S3 bucket content using Read-Only Role: $S3_READ_ONLY_ROLE_NAME..."
TEMP_CREDS=$(aws sts assume-role --role-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${S3_READ_ONLY_ROLE_NAME}" --role-session-name "S3ReadOnlyVerificationSession" --query "Credentials" --output json --region "$REGION")

if [ -z "$TEMP_CREDS" ]; then
    echo "[✗] Failed to assume S3 Read-Only Role. Check IAM permissions."
    exit 1
fi

AWS_ACCESS_KEY_ID=$(echo "$TEMP_CREDS" | jq -r .AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(echo "$TEMP_CREDS" | jq -r .SecretAccessKey)
AWS_SESSION_TOKEN=$(echo "$TEMP_CREDS" | jq -r .SessionToken)

echo "Attempting to list contents of s3://$S3_BUCKET_NAME/ using read-only role:"
if AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN" aws s3 ls "s3://$S3_BUCKET_NAME/" --recursive --region "$REGION"; then
    echo "[✓] Successfully listed S3 bucket contents with Read-Only Role."
else
    echo "[✗] Failed to list S3 bucket contents with Read-Only Role. Check permissions or bucket state."
fi

echo "Attempting to upload a test file with Read-Only Role (this should FAIL as expected):"
if AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN" echo "test content" | aws s3 cp - "s3://$S3_BUCKET_NAME/test_readonly_fail.txt" --region "$REGION" 2>&1; then
    echo "[✗] ERROR: Upload unexpectedly succeeded with Read-Only Role. Policy is too permissive."
else
    echo "[✓] Upload failed as expected with Read-Only Role. Policy is correctly restrictive."
fi

echo "--- EC2 Deployment Automation (Extended - Stage: $STAGE) Finished ---"
echo ""
echo "--- IMPORTANT: AWS Resource Cleanup Commands (Run these manually!) ---"
echo "INSTANCE_ID=\"$INSTANCE_ID\""
echo "S3_BUCKET_NAME=\"$S3_BUCKET_NAME\""
echo "AWS_ACCOUNT_ID=\"$AWS_ACCOUNT_ID\""
echo "S3_WRITE_ROLE_NAME=\"$S3_WRITE_ROLE_NAME\""
echo "S3_READ_ONLY_ROLE_NAME=\"$S3_READ_ONLY_ROLE_NAME\""
echo "EC2_INSTANCE_PROFILE_NAME=\"$EC2_INSTANCE_PROFILE_NAME\""
echo "REGION=\"$REGION\""
echo ""
echo "aws ec2 terminate-instances --instance-ids \$INSTANCE_ID --region \$REGION"
echo "aws ec2 wait instance-terminated --instance-ids \$INSTANCE_ID --region \$REGION"
echo "aws s3 rm \"s3://\$S3_BUCKET_NAME/\" --recursive --region \$REGION"
echo "aws s3api delete-bucket --bucket \"\$S3_BUCKET_NAME\" --region \$REGION"
echo "aws iam detach-role-policy --role-name \"\$S3_WRITE_ROLE_NAME\" --policy-arn \"arn:aws:iam::\${AWS_ACCOUNT_ID}:policy/\${S3_WRITE_ROLE_NAME}Policy\" --region \$REGION"
echo "aws iam delete-policy --policy-arn \"arn:aws:iam::\${AWS_ACCOUNT_ID}:policy/\${S3_WRITE_ROLE_NAME}Policy\" --region \$REGION"
echo "aws iam detach-role-policy --role-name \"\$S3_READ_ONLY_ROLE_NAME\" --policy-arn \"arn:aws:iam::\${AWS_ACCOUNT_ID}:policy/\${S3_READ_ONLY_ROLE_NAME}Policy\" --region \$REGION"
echo "aws iam delete-policy --policy-arn \"arn:aws:iam::\${AWS_ACCOUNT_ID}:policy/\${S3_READ_ONLY_ROLE_NAME}Policy\" --region \$REGION"
echo "aws iam remove-role-from-instance-profile --instance-profile-name \"\$EC2_INSTANCE_PROFILE_NAME\" --role-name \"\$S3_WRITE_ROLE_NAME\" --region \$REGION"
echo "aws iam delete-instance-profile --instance-profile-name \"\$EC2_INSTANCE_PROFILE_NAME\" --region \$REGION"
echo "aws iam delete-role --role-name \"\$S3_WRITE_ROLE_NAME\" --region \$REGION"
echo "aws iam delete-role --role-name \"\$S3_READ_ONLY_ROLE_NAME\" --region \$REGION"
