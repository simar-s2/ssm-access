# Session Manager in one account, and the operator policy attached to an
# existing role (for example the one behind your SSO permission set).

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

variable "operator_role_name" {
  type        = string
  description = "IAM role of the people who connect to instances."
}

module "ssm_access" {
  source = "../.."

  enable_default_host_management = true
}

resource "aws_iam_role_policy_attachment" "operators" {
  role       = var.operator_role_name
  policy_arn = module.ssm_access.operator_policy_arn
}

output "instance_profile_name" {
  value = module.ssm_access.instance_profile_name
}
