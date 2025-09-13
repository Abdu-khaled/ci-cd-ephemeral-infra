# CI/CD Ephemeral Infrastructure with Jenkins, Terraform, Ansible, and Docker

## Preparation for the CI/CD Project
Before running the pipelines, we need to set up infrastructure and tools for Jenkins.

---

### 1.1 Terraform Remote Backend Setup

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

### 1.2 Jenkins Master in Docker

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

### 1.3 Jenkins Agent Setup (Custom Dockerfile)

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

### 1.4 Jenkins Credentials Setup

- AWS Credentials
  - ID: aws-creds
  - Type: AWS Access Key & Secret

- SSH Key for EC2
  - ID: ssh-key
  - Type: SSH private key (or PEM file)
  - Username: ubuntu

- DockerHub Credentials
  - ID: dockerhub-creds
  - Type: Username & Token\
  
**Verification**
![](./images-sc/05.png)

---

## 2. Pipelines

- **Pipeline 1 (Provision & Configure):** Webhook-triggered. Creates an ephemeral EC2 with Terraform (remote backend), then configures it with Ansible to install Docker.
- **Pipeline 2 (Build, Push & Deploy):** Auto-triggered after Pipeline 1. Builds an Nginx image, pushes it to private Docker Hub, then SSH-deploys to the EC2 IP.
- **Pipeline 3 (Daily Cleanup):** Scheduled. Terminates all EC2 instances tagged as ephemeral at **12:00 AM Africa/Cairo** every day.

---

### 2.1 Pipeline One: Provision Infrastructure

**Required steps:**
#### **1. Trigger:** Git webhook on push to `main`

- Configure Jenkins Job for Webhook
- Enable GitHub hook trigger for GITScm polling
  ![](./images-sc/06.png)

- Add Webhook in GitHub repository
  ![](./images-sc/07.png)


#### 2. Creates an ephemeral EC2 with [`Terraform`](terraform/) `Check my repo`
  - Create [`main.tf`](terraform/main.tf), [`variables.tf`](terraform/variables.tf), [`outputs.tf`](terraform/outputs.tf), [`provider.tf`](terraform/provider.tf).

#### 3. [`Ansible`](ansible/playbook.yaml): install & enable Docker on the new host `Check playbook file in my repo`.


#### 4. Create: [`Jenkinsfile.provision`](Jenkinsfile.provision)

   - Run Terraform to provision EC2

   - Extract EC2 public IP + save it

   - Run Ansible to configure EC2 (install Docker)

```bash
pipeline {
  agent { label 'agent1' }
  environment {
    TF_DIR = "terraform"
    AWS_CREDENTIALS_ID = "aws-creds"
    SSH_CREDENTIALS_ID = "ssh-key"
  }
  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Terraform Init & Apply') {
      steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
          dir("${TF_DIR}") {
            sh '''
              terraform init -input=false
              terraform apply -var-file="terraform.tfvars" -auto-approve -input=false
            '''
          }
        }
      }
    }


    stage('Wait for EC2 to be ready') {
      steps {
        echo "Waiting 60 seconds for EC2 to initialize..."
        sleep 60
      }
    }


    stage('Get outputs') {
      steps {
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: env.AWS_CREDENTIALS_ID]]) {
          dir("${TF_DIR}") {
            script {
              def ip = sh(script: "terraform output -raw public_ip", returnStdout: true).trim()
              def instanceId = sh(script: "terraform output -raw instance_id", returnStdout: true).trim()

              echo "EC2 IP: ${ip}"
              echo "Instance ID: ${instanceId}"

              // Save for downstream jobs or debugging
              writeFile file: 'ec2_ip.txt', text: ip
              archiveArtifacts artifacts: 'ec2_ip.txt', fingerprint: true

              // Add info to build metadata
              currentBuild.description = "EC2_IP=${ip}"
              env.EC2_IP = ip
            }
          }
        }
      }
    }

    stage('Ansible configure') {
      steps {
          withCredentials([file(credentialsId: env.SSH_CREDENTIALS_ID, variable: 'SSH_KEY_FILE')]) {
          script {
              def ip = readFile("${TF_DIR}/ec2_ip.txt").trim()
              sh """
              # Set proper permissions for the SSH key
              chmod 600 ${SSH_KEY_FILE}
              
              # Create Ansible inventory
              echo "[ephemeral]" > /tmp/inv
              echo "${ip}" >> /tmp/inv

              # Run Ansible playbook
              ANSIBLE_HOST_KEY_CHECKING=False \\
              ansible-playbook -i /tmp/inv ansible/playbook.yaml \\
                  --private-key=${SSH_KEY_FILE} -u ubuntu
              """
          }
          }
      }
    }
}

  post {
    success {
      build job: 'Pipeline-two', parameters: [string(name: 'EC2_IP', value: env.EC2_IP)]
    }
  }
}
```
