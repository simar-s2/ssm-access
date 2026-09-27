# Interface endpoints so instances in private subnets with no NAT gateway can
# still reach Systems Manager (and CloudWatch Logs and KMS for logged,
# encrypted sessions). Private DNS makes the agent use them automatically.

variable "name_prefix" {
  type        = string
  description = "Prefix for the security group name."
  default     = "sec"
}

variable "vpc_id" {
  type        = string
  description = "VPC to add the endpoints to."
}

variable "subnet_ids" {
  type        = list(string)
  description = "One private subnet per Availability Zone. Each endpoint gets a network interface in each."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "Who may reach the endpoints on 443. Empty means the VPC's primary CIDR."
  default     = []
}

variable "services" {
  type        = list(string)
  description = "Endpoint services. ssm, ssmmessages and ec2messages are required for Session Manager; logs and kms for logged, encrypted sessions."
  default     = ["ssm", "ssmmessages", "ec2messages", "logs", "kms"]
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_region" "current" {}

resource "aws_security_group" "endpoints" {
  name        = "${var.name_prefix}-ssm-endpoints"
  description = "HTTPS from inside the VPC to the Systems Manager endpoints"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  for_each = toset(length(var.allowed_cidr_blocks) > 0 ? var.allowed_cidr_blocks : [data.aws_vpc.this.cidr_block])

  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from ${each.key}"
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "this" {
  for_each = toset(var.services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}

output "endpoint_ids" {
  description = "Endpoint ID per service."
  value       = { for s, e in aws_vpc_endpoint.this : s => e.id }
}

output "security_group_id" {
  description = "Security group on the endpoints."
  value       = aws_security_group.endpoints.id
}
