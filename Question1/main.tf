# Question1/main.tf
provider "aws" {
  region = "us-east-1"
}

variable "name_prefix" {
  default = "Anshika_Tiwari"
}

# VPC
resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "${var.name_prefix}_VPC" }
}

# Public subnets
resource "aws_subnet" "public1" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "${var.name_prefix}_PublicSubnet1" }
}
resource "aws_subnet" "public2" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "${var.name_prefix}_PublicSubnet2" }
}

# Private subnets
resource "aws_subnet" "private1" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.0.11.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "${var.name_prefix}_PrivateSubnet1" }
}
resource "aws_subnet" "private2" {
  vpc_id = aws_vpc.this.id
  cidr_block = "10.0.12.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "${var.name_prefix}_PrivateSubnet2" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${var.name_prefix}_IGW" }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.name_prefix}_PublicRouteTable" }
}
resource "aws_route_table_association" "pub1" {
  subnet_id = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "pub2" {
  subnet_id = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

# Security group for NAT/SSH (allow SSH from your IP only if needed)
resource "aws_security_group" "nat_sg" {
  name = "${var.name_prefix}_NAT_SG"
  vpc_id = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # If you know your IP, replace with "x.x.x.x/32"
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name_prefix}_NAT_SG" }
}

# Data - latest Amazon Linux 2 AMI
data "aws_ami" "amzn2" {
  most_recent = true
  owners = ["amazon"]
  filter { name = "name"; values = ["amzn2-ami-hvm-*-x86_64-gp2"] }
}

# NAT instance (t2.micro) - enables outbound for private subnets
resource "aws_instance" "nat" {
  ami           = data.aws_ami.amzn2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public1.id
  vpc_security_group_ids = [aws_security_group.nat_sg.id]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y iptables-services
              sysctl -w net.ipv4.ip_forward=1
              # Persist
              echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
              # Setup NAT (MASQUERADE)
              /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
              service iptables save
              EOF
  tags = { Name = "${var.name_prefix}_NAT_Instance" }
  disable_api_termination = false
  # key_name = "your-key-name" # optional: set if you need SSH access
}

# Disable source/dest check on NAT instance so it can forward traffic
resource "aws_network_interface_sg_attachment" "nat_sg_attach" {
  security_group_id    = aws_security_group.nat_sg.id
  network_interface_id = aws_instance.nat.primary_network_interface_id
}

resource "aws_eip" "nat_eip" {
  instance = aws_instance.nat.id
  vpc = true
  tags = { Name = "${var.name_prefix}_NAT_EIP" }
}

# Private route table -> route 0.0.0.0/0 to NAT instance
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags = { Name = "${var.name_prefix}_PrivateRouteTable" }
  route {
    cidr_block = "0.0.0.0/0"
    instance_id = aws_instance.nat.id
  }
}
resource "aws_route_table_association" "priv1" {
  subnet_id = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "priv2" {
  subnet_id = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}
