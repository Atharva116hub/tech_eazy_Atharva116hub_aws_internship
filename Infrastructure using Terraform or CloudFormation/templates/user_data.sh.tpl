#!/bin/bash
set -euxo pipefail

S3_BUCKET_NAME="${s3_bucket_name}"
REPO_URL="${repo_url}"
REGION="${region}"
APP_NAME="${app_name}"
APP_PORT="${app_port}"
STAGE="${stage}"
STOP_AFTER_MINUTES="${stop_after_minutes}"

APP_ENV="${app_env}"
DB_HOST="${db_host}"
API_KEY="${api_key}"

yum update -y
yum install -y git java-19-amazon-corretto-devel python3 awscli

sudo alternatives --set java /usr/lib/jvm/java-19-amazon-corretto/bin/java
sudo alternatives --set javac /usr/lib/jvm/java-19-amazon-corretto/bin/javac
java -version

mkdir -p "/home/ec2-user/${APP_NAME}/logs"
chown -R ec2-user:ec2-user "/home/ec2-user/${APP_NAME}"

git clone "${REPO_URL}" "/home/ec2-user/${APP_NAME}"
cd "/home/ec2-user/${APP_NAME}"

echo "export APP_ENV=\"${APP_ENV}\"" >> /etc/profile.d/app_env.sh
echo "export DB_HOST=\"${DB_HOST}\"" >> /etc/profile.d/app_env.sh
echo "export API_KEY=\"${API_KEY}\"" >> /etc/profile.d/app_env.sh
chmod +x /etc/profile.d/app_env.sh

source /etc/profile.d/app_env.sh
env | grep "APP_ENV\|DB_HOST\|API_KEY" || true

sudo nohup python3 -m http.server "${APP_PORT}" &> "/var/log/${APP_NAME}_app.log" &

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

if [ "${STOP_AFTER_MINUTES}" -gt 0 ]; then
  echo "sudo shutdown -h +${STOP_AFTER_MINUTES}" | at now + ${STOP_AFTER_MINUTES} minutes
fi

cat << 'EOF_SHUTDOWN' > /etc/rc.d/init.d/upload_logs_on_shutdown.sh
#!/bin/bash
set -e
set -u
set -o pipefail

S3_BUCKET_NAME_SHUTDOWN="${s3_bucket_name}"
INSTANCE_ID_SHUTDOWN=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION_SHUTDOWN="${region}"
APP_NAME_SHUTDOWN="${app_name}"

LOG_UPLOAD_TEMP_DIR="/tmp/ec2_shutdown_logs"

echo "$(date): Shutdown script started for instance $INSTANCE_ID_SHUTDOWN." >> /var/log/cloud-init-output.log
mkdir -p "$LOG_UPLOAD_TEMP_DIR" || { echo "Failed to create temp log dir." >> /var/log/cloud-init-output.log; exit 1; }

if [ -f "/var/log/cloud-init.log" ]; then
    cp /var/log/cloud-init.log "$LOG_UPLOAD_TEMP_DIR/cloud-init.log"
fi
if [ -f "/var/log/cloud-init-output.log" ]; then
    cp /var/log/cloud-init-output.log "$LOG_UPLOAD_TEMP_DIR/cloud-init-output.log"
fi

APP_LOG_PATH="/var/log/${APP_NAME_SHUTDOWN}_app.log"
if [ -f "$APP_LOG_PATH" ]; then
    cp "$APP_LOG_PATH" "$LOG_UPLOAD_TEMP_DIR/app.log"
fi

TARBALL_NAME="ec2-instance-logs-${INSTANCE_ID_SHUTDOWN}-$(date +%Y%m%d%H%M%S).tar.gz"
tar -czf "$LOG_UPLOAD_TEMP_DIR/$TARBALL_NAME" -C "$LOG_UPLOAD_TEMP_DIR" .

/usr/bin/aws s3 cp "$LOG_UPLOAD_TEMP_DIR/$TARBALL_NAME" "s3://${S3_BUCKET_NAME_SHUTDOWN}/instance-logs/" --region "${REGION_SHUTDOWN}"

if [ -f "$LOG_UPLOAD_TEMP_DIR/app.log" ]; then
    /usr/bin/aws s3 cp "$LOG_UPLOAD_TEMP_DIR/app.log" "s3://${S3_BUCKET_NAME_SHUTDOWN}/app-logs/$INSTANCE_ID_SHUTDOWN/app.log" --region "${REGION_SHUTDOWN}"
fi

rm -rf "$LOG_UPLOAD_TEMP_DIR"
echo "$(date): Shutdown script finished." >> /var/log/cloud-init-output.log

exit 0
EOF_SHUTDOWN

chmod +x /etc/rc.d/init.d/upload_logs_on_shutdown.sh

ln -s /etc/rc.d/init.d/upload_logs_on_shutdown.sh /etc/rc0.d/K99upload_logs_on_shutdown.sh
ln -s /etc/rc.d/init.d/upload_logs_on_shutdown.sh /etc/rc6.d/K99upload_logs_on_shutdown.sh
