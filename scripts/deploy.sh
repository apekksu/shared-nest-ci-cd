#!/bin/bash
set -e

APPLICATION_NAME="$1"
MONGODB_URI="$2"
APPLICATION_PORT="$3"
S3_BUCKET_NAME="$4"

cd /home/ec2-user

sudo -u ec2-user pm2 stop "$APPLICATION_NAME" || echo "Failed to stop $APPLICATION_NAME, it may not be running"
sudo -u ec2-user pm2 delete "$APPLICATION_NAME" || echo "Failed to delete $APPLICATION_NAME, it may not be running"

rm -rf "$APPLICATION_NAME"

mkdir "$APPLICATION_NAME"
cd "$APPLICATION_NAME"

echo "Downloading application package from S3"
aws s3 cp "s3://${S3_BUCKET_NAME}/${APPLICATION_NAME}/${APPLICATION_NAME}.zip" . || exit 1

echo "Unzipping application package"
unzip -o "${APPLICATION_NAME}.zip" || exit 1

chown -R ec2-user:ec2-user "/home/ec2-user/${APPLICATION_NAME}"

echo "Setting MongoDB URI in .env.dev"
sudo -u ec2-user bash -c "printf 'MONGODB_URI=%s\n' '$MONGODB_URI' > .env.dev" || exit 1

echo "Downloading RDS CA bundle"
wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -O /home/ec2-user/rds-combined-ca-bundle.pem || { echo "Failed to download CA bundle"; exit 1; }
chown ec2-user:ec2-user /home/ec2-user/rds-combined-ca-bundle.pem

ls -alh

if [[ ! -f "dist/src/main.js" ]]; then
  echo "Error: dist/src/main.js not found"
  exit 1
fi

echo "Starting application using PM2"
sudo -u ec2-user NODE_EXTRA_CA_CERTS=/home/ec2-user/rds-combined-ca-bundle.pem pm2 start dist/src/main.js \
  --name "$APPLICATION_NAME" \
  --cwd "/home/ec2-user/${APPLICATION_NAME}" \
  -- --port="$APPLICATION_PORT" || exit 1
