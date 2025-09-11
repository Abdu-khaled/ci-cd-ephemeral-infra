# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnet in AZ a
data "aws_subnet" "default_a" {
  availability_zone = "eu-central-1a"
  default_for_az    = true

  tags = {
    Name = "public-subnet"
    Tier = "public"
  }
}

# Create security_group
resource "aws_security_group" "ci_ssh" {
  name        = "ci-ssh-sg"
  description = "Allow SSH and HTTP"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# EC2 Instance
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

resource "aws_instance" "ci_ephemeral" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnet.default_a.id
  vpc_security_group_ids = [aws_security_group.ci_ssh.id]
  key_name               = var.ssh_key_name

  tags = {
    Name = "ci_ephemeral"
    lifespan= "ephemeral"
    owner= var.ci_owner
  }
}