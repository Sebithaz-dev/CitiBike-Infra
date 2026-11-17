terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# AMI oficial ECS-optimized Amazon Linux 2023 (parametro publico de SSM).
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

# El Learner Lab no permite crear roles: se reutilizan los precreados.
data "aws_iam_instance_profile" "lab" {
  name = var.instance_profile_name
}

data "aws_iam_role" "task" {
  name = var.task_role_name
}

locals {
  tags = {
    Project     = "citibike"
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "Sebithaz-dev"
    CostCenter  = "learner-lab"
  }

  # Una sola subred publica de la VPC default alcanza para la demo; el ALB
  # usa todas las subredes para cumplir el minimo de 2 AZ.
  subnet_ids = sort(data.aws_subnets.default.ids)
  subnet_id  = local.subnet_ids[0]

  dashboard_name = "citibike-${var.environment}"
}
