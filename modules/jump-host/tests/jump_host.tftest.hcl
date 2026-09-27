mock_provider "aws" {
  override_data {
    target = data.aws_vpc.this
    values = { cidr_block = "10.20.0.0/16" }
  }
  override_data {
    target = data.aws_ssm_parameter.al2023
    values = { value = "ami-0a1b2c3d4e5f60001" }
  }
}

variables {
  vpc_id                = "vpc-0a1b2c3d4e5f60001"
  subnet_id             = "subnet-0a1b2c3d4e5f60011"
  instance_profile_name = "sec-ssm-instance"
}

run "private_imdsv2_encrypted" {
  command = plan

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "No public IP."
  }
  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 only."
  }
  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted
    error_message = "Encrypted root volume."
  }
  assert {
    condition     = aws_instance.this.tags["patch-reboot"] == "if-needed"
    error_message = "Enrolled in org-patch-manager installs."
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.https) == 1
    error_message = "HTTPS out through NAT by default."
  }
}

run "endpoint_only_vpc" {
  command = plan

  variables {
    allow_internet_https = false
    patch_reboot         = null
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.https) == 0
    error_message = "No internet egress when the VPC has endpoints."
  }
  assert {
    condition     = !contains(keys(aws_instance.this.tags), "patch-reboot")
    error_message = "A null patch_reboot leaves the host scan-only."
  }
}
