#!/bin/bash
set -ex 

export HOME=/home/ubuntu
APPLICATION_NAME="$1"
APPLICATION_PORT="$2"
S3_BUCKET_NAME="$3"
MYSQL_DB_HOST="$4"
MYSQL_DB_PORT="$5"
MYSQL_DB_USER="$6"
MYSQL_DB_PASSWORD="$7"

PROCESS_NAME="${APPLICATION_NAME}-${APPLICATION_PORT}"

exec > >(tee -a /var/log/deploy_script.log) 2>&1

echo "Starting deployment script for $APPLICATION_NAME..."

cd /home/ubuntu

if pm2 describe "$PROCESS_NAME" > /dev/null; then
  echo "Stopping and deleting existing PM2 process: $PROCESS_NAME"
  sudo -u ubuntu pm2 stop "$PROCESS_NAME"
  sudo -u ubuntu pm2 delete "$PROCESS_NAME"
else
  echo "No existing PM2 process named $PROCESS_NAME found, skipping stop/delete"
fi

echo "Handling application directory: $APPLICATION_NAME"
if [ -d "$APPLICATION_NAME" ]; then
  echo "Directory $APPLICATION_NAME already exists. Removing it."
  rm -rf "$APPLICATION_NAME"
fi
mkdir "$APPLICATION_NAME"
cd "$APPLICATION_NAME"
echo "Application directory $APPLICATION_NAME is ready."

echo "Downloading application package from S3 bucket: $S3_BUCKET_NAME"
if ! aws s3 cp "s3://${S3_BUCKET_NAME}/${APPLICATION_NAME}/${APPLICATION_NAME}.zip" .; then
  echo "Failed to download application package from S3"
  exit 1
fi
echo "Application package downloaded successfully."

echo "Unzipping application package..."
if ! unzip -o "${APPLICATION_NAME}.zip"; then
  echo "Failed to unzip application package"
  exit 1
fi
echo "Application package unzipped successfully."

chown -R ubuntu:ubuntu "/home/ubuntu/${APPLICATION_NAME}"

echo "Setting MySQL RDS connection details in .env.dev"
sudo -u ubuntu bash -c "printf 'DATABASE_HOST=%s\nDATABASE_PORT=%s\nDATABASE_USER=%s\nDATABASE_PASSWORD=%s\n' \
'$MYSQL_DB_HOST' '$MYSQL_DB_PORT' '$MYSQL_DB_USER' '$MYSQL_DB_PASSWORD' > .env.dev" || exit 1

if [[ ! -f "dist/main.js" ]]; then
  echo "Error: dist/main.js not found"
  exit 1
fi

echo "Starting application using PM2"
if ! sudo -u ubuntu pm2 start dist/main.js \
  --name "$PROCESS_NAME" \
  --cwd "/home/ubuntu/${APPLICATION_NAME}" \
  -- --port="$APPLICATION_PORT"; then
  echo "Failed to start application using PM2"
  exit 1
fi

echo "Deployment completed successfully!"
