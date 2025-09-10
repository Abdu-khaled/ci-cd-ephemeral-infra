#!/bin/bash

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
AWS_REGION="eu-central-1"
S3_BUCKET="cicd-tfstate-infra"
DDB_TABLE="tf-locks"
# ==============================


echo "Starting Terraform backend bootstrap..."
echo "Region: $AWS_REGION"
echo "S3 Bucket: $S3_BUCKET"
echo "DynamoDB Table: $DDB_TABLE"

echo "------------------------------"

# Check if S3 bucket is already exists
if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
    echo "S3 bucket aleady exists: $S3_BUCKET"
else
    echo "Creating S3 bucket  $S3_BUCKET..."
    aws s3api create-bucket \
      --bucket "$S3_BUCKET" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION"

   echo "Enabling versioning on $S3_BUCKET..."
   aws s3api put-bucket-versioning \
     --bucket "$S3_BUCKET" \
     --versioning-configuration Status=Enabled
   echo "S3 bucket created and versioning enabled."
fi

echo "------------------------------"

# Check if DynamoDB table already exists
if aws dynamodb describe-table --table-name "$DDB_TABLE" 2>/dev/null; then
    echo "Dynamodb is already exists: $DDB_TABLE" 
else
    echo "Creating DynameDB table: $DDB_TABLE..."
    aws dynamodb create-table \
      --table-name "$DDB_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --region $AWS_REGION 
    # echo "Waiting for DynamoDB table to become active..."
    # aws dynamodb wait table-exists --table-name "$DDB_TABLE"
    # echo "DynamoDB table created and ready."
fi

echo "------------------------------"

echo "Backend bootstrap complete! Terraform can now use S3 + DynamoDB for state."


