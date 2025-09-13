# CI/CD Practical Task — Jenkins + Terraform + Ansible + Docker + Daily Cleanup

## Scenario

- **Pipeline 1 (Provision & Configure):** Webhook-triggered. Creates an ephemeral EC2 with Terraform (remote backend), then configures it with Ansible to install Docker.
- **Pipeline 2 (Build, Push & Deploy):** Auto-triggered after Pipeline 1. Builds an Nginx image, pushes it to private Docker Hub, then SSH-deploys to the EC2 IP.
- **Pipeline 3 (Daily Cleanup):** Scheduled. Terminates all EC2 instances tagged as ephemeral at **12:00 AM Africa/Cairo** every day.
