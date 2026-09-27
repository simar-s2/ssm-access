# A small Amazon Linux 2023 host in a private subnet with no inbound rules and
# no public IP, reached only through Session Manager. Use it for SSH over SSM,
# or to forward ports to databases and other private endpoints.

variable "name" {
  type        = string
  description = "Name tag of the instance and prefix of its security group."
  default     = "jump-host"
}

variable "vpc_id" {
  type        = string
  description = "VPC of the subnet."
}

variable "subnet_id" {
  type        = string
  description = "Private subnet. It needs a NAT gateway or the SSM VPC endpoints (see ../vpc-endpoints)."
}

variable "instance_profile_name" {
  type        = string
  description = "Instance profile from the root module (output instance_profile_name). Null when Default Host Management Configuration is on."
  default     = null
}

variable "instance_type" {
  type        = string
  description = "Instance type. Must match architecture."
  default     = "t4g.micro"
}

variable "architecture" {
  type        = string
  description = "arm64 or x86_64."
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "Use arm64 or x86_64."
  }
}

variable "root_volume_gb" {
  type        = number
  description = "Root volume size."
  default     = 16
}

variable "allow_internet_https" {
  type        = bool
  description = "Allow HTTPS out to the internet (through NAT) for the SSM service and package updates. Set false when the VPC has SSM endpoints and a package mirror."
  default     = true
}

variable "patch_reboot" {
  type        = string
  description = "patch-reboot tag value for org-patch-manager: if-needed or never. Null leaves the host scan-only."
  default     = "if-needed"
}

variable "tags" {
  type        = map(string)
  description = "Extra tags."
  default     = {}
}

data "aws_vpc" "this" {
  id = var.vpc_id
}

# The latest AL2023 AMI, which ships with the SSM agent and EC2 Instance Connect.
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${var.architecture}"
}

resource "aws_security_group" "this" {
  name        = "${var.name}-sg"
  description = "No inbound access; outbound to the VPC and HTTPS for Systems Manager"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-sg" })
}

resource "aws_vpc_security_group_egress_rule" "vpc" {
  security_group_id = aws_security_group.this.id
  description       = "Anything inside the VPC (databases, caches, APIs)"
  cidr_ipv4         = data.aws_vpc.this.cidr_block
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "https" {
  #checkov:skip=CKV_AWS_382:HTTPS to the public SSM endpoints and package repositories when the VPC has no SSM endpoints.
  count = var.allow_internet_https ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "HTTPS to Systems Manager and package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_instance" "this" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring costs more than this host is worth watching every minute.
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  iam_instance_profile        = var.instance_profile_name
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = false
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_gb
    encrypted   = true
  }

  tags = merge(var.tags, { Name = var.name }, var.patch_reboot == null ? {} : { patch-reboot = var.patch_reboot })

  lifecycle {
    # Newer AMIs arrive through patching, not replacement.
    ignore_changes = [ami]
  }
}

output "instance_id" {
  description = "Instance ID of the jump host."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "Security group of the jump host. Allow it as a source on the resources it should reach."
  value       = aws_security_group.this.id
}
