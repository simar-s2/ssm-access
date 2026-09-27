mock_provider "aws" {
  override_data {
    target = data.aws_vpc.this
    values = { cidr_block = "10.20.0.0/16" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-1" }
  }
}

variables {
  vpc_id     = "vpc-0a1b2c3d4e5f60001"
  subnet_ids = ["subnet-0a1b2c3d4e5f60011", "subnet-0a1b2c3d4e5f60012"]
}

run "session_manager_endpoints" {
  command = plan

  assert {
    condition     = toset(keys(aws_vpc_endpoint.this)) == toset(["ssm", "ssmmessages", "ec2messages", "logs", "kms"])
    error_message = "Session Manager plus logs and KMS by default."
  }
  assert {
    condition     = aws_vpc_endpoint.this["ssmmessages"].service_name == "com.amazonaws.eu-west-1.ssmmessages" && aws_vpc_endpoint.this["ssm"].private_dns_enabled
    error_message = "Regional service names with private DNS."
  }
  assert {
    condition     = keys(aws_vpc_security_group_ingress_rule.https) == ["10.20.0.0/16"]
    error_message = "Only the VPC can reach the endpoints by default."
  }
}
