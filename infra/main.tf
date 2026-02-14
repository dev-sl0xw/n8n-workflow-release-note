terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- SSH Key Pair ---

resource "tls_private_key" "n8n_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "n8n_key" {
  key_name   = var.key_pair_name
  public_key = tls_private_key.n8n_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.n8n_key.private_key_pem
  filename        = "${path.module}/${var.key_pair_name}.pem"
  file_permission = "0400"
}

# --- Data Sources ---

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# --- Security Group ---

resource "aws_security_group" "n8n_sg" {
  name        = "n8n-sg"
  description = "n8n server - SSH and web UI access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  ingress {
    description = "n8n Web UI"
    from_port   = var.n8n_port
    to_port     = var.n8n_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "n8n-sg"
  }
}

# --- EC2 Instance ---

resource "aws_instance" "n8n_server" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.n8n_key.key_name
  vpc_security_group_ids = [aws_security_group.n8n_sg.id]

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/scripts/user-data.sh", {
    env_content = templatefile("${path.module}/templates/.env.tpl", {
      n8n_host = "0.0.0.0"
      n8n_port = var.n8n_port
      timezone = var.n8n_timezone
    })
    compose_content = templatefile("${path.module}/templates/docker-compose.yml.tpl", {
      n8n_port = var.n8n_port
    })
  })

  tags = {
    Name = "n8n-server"
  }
}

# --- Elastic IP ---

resource "aws_eip" "n8n_eip" {
  instance = aws_instance.n8n_server.id

  tags = {
    Name = "n8n-eip"
  }
}
