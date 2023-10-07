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

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-SN.id
  route_table_id = aws_route_table.public-RT.id
}