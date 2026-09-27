# A private subnet with no NAT gateway: SSM VPC endpoints, and a jump host
# that only the platform team can reach (tag ssm-access=platform).

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "One private subnet per Availability Zone."
}

module "ssm_access" {
  source = "../.."

  name_prefix               = "acme"
  session_access_tag_values = ["platform"]
}

module "endpoints" {
  source = "../../modules/vpc-endpoints"

  name_prefix = "acme"
  vpc_id      = var.vpc_id
  subnet_ids  = var.private_subnet_ids
}

module "jump_host" {
  source = "../../modules/jump-host"

  name                  = "acme-jump-host"
  vpc_id                = var.vpc_id
  subnet_id             = var.private_subnet_ids[0]
  instance_profile_name = module.ssm_access.instance_profile_name
  allow_internet_https  = false

  tags = {
    ssm-access = "platform"
  }

  depends_on = [module.endpoints]
}

output "connect" {
  value = "aws ssm start-session --target ${module.jump_host.instance_id}"
}
