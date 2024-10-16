#!/bin/bash
set -e

APPLICATION_NAME="$1"
MONGODB_URI="$2"
APPLICATION_PORT="$3"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-'${S3_BUCKET_NAME}'}"

cd /home/ec2-user

sudo -u ec2-user pm2 stop "$APPLICATION_NAME" || true
sudo -u ec2-user pm2 delete "$APPLICATION_NAME" || true
rm -rf "$APPLICATION_NAME"

mkdir "$APPLICATION_NAME"
cd "$APPLICATION_NAME"

aws s3 cp "s3://${S3_BUCKET_NAME}/${APPLICATION_NAME}/${APPLICATION_NAME}.zip" .
unzip -o "${APPLICATION_NAME}.zip"

chown -R ec2-user:ec2-user "/home/ec2-user/${APPLICATION_NAME}"

sudo -u ec2-user bash -c "printf 'MONGODB_URI=%s\n' '$MONGODB_URI' > .env.dev"

wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -O /home/ec2-user/rds-combined-ca-bundle.pem
chown ec2-user:ec2-user /home/ec2-user/rds-combined-ca-bundle.pem

sudo -u ec2-user NODE_EXTRA_CA_CERTS=/home/ec2-user/rds-combined-ca-bundle.pem pm2 start dist/src/main.js \
  --name "$APPLICATION_NAME" \
  --cwd "/home/ec2-user/${APPLICATION_NAME}" \
  -- --port="$APPLICATION_PORT"
