mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}", minified_json = "{}" }
  }
  override_data {
    target = data.aws_region.current
    values = { region = "us-east-1" }
  }
  override_data {
    target = data.aws_caller_identity.current
    values = { account_id = "111122223333" }
  }
  override_data {
    target = data.aws_partition.current
    values = { partition = "aws" }
  }
}

# apply, not plan: the preferences document embeds the key ARN, which is only
# known after apply. With the mocked provider, apply still makes no AWS calls.
run "defaults" {
  command = apply

  assert {
    condition     = keys(aws_kms_key.sessions) == ["us-east-1"] && keys(aws_ssm_document.preferences) == ["us-east-1"]
    error_message = "One key and one preferences document in the provider region."
  }
  assert {
    condition     = aws_ssm_document.preferences["us-east-1"].name == "SSM-SessionManagerRunShell" && aws_ssm_document.preferences["us-east-1"].document_type == "Session"
    error_message = "Preferences live in the SSM-SessionManagerRunShell session document."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.preferences["us-east-1"].content).inputs.idleSessionTimeout == "20"
    error_message = "Idle sessions close after 20 minutes."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.preferences["us-east-1"].content).inputs.runAsEnabled == false
    error_message = "Sessions run as ssm-user unless run_as_user is set."
  }
  assert {
    condition     = aws_iam_instance_profile.instance.name == "sec-ssm-instance"
    error_message = "Instance profile name comes from name_prefix."
  }
  assert {
    condition     = length(aws_iam_role.dhmc) == 0 && length(aws_ssm_service_setting.dhmc) == 0
    error_message = "Default Host Management Configuration is opt-in."
  }
  assert {
    condition     = aws_cloudwatch_log_group.sessions["us-east-1"].name == "/sec/ssm-sessions" && aws_cloudwatch_log_group.sessions["us-east-1"].retention_in_days == 365
    error_message = "Transcripts are kept for a year."
  }
}

run "dhmc_and_run_as_in_two_regions" {
  command = apply

  variables {
    name_prefix                    = "acme"
    regions                        = ["us-east-1", "eu-west-1"]
    enable_default_host_management = true
    run_as_user                    = "ec2-user"
    session_log_bucket_name        = "acme-org-logs-222233334444"
  }

  assert {
    condition     = length(aws_ssm_service_setting.dhmc) == 2
    error_message = "DHMC is set in every region."
  }
  assert {
    condition     = aws_ssm_service_setting.dhmc["eu-west-1"].setting_value == "service-role/acme-ssm-default-host"
    error_message = "DHMC points at the service-role path."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.preferences["eu-west-1"].content).inputs.runAsDefaultUser == "ec2-user"
    error_message = "run_as_user reaches the preferences."
  }
  assert {
    condition     = jsondecode(aws_ssm_document.preferences["eu-west-1"].content).inputs.s3KeyPrefix == "ssm-sessions/111122223333/eu-west-1"
    error_message = "S3 transcripts are prefixed by account and region."
  }
}

run "preferences_can_be_left_alone" {
  command = plan

  variables {
    manage_session_preferences = false
  }

  assert {
    condition     = length(aws_ssm_document.preferences) == 0
    error_message = "No preferences document when unmanaged."
  }
}

run "rejects_long_idle_timeout" {
  command = plan

  variables {
    session_idle_timeout_minutes = 90
  }

  expect_failures = [var.session_idle_timeout_minutes]
}
