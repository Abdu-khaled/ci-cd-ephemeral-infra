variable "aws_region" {
  default = "eu-central-1"
}


variable "instance_type" {
  default = "t3.micro"
}


variable "ssh_key_name" {
  description = "Name of the EC2 KeyPair for provisioning (must exist in AWS)"
  type = string
}

variable "ci_owner" {
  default = "jenkins"
}