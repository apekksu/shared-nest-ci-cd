#!/bin/bash
set -e

APPLICATION_NAME="$1"
MONGODB_URI="$2"
APPLICATION_PORT="$3"
S3_BUCKET_NAME="$4"
MONGODB_TYPE="$5"
DOCKER_MONGO_PORT="$6"

cd /home/ubuntu

sudo -u ubuntu pm2 stop "$APPLICATION_NAME" || echo "Failed to stop $APPLICATION_NAME, it may not be running"
sudo -u ubuntu pm2 delete "$APPLICATION_NAME" || echo "Failed to delete $APPLICATION_NAME, it may not be running"

rm -rf "$APPLICATION_NAME"

mkdir "$APPLICATION_NAME"
cd "$APPLICATION_NAME"

echo "Downloading application package from S3"
aws s3 cp "s3://${S3_BUCKET_NAME}/${APPLICATION_NAME}/${APPLICATION_NAME}.zip" . || exit 1

echo "Unzipping application package"
unzip -o "${APPLICATION_NAME}.zip" || exit 1

chown -R ubuntu:ubuntu "/home/ubuntu/${APPLICATION_NAME}"

echo "Updating port in main.ts to $APPLICATION_PORT"
sed -i "s/await app.listen(3000);/await app.listen($APPLICATION_PORT);/" dist/src/main.js || { echo "Failed to update port in main.js"; exit 1; }

if [ "$MONGODB_TYPE" = "docker" ]; then
  echo "Setting up Docker MongoDB on port $DOCKER_MONGO_PORT"

  docker container stop mongodb-${APPLICATION_NAME} || echo "No container to stop"
  docker container rm mongodb-${APPLICATION_NAME} || echo "No container to remove"

  docker run -d --name mongodb-${APPLICATION_NAME} --restart always -p "$DOCKER_MONGO_PORT":27017 mongo:latest || exit 1

  sudo -u ubuntu bash -c "printf 'MONGODB_URI=mongodb://localhost:%s/mydatabase\n' '$DOCKER_MONGO_PORT' > .env.dev" || exit 1
else
  echo "Setting MongoDB URI in .env.dev for cluster"
  sudo -u ubuntu bash -c "printf 'MONGODB_URI=%s\n' '$MONGODB_URI' > .env.dev" || exit 1

  echo "Downloading RDS CA bundle"
  wget https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -O /home/ubuntu/rds-combined-ca-bundle.pem || { echo "Failed to download CA bundle"; exit 1; }
  chown ubuntu:ubuntu /home/ubuntu/rds-combined-ca-bundle.pem
fi

ls -alh

if [[ ! -f "dist/src/main.js" ]]; then
  echo "Error: dist/src/main.js not found"
  exit 1
fi

echo "Starting application using PM2"
sudo -u ubuntu NODE_EXTRA_CA_CERTS=/home/ubuntu/rds-combined-ca-bundle.pem pm2 start dist/src/main.js \
  --name "$APPLICATION_NAME" \
  --cwd "/home/ubuntu/${APPLICATION_NAME}" \
  -- --port="$APPLICATION_PORT" || exit 1
