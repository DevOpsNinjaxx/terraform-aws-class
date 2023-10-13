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
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
}

data "aws_vpc" "default_vpc" {
  default = true
}

data "aws_subnet_ids" "default_subnets" {
  vpc_id = data.aws_vpc.default_vpc.id
}

resource "aws_s3_bucket" "web-app-bucket" {
  bucket = "web-app-bucket-aminundakun"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web-app-bucket-encyption" {
  bucket = aws_s3_bucket.web-app-bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_db_instance" "web-app-db" {
  allocated_storage    = 10
  name                 = "mydb"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "foo"
  password             = "foobarbaz"
  parameter_group_name = "default.mysql5.7"
  skip_final_snapshot  = true
}

resource "aws_security_group" "web-server-SG" {
  name        = "web-server-SG"
  description = "Allow inbound traffic on port 80"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["105.112.126.170/32"]
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

resource "aws_key_pair" "ssh_key" {
  key_name   = "SSH-KEY"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "web_server-1" {
  ami                         = "ami-0430580de6244e02e"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh_key.key_name
  security_groups             = [aws_security_group.web-server-SG.name]
  user_data                   = <<-EOF
                 #!/bin/bash
                 sudo apt update -y
                 sudo apt install apache2 -y
                 sudo systemctl start apache2
                 sudo bash -c 'echo "<h1>Terrfaform Website</h1> from" $(hostname -f) > /var/www/html/index.html'
                 EOF

  tags = {
    Name = "terraform-web-server-1"
  }
  depends_on = [
    aws_key_pair.ssh_key
  ]
}

resource "aws_instance" "web_server-2" {
  ami                         = "ami-0430580de6244e02e"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh_key.key_name
  security_groups             = [aws_security_group.web-server-SG.name]
  user_data                   = <<-EOF
                 #!/bin/bash
                 sudo apt update -y
                 sudo apt install apache2 -y
                 sudo systemctl start apache2
                 sudo bash -c 'echo "<h1>Terrfaform Website</h1> from" $(hostname -f) > /var/www/html/index.html'
                 EOF

  tags = {
    Name = "terraform-web-server-2"
  }
  depends_on = [
    aws_key_pair.ssh_key
  ]
}

resource "aws_security_group" "loadbalancer-SG" {
  name        = "loadbalancer-SG"
  description = "Allow inbound traffic to loadbalancer"
  vpc_id      = data.aws_vpc.default_vpc.id

  ingress {
    description = "HTTP"
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

  tags = {
    Name = "loadbalancer-SG"
  }
}

resource "aws_lb" "web-app-loadbalancer" {
  name               = "web-app-loadbalancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.loadbalancer-SG.id]
  subnets            = data.aws_subnet_ids.default_subnets.ids

  tags = {
    Name = "web-app-loadbalancer"
  }
}

resource "aws_lb_target_group" "web-app-loadbalancer-TG" {
  name     = "web-app-loadbalancer-TG"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default_vpc.id
  tags = {
    Name = "web-app-loadbalancer-TG"
  }
}
resource "aws_lb_target_group_attachment" "TG-attachment-1" {
  target_group_arn = aws_lb_target_group.web-app-loadbalancer-TG.arn
  target_id        = aws_instance.web_server-1.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "TG-attachment-2" {
  target_group_arn = aws_lb_target_group.web-app-loadbalancer-TG.arn
  target_id        = aws_instance.web_server-2.id
  port             = 80
}

resource "aws_lb_listener" "loadbalancer-listener" {
  load_balancer_arn = aws_lb.web-app-loadbalancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Fixed response content"
      status_code  = "200"
    }
  }
}

resource "aws_lb_listener_rule" "static" {
  listener_arn = aws_lb_listener.loadbalancer-listener.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-app-loadbalancer-TG.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}