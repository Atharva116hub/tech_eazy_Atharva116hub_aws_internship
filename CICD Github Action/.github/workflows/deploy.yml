#!/bin/bash
set -euxo pipefail

sudo yum update -y
sudo yum install -y git python3

git clone https://github.com/Atharva116hub/tech_eazy_Atharva116hub_aws_internship.git
cd tech_eazy_Atharva116hub_aws_internship

nohup python3 main.py &

sleep 5
tar -czvf logs.tar.gz nohup.out
aws s3 cp logs.tar.gz s3://<YOUR_BUCKET_NAME>
