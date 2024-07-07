terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "iac-schalla-tf-state"
    key    = "dbt_airflow_airbyte_hmtsk/terraform.tfstate"
    region = "eu-central-1"  
  }
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "custom_vpc" {
  cidr_block           = "172.16.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "data-platform-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  cidr_block           = "172.16.1.0/24"
  vpc_id               = aws_vpc.custom_vpc.id
  availability_zone    = "eu-central-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet1" {
  cidr_block        = "172.16.2.0/24"
  vpc_id            = aws_vpc.custom_vpc.id
  availability_zone = "eu-central-1b"
  tags = {
    Name = "private_subnet1"
  }
}

resource "aws_subnet" "private_subnet2" {
  cidr_block        = "172.16.3.0/24"
  vpc_id            = aws_vpc.custom_vpc.id
  availability_zone = "eu-central-1c"
  tags = {
    Name = "private_subnet2"
  }
}

resource "aws_db_subnet_group" "custom_subnet_group" {
  name       = "custom_subnet_group"
  subnet_ids = [aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id]
  tags = {
    Name = "rds-subnet-group"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.custom_vpc.id
  tags = {
    Name = "MyIGW"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.custom_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
  tags = {
    Name = "PublicRouteTable"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
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
    Name = "sg-rds"
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group for EC2"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
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
    Name = "sg-ec2"
  }
}

resource "aws_security_group" "airflow_security_group" {
  name        = "airflow_security_group"
  description = "Security group to allow ssh and airflow"
  vpc_id      = aws_vpc.custom_vpc.id

  ingress {
    description = "Inbound SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Inbound Airflow"
    from_port   = 8080
    to_port     = 8080
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

resource "aws_db_instance" "app_rds" {
  allocated_storage    = 10
  engine               = "postgres"
  engine_version       = "16.1"
  instance_class       = "db.t3.micro"
  db_name              = var.database_name
  username             = var.username_db
  password             = var.pwd_db
  parameter_group_name = "default.postgres16"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.custom_subnet_group.id
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
}

resource "tls_private_key" "custom_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.custom_key.public_key_openssh
}

resource "local_file" "ssh_key" {
  filename = "${aws_key_pair.generated_key.key_name}.pem"
  content = tls_private_key.custom_key.private_key_pem
  file_permission = 400
}


resource "aws_instance" "sde_ec2" {
  ami             = var.aws_ami
  instance_type   = var.instance_type
  key_name        = aws_key_pair.generated_key.key_name
  subnet_id       = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  tags = {
    Name = "sde_ec2"
  }

  user_data = <<EOF
#!/bin/bash
echo "-------------------------START SETUP---------------------------"
sudo apt-get -y update
sudo apt-get -y install \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get -y update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo chmod 666 /var/run/docker.sock
sudo apt install make
echo "-------------------------END SETUP---------------------------"
EOF
}

resource "aws_instance" "airflow_ec2" {
  ami             = var.aws_ami
  instance_type   = var.airflow_instance_type
  key_name        = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.airflow_security_group.id]
  subnet_id       = aws_subnet.public_subnet.id
  tags = {
    Name = "airflow_dbt_snowflake_ec2"
  }

  user_data = <<EOF
#!/bin/bash
echo "-------------------------START SETUP---------------------------"
sudo apt-get -y update
sudo apt-get -y install \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  unzip
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get -y update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo chmod 666 /var/run/docker.sock
echo "-------------------------END SETUP---------------------------"
EOF
}
