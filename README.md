# Ephemeral CI/CD with Jenkins, Terraform, Ansible & Docker

## Preparation for the CI/CD Project
Before running the pipelines, we need to set up infrastructure and tools for Jenkins.

---

### 1. Terraform Remote Backend Setup

I used Amazon S3 to store the Terraform state and DynamoDB for state locking to avoid race conditions when multiple pipelines run.


**Shell Script setup [`backend.sh`](infra-bootstrap/backend.sh)**
```bash
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
```

**Run:**

```bash
chmod +x backend.sh
./backend.sh
```

**Terraform Backend Block in [`backend.tf`](terraform/backend.tf)**

```bash
terraform {
  backend "s3" {
    bucket         	   = "cicd-tfstate-infra"
    key                = "cicd/terraform.tfstate"
    region         	   = "eu-central-1"
    dynamodb_table     = "tf-locks"
    encrypt        	   = true
  }
}
```

**Verification: AWS console**
1. S3 bucket 
![](./images-sc/01.png)

2. DynamoDB table
![](./images-sc/02.png)


---

### 2. Jenkins Master in Docker

I run Jenkins Master inside a container.

```bash
docker run -d \
  --name jenkins-master \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  jenkins/jenkins:lts
```

---

### 3. Jenkins Agent Setup (Custom Dockerfile)

I built a Jenkins agent container image that has all required tools: Terraform, Ansible, AWS CLI, Docker CLI, OpenJDK 17.

**[`Dockerfile.agent`](Dockerfile.agent)**
```bash
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies: ssh server, docker cli, terraform, ansible, awscli
RUN apt-get update && apt-get install -y \
    openjdk-17-jdk \
    openssh-server \
    sudo \
    curl \
    unzip \
    python3 \
    python3-pip \
    docker.io \
    ansible \
    awscli \
    && rm -rf /var/lib/apt/lists/*


# Install Terraform
ARG TF_VERSION=1.6.6
RUN curl -fsSL https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip -o terraform.zip && \
    unzip terraform.zip && mv terraform /usr/local/bin/ && rm terraform.zip

# Create Jenkins user
RUN useradd -m -d /home/jenkins -s /bin/bash jenkins && \
    echo "jenkins ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/jenkins/.ssh && chmod 700 /home/jenkins/.ssh

# Copy public key into image
COPY jenkins_agent.pub /home/jenkins/.ssh/authorized_keys

RUN chmod 700 /home/jenkins/.ssh && \
    chmod 600 /home/jenkins/.ssh/authorized_keys && \
    chown -R jenkins:jenkins /home/jenkins/.ssh


# Configure SSH
RUN mkdir /var/run/sshd
EXPOSE 22

# Run SSH server
CMD ["/usr/sbin/sshd", "-D"]
```

**Build and Run Agent**

```bash
docker build -t jenkins-agent:devops -f Dockerfile.agent .  
docker run -d --name jenkins-agent \ 
  -v /var/run/docker.sock:/var/run/docker.sock \ 
  -v ~/.ssh/jenkins_agent.pub:/home/jenkins/.ssh/authorized_keys:ro \
  jenkins-agent:devops 
```
**Verification**
![](./images-sc/03.png)

![](./images-sc/04.png)

---