########################################
# Docker Swarm – Root Configuration
########################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state in S3 with DynamoDB locking.
  # Values are supplied via backend.hcl: terraform init -backend-config=backend.hcl
  backend "s3" {
    key     = "docker-swarm/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

########################################
# Data Sources
########################################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

########################################
# VPC & Networking
########################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.project_name}-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${var.project_name}-private-${count.index + 1}" }
}

resource "aws_eip" "nat" {
  count  = var.az_count
  domain = "vpc"
  tags   = { Name = "${var.project_name}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "main" {
  count         = var.az_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags       = { Name = "${var.project_name}-nat-${count.index + 1}" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = { Name = "${var.project_name}-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

########################################
# Modules
########################################

module "iam" {
  source                         = "./modules/iam"
  project_name                   = var.project_name
  environment                    = var.environment
  secret_recovery_window_in_days = var.secret_recovery_window_in_days
}

module "security" {
  source       = "./modules/security"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = aws_vpc.main.id
  vpc_cidr     = var.vpc_cidr
  allowed_cidr = var.allowed_cidr
}

module "manager" {
  source                    = "./modules/manager"
  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = aws_vpc.main.id
  subnet_ids                = aws_subnet.public[*].id
  ami_id                    = data.aws_ami.amazon_linux_2.id
  instance_type             = var.manager_instance_type
  manager_count             = var.manager_count
  key_name                  = var.key_name
  security_group_ids        = [module.security.manager_sg_id]
  iam_instance_profile_name = module.iam.manager_instance_profile_name
  swarm_join_token_secret   = module.iam.swarm_token_secret_arn
  docker_version            = var.docker_version
}

module "load_balancer" {
  source            = "./modules/load_balancer"
  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = aws_vpc.main.id
  public_subnets    = aws_subnet.public[*].id
  security_group_id = module.security.alb_sg_id
  health_check_path = var.health_check_path
  certificate_arn   = var.certificate_arn
}

module "workers" {
  source                    = "./modules/workers"
  project_name              = var.project_name
  environment               = var.environment
  vpc_id                    = aws_vpc.main.id
  subnet_ids                = aws_subnet.private[*].id
  ami_id                    = data.aws_ami.amazon_linux_2.id
  instance_type             = var.worker_instance_type
  min_workers               = var.min_workers
  max_workers               = var.max_workers
  desired_workers           = var.desired_workers
  key_name                  = var.key_name
  security_group_ids        = [module.security.worker_sg_id]
  iam_instance_profile_name = module.iam.worker_instance_profile_name
  manager_private_ip        = module.manager.manager_primary_private_ip
  swarm_join_token_secret   = module.iam.swarm_token_secret_arn
  target_group_arn          = module.load_balancer.target_group_arn
  docker_version            = var.docker_version
}

module "dns" {
  source         = "./modules/dns"
  project_name   = var.project_name
  environment    = var.environment
  hosted_zone_id = var.hosted_zone_id
  domain_name    = var.domain_name
  alb_dns_name   = module.load_balancer.alb_dns_name
  alb_zone_id    = module.load_balancer.alb_zone_id
}
