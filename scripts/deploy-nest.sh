#!/bin/bash
set -Eeuo pipefail

export AWS_PAGER=""
umask 027
trap 'rc=$?; echo "[deploy] finished with exit code $rc"; exit $rc' EXIT

export HOME=/home/ubuntu
APPLICATION_NAME="$1"
APPLICATION_PORT="$2"
S3_BUCKET_NAME="$3"
SECRET_NAME="$4"

PROCESS_NAME="${APPLICATION_NAME}-${APPLICATION_PORT}"


if [[ -z "${NO_TEE:-}" ]]; then
  exec > >(tee -a /home/ubuntu/deploy_script.log) 2>&1
else
  exec >> /home/ubuntu/deploy_script.log 2>&1
fi

echo "Starting deployment script for $APPLICATION_NAME..."
cd /home/ubuntu

if sudo -u ubuntu pm2 describe "$PROCESS_NAME" >/dev/null 2>&1; then
  echo "Stopping and deleting existing PM2 process: $PROCESS_NAME"
  sudo -u ubuntu pm2 stop "$PROCESS_NAME" || true
  sudo -u ubuntu pm2 delete "$PROCESS_NAME" || true
fi

if [[ -d "$APPLICATION_NAME" ]]; then
  echo "Directory $APPLICATION_NAME already exists. Removing it."
  rm -rf "$APPLICATION_NAME"
fi
mkdir "$APPLICATION_NAME"
cd "$APPLICATION_NAME"

echo "Downloading application package from S3 bucket: $S3_BUCKET_NAME"

if ! aws s3 cp --no-progress --only-show-errors \
  "s3://${S3_BUCKET_NAME}/${APPLICATION_NAME}/${APPLICATION_NAME}.zip" .; then
  echo "Failed to download application package from S3"
  exit 1
fi
echo "Application package downloaded successfully."

echo "Unzipping application package..."
if ! unzip -o "${APPLICATION_NAME}.zip" > /dev/null; then
  echo "Failed to unzip application package"
  exit 1
fi
echo "Application package unzipped successfully."
rm -f "${APPLICATION_NAME}.zip" || true

chown -R ubuntu:ubuntu "/home/ubuntu/${APPLICATION_NAME}"

echo "Fetching secrets from AWS Secrets Manager"
set +x
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --query SecretString \
  --output text \
  | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > .env
set -x

chmod 600 .env
chown ubuntu:ubuntu .env

if [[ ! -f "package.json" ]]; then
  echo "ERROR: package.json not found. Cannot use npm start."
  exit 2
fi
echo "Found package.json - will use npm start"

sudo -u ubuntu bash -lc 'pm2 ping >/dev/null 2>&1 || true; pm2 startup systemd -u ubuntu --hp /home/ubuntu >/dev/null 2>&1 || true'

echo "Starting application via PM2 (npm start) with APPLICATION_PORT=$APPLICATION_PORT"
sudo -u ubuntu bash -lc \
  "export PORT=$APPLICATION_PORT APPLICATION_PORT=$APPLICATION_PORT NODE_ENV=production; \
   pm2 delete '$PROCESS_NAME' >/dev/null 2>&1 || true; \
   pm2 start npm --name '$PROCESS_NAME' --cwd '/home/ubuntu/${APPLICATION_NAME}' -- start --update-env; \
   pm2 save"


echo "Deployment completed successfully!"
