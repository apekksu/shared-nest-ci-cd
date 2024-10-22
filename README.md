### `Shared NestJS CI/CD pipeline`
This repository provides a shared CI/CD pipeline for deploying NestJS applications to an EC2 instance, either using a dockerized MongoDB instance or a RDS MongoDB cluster.

Table of Contents

Getting Started
To use the shared CI/CD pipeline, follow these steps:

Create or clone your NestJS application repository.
Set up the correct directory structure:
    **.github/workflows/deploy.yml** with referance to this shared pipeline as shown in the example
    source files located in **/src** (**main.ts**, app-module etc.)
Commit and push to the branch mentioned in your yaml for automatic deployment.

```yaml
name: Deploy NestJS App

on:
  push:
    branches:
      - main # choose any other  branch name if needed like dev/*

jobs:
  deploy:
    uses: apekksu/shared-nest-ci-cd/.github/workflows/ci.yml@main
    with:
      s3-bucket-name: nestjs-app-bucket-test
      application-name: ${{ github.event.repository.name }}
      application-port: 3018 # for convenience use similar port to docker port like 27018 for 3018 etc.
      aws-region: us-west-2
      mongodb-type: docker # or cluster if you want to use RDS DynamoDB cluster instance
      docker-mongo-port: 27018 # comment this if you're using cluster

    secrets:
      aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
      aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
      # MONGODB_URI: ${{ secrets.MONGODB_URI }} # enable this when choosing cluster option
```

### `Using organizaion level secrets`
**AWS_ACCESS_KEY_ID**: The AWS access key ID.
**AWS_SECRET_ACCESS_KEY**: The AWS secret access key.

Secrets above are required for the pipeline to authenticate with AWS and are set on organization level secrets. Ask Tigran/Aram to check if there are issues with credentials.


### `Shared pipeline performs the following tasks:`

The pipeline checks out your repository, installs dependencies, and builds the application.
The built application is zipped and uploaded to an S3 bucket.
The pipeline retrieves the shared EC2 instance information and deploys the application using AWS SSM.
The pipeline configures MongoDB based on your chosen deployment type (Docker or cluster).


### `MongoDB configuration`
**For Cluster MongoDB**
Ensure that **MONGODB_URI** is added to your repository secrets.
Set mongodb-type to **cluster** in your workflow file.

**For Docker MongoDB**
Set mongodb-type to docker in your workflow file.
Specify a different port for each app (e.g., 27018 for the second app, 27019 for the third). Choose similar port to expose the application from range 3000-3030.
e.g. **27018** and **3018**
The pipeline will automatically spin up a Dockerized MongoDB container for the application on the specified port.

### `Example Repo`
[Authentication Module](https://github.com/apekksu/authentication-module).

The EC2 instance used for deployment is automatically configured to start PM2-managed processes on boot, ensuring that the application runs automatically after ec2 instance restart.
Use different application ports for multiple applications deployed on the same EC2 instance to avoid port conflicts.
