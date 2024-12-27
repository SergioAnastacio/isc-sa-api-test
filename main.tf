terraform {
  backend "s3" {
    bucket         = "isc-anasty-state"
    key            = "terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "anasty-lock-table"
  }
}

provider "aws" {
  region = "us-west-1"
}

resource "aws_vpc" "anasty_vpc" {
  cidr_block = "172.30.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_support = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "anasty_gateway" {
  vpc_id = aws_vpc.anasty_vpc.id
}

resource "aws_subnet" "anasty_subnet_a" {
  vpc_id            = aws_vpc.anasty_vpc.id
  cidr_block        = "172.30.0.0/24"
  availability_zone = "us-west-1b"
}

resource "aws_subnet" "anasty_subnet_b" {
  vpc_id            = aws_vpc.anasty_vpc.id
  cidr_block        = "172.30.1.0/24"
  availability_zone = "us-west-1c"
}

resource "aws_route_table" "anasty_route_table" {
  vpc_id = aws_vpc.anasty_vpc.id
}

resource "aws_route" "default_route" {
  route_table_id         = aws_route_table.anasty_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.anasty_gateway.id
}

resource "aws_route_table_association" "anasty_table_association_a" {
  subnet_id      = aws_subnet.anasty_subnet_a.id
  route_table_id = aws_route_table.anasty_route_table.id
}

resource "aws_route_table_association" "anasty_table_association_b" {
  subnet_id      = aws_subnet.anasty_subnet_b.id
  route_table_id = aws_route_table.anasty_route_table.id
}

resource "aws_security_group" "anasty_security_group" {
  name        = "anasty-security-group"
  description = "Allow SSH and HTTP traffic"
  vpc_id      = aws_vpc.anasty_vpc.id

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

resource "aws_instance" "back_anasty" {
  ami                    = "ami-0657605d763ac72a8"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.anasty_security_group.id]
  key_name               = "masternode"
  subnet_id              = aws_subnet.anasty_subnet_a.id
  associate_public_ip_address = true
}

resource "aws_eip" "back_anasty_eip" {
  instance = aws_instance.back_anasty.id
}

output "api_instance_ip" {
  value = aws_eip.back_anasty_eip.public_ip
}

resource "aws_db_instance" "anasty_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.39"
  instance_class       = "db.t4g.micro"
  db_name              = "digidb"
  username             = var.db_username
  password             = var.db_password
  skip_final_snapshot  = true
  publicly_accessible  = true
  vpc_security_group_ids = [aws_security_group.anasty_db_sg.id]
  db_subnet_group_name = aws_db_subnet_group.anasty_db_subnet_group.name
}

resource "aws_db_subnet_group" "anasty_db_subnet_group" {
  name       = "anasty-db-subnet-group"
  subnet_ids = [aws_subnet.anasty_subnet_a.id, aws_subnet.anasty_subnet_b.id]
}

resource "aws_security_group" "anasty_db_sg" {
  name        = "anasty-db-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.anasty_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
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

output "db_endpoint" {
  value = aws_db_instance.anasty_db.endpoint
}

resource "aws_instance" "web_server" {
  ami                    = "ami-0657605d763ac72a8" # Ubuntu 24.04 LTS
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.web_server_sg.id]
  key_name               = "masternode"
  subnet_id              = aws_subnet.anasty_subnet_a.id
  associate_public_ip_address = true
}

resource "aws_eip" "web_server_eip" {
  instance = aws_instance.web_server.id
}

resource "aws_security_group" "web_server_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.anasty_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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

output "web_instance_ip" {
  value = aws_eip.web_server_eip.public_ip
}

resource "local_file" "instance_api_ip_file" {
  content  = aws_eip.back_anasty_eip.public_ip
  filename = "${path.module}/api_instance_ip.txt"
}

resource "local_file" "instance_web_ip_file" {
  content  = aws_eip.web_server_eip.public_ip
  filename = "${path.module}/web_instance_ip.txt"
}