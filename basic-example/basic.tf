terraform {
  ## Assumes s3 bucket and dynamo DB table already set up
  ## See /code/03-basics/aws-backend
  backend "s3" {
    bucket         = "terraformstate-bucket-aminundakun" # REPLACE WITH YOUR BUCKET NAME
    key            = "terraform-state-file/project/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}
# Create a VPC
resource "aws_vpc" "prod-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "prod-vpc"
  }
}

resource "aws_subnet" "public-SN" {
  vpc_id     = aws_vpc.prod-vpc.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "public-SN"
  }
}

resource "aws_internet_gateway" "internet-gw" {
  vpc_id = aws_vpc.prod-vpc.id

  tags = {
    Name = "internet-gw"
  }
}

resource "aws_route_table" "public-RT" {
  vpc_id = aws_vpc.prod-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet-gw.id
  }

  tags = {
    Name = "public-RT"
  }
}

resource "aws_route_table_association" "RT-association" {
  subnet_id      = aws_subnet.public-SN.id
  route_table_id = aws_route_table.public-RT.id
}

#data "aws_key_pair" "ssh_key" {
#  key_name           = "amzonLinux2Key"
#  include_public_key = true
#}

resource "aws_instance" "web_server" {
  ami             = "ami-0430580de6244e02e"
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.public-SN.id
  associate_public_ip_address = true
  key_name        = "amzonLinux2Key"
  security_groups = [aws_security_group.web-server-SG.id]
  user_data = <<-EOF
                 #!/bin/bash
                 sudo apt update -y
                 sudo apt install apache2 -y
                 sudo systemctl start apache2
                 sudo bash -c 'echo "<h1>Terrfaform Website</h1> $(hostname -f)" > /var/www/html/index.html'
                 EOF

  tags = {
    Name = "terraform-web-server"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web-server-SG" {
  name        = "web-server-SG"
  description = "Allow inbound traffic to webserver"
  vpc_id      = aws_vpc.prod-vpc.id

  ingress {
    description = "http from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-server-SG"
  }
}