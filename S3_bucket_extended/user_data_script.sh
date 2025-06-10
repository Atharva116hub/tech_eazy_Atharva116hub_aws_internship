#!/bin/bash
set -euxo pipefail

S3_BUCKET_NAME="YOUR_S3_BUCKET_NAME"
REPO_URL="YOUR_REPO_URL"
REGION="YOUR_AWS_REGION"
APP_NAME="YOUR_APP_NAME"
APP_PORT="YOUR_APP_PORT"
STAGE="YOUR_STAGE"

yum update -y
yum install -y git java-19-amazon-corretto-devel python3 awscli

sudo alternatives --set java /usr/lib/jvm/java-19-amazon-corretto/bin/java
sudo alternatives --set javac /usr/lib/jvm/java-19-amazon-corretto/bin/javac

mkdir -p "/home/ec2-user/$APP_NAME/logs"
chown -R ec2-user:ec2-user "/home/ec2-user/$APP_NAME"

git clone "$REPO_URL" "/home/ec2-user/$APP_NAME"
cd "/home/ec2-user/$APP_NAME"

cat << EOF > "./src/config.js"
const config = {
    stage: "$STAGE",
    message: "Welcome to the $STAGE environment!",
};
EOF

sudo nohup python3 -m http.server "$APP_PORT" &> "/var/log/${APP_NAME}_app.log" &

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# This part is crucial for the STOP_AFTER from ec2-deploy.sh to be effective
# The actual shutdown is handled by the main script triggering an EC2 stop
# which then runs the below shutdown script.
# No direct `shutdown` command needed here in user-data, as the main script handles stopping.

cat << 'EOF_SHUTDOWN' > /etc/rc.d/init.d/upload_logs_on_shutdown.sh
#!/bin/bash
set -e
set -u
set -o pipefail

S3_BUCKET_NAME_SHUTDOWN="YOUR_S3_BUCKET_NAME"
INSTANCE_ID_SHUTDOWN=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION_SHUTDOWN="YOUR_AWS_REGION"
APP_NAME_SHUTDOWN="YOUR_APP_NAME"

LOG_UPLOAD_TEMP_DIR="/tmp/ec2_shutdown_logs"

echo "$(date): Shutdown script started." >> /var/log/cloud-init-output.log
mkdir -p "$LOG_UPLOAD_TEMP_DIR"

if [ -f "/var/log/cloud-init.log" ]; then cp /var/log/cloud-init.log "$LOG_UPLOAD_TEMP_DIR/cloud-init.log"; fi
if [ -f "/var/log/cloud-init-output.log" ]; then cp /var/log/cloud-init-output.log "$LOG_UPLOAD_TEMP_DIR/cloud-init-output.log"; fi

APP_LOG_PATH="/var/log/${APP_NAME_SHUTDOWN}_app.log"
if [ -f "$APP_LOG_PATH" ]; then cp "$APP_LOG_PATH" "$LOG_UPLOAD_TEMP_DIR/app.log"; fi

TARBALL_NAME="ec2-instance-logs-${INSTANCE_ID_SHUTDOWN}-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "$LOG_UPLOAD_TEMP_DIR/$TARBALL_NAME" -C "$LOG_UPLOAD_TEMP_DIR" .

/usr/bin/aws s3 cp "$LOG_UPLOAD_TEMP_DIR/$TARBALL_NAME" "s3://${S3_BUCKET_NAME_SHUTDOWN}/instance-logs/" --region "${REGION_SHUTDOWN}"

if [ -f "$LOG_UPLOAD_TEMP_DIR/app.log" ]; then
    /usr/bin/aws s3 cp "$LOG_UPLOAD_TEMP_DIR/app.log" "s3://${S3_BUCKET_NAME_SHUTDOWN}/app-logs/$INSTANCE_ID_SHUTDOWN/app.log" --region "${REGION_SHUTDOWN}"
fi

rm -rf "$LOG_UPLOAD_TEMP_DIR"
EOF_SHUTDOWN

chmod +x /etc/rc.d/init.d/upload_logs_on_shutdown.sh
ln -s /etc/rc.d/init.d/upload_logs_on_shutdown.sh /etc/rc0.d/K99upload_logs_on_shutdown.sh
ln -s /etc/rc.d/init.d/upload_logs_on_shutdown.sh /etc/rc6.d/K99upload_logs_on_shutdown.sh
