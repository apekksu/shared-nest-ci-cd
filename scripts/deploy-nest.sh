#!/bin/bash
# Version 10:33
set -ex 

export HOME=/home/ubuntu
APPLICATION_NAME="$1"
MONGODB_URI="$2"
APPLICATION_PORT="$3"
S3_BUCKET_NAME="$4"
DATABASE_TYPE="$5"
MONGODB_TYPE="$6"
MYSQL_DB_HOST="$7"
MYSQL_DB_PORT="$8"
MYSQL_DB_USER="$9"
MYSQL_DB_PASSWORD="${10}"
DOCKER_MONGO_PORT="${11}"

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

if [ "$DATABASE_TYPE" = "mongo" ]; then
  echo "Updating port in main.js to $APPLICATION_PORT for MongoDB app"
  if ! sed -i "s/await app.listen(3000);/await app.listen($APPLICATION_PORT);/" dist/src/main.js; then
    echo "Failed to update port in main.js"
    exit 1
  fi

  if [ "$MONGODB_TYPE" = "docker" ]; then
    echo "Setting up Docker MongoDB on port $DOCKER_MONGO_PORT"
    docker container stop mongodb-${APPLICATION_NAME} || echo "No container to stop"
    docker container rm mongodb-${APPLICATION_NAME} || echo "No container to remove"

    if ! docker run -d --name mongodb-${APPLICATION_NAME} --restart always -p "$DOCKER_MONGO_PORT":27017 mongo:latest; then
      echo "Failed to start Docker MongoDB"
      exit 1
    fi
    echo "Docker MongoDB started successfully."

    echo "Setting up MongoDB URI in .env.dev"
    sudo -u ubuntu bash -c "printf 'MONGODB_URI=mongodb://localhost:%s/mydatabase\n' '$DOCKER_MONGO_PORT' > .env.dev" || exit 1
  else
    echo "Setting MongoDB URI in .env.dev for cluster"
    sudo -u ubuntu bash -c "printf 'MONGODB_URI=%s\n' '$MONGODB_URI' > .env.dev" || exit 1

    echo "Downloading RDS CA bundle"
    if ! wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -O /home/ubuntu/rds-combined-ca-bundle.pem; then
      echo "Failed to download CA bundle"
      exit 1
    fi
    chown ubuntu:ubuntu /home/ubuntu/rds-combined-ca-bundle.pem
  fi
fi

if [ "$DATABASE_TYPE" = "mysql" ]; then
  echo "Setting MySQL RDS connection details in .env.dev"
  sudo -u ubuntu bash -c "printf 'DATABASE_HOST=%s\nDATABASE_PORT=%s\nDATABASE_USER=%s\nDATABASE_PASSWORD=%s\n' \
  '$MYSQL_DB_HOST' '$MYSQL_DB_PORT' '$MYSQL_DB_USER' '$MYSQL_DB_PASSWORD' > .env.dev" || exit 1
fi

if [[ ! -f "dist/src/main.js" ]]; then
  echo "Error: dist/src/main.js not found"
  exit 1
fi

echo "Starting application using PM2"
if ! sudo -u ubuntu pm2 start dist/src/main.js \
  --name "$PROCESS_NAME" \
  --cwd "/home/ubuntu/${APPLICATION_NAME}" \
  -- --port="$APPLICATION_PORT"; then
  echo "Failed to start application using PM2"
  exit 1
fi

echo "Deployment completed successfully!"
