# Keyless instance access with Session Manager: no inbound ports, no
# long-lived SSH keys, every session encrypted and recorded.
#
#   account-wide  instance role + profile, operator policy, optional DHMC role
#   per region    KMS key and log group for session transcripts, Session
#                 Manager preferences, optional DHMC setting

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  regions    = toset(length(var.regions) > 0 ? var.regions : [data.aws_region.current.region])

  log_group_name = "/${var.name_prefix}/ssm-sessions"
  key_alias      = "alias/${var.name_prefix}-ssm-sessions"
}

# ---------------------------------------------------------------- per-region KMS key and log group

data "aws_iam_policy_document" "session_key" {
  for_each = local.regions

  #checkov:skip=CKV_AWS_109:Key policies must use "*" as the resource; access is limited by principals and conditions.
  #checkov:skip=CKV_AWS_111:Key policies must use "*" as the resource; access is limited by principals and conditions.
  #checkov:skip=CKV_AWS_356:Key policies must use "*" as the resource; access is limited by principals and conditions.
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${each.key}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${each.key}:${local.account_id}:log-group:${local.log_group_name}"]
    }
  }
}

resource "aws_kms_key" "sessions" {
  for_each = local.regions
  region   = each.key

  description         = "Encrypts Session Manager sessions and their transcripts"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.session_key[each.key].json
}

resource "aws_kms_alias" "sessions" {
  for_each = local.regions
  region   = each.key

  name          = local.key_alias
  target_key_id = aws_kms_key.sessions[each.key].key_id
}

resource "aws_cloudwatch_log_group" "sessions" {
  for_each = local.regions
  region   = each.key

  name              = local.log_group_name
  retention_in_days = var.session_log_retention_days
  kms_key_id        = aws_kms_key.sessions[each.key].arn
}

# ---------------------------------------------------------------- Session Manager preferences

# SSM-SessionManagerRunShell holds the account's Session Manager preferences.
# It already exists if someone saved preferences in the console:
#   terraform import 'module.ssm_access.aws_ssm_document.preferences["<region>"]' SSM-SessionManagerRunShell
resource "aws_ssm_document" "preferences" {
  for_each = var.manage_session_preferences ? local.regions : toset([])
  region   = each.key

  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Session Manager preferences: encrypted sessions, transcripts to CloudWatch Logs"
    sessionType   = "Standard_Stream"
    inputs = {
      kmsKeyId                    = aws_kms_key.sessions[each.key].arn
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.sessions[each.key].name
      cloudWatchEncryptionEnabled = true
      cloudWatchStreamingEnabled  = true
      s3BucketName                = var.session_log_bucket_name == null ? "" : var.session_log_bucket_name
      s3KeyPrefix                 = var.session_log_bucket_name == null ? "" : "ssm-sessions/${local.account_id}/${each.key}"
      s3EncryptionEnabled         = var.session_log_bucket_name != null
      idleSessionTimeout          = tostring(var.session_idle_timeout_minutes)
      maxSessionDuration          = tostring(var.session_max_duration_minutes)
      runAsEnabled                = var.run_as_user != null
      runAsDefaultUser            = var.run_as_user == null ? "" : var.run_as_user
      shellProfile = {
        linux   = "cd ~ && exec bash -l"
        windows = ""
      }
    }
  })
}

# ---------------------------------------------------------------- permissions shared by instances

# What the SSM agent needs beyond AmazonSSMManagedInstanceCore to use the
# encrypted, logged sessions above. Used by the instance role and the DHMC role.
data "aws_iam_policy_document" "agent_session_logging" {
  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [for k in aws_kms_key.sessions : k.arn]
  }

  statement {
    sid       = "SessionTranscripts"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
    resources = flatten([for g in aws_cloudwatch_log_group.sessions : [g.arn, "${g.arn}:*"]])
  }

  dynamic "statement" {
    for_each = var.session_log_bucket_name == null ? [] : [1]
    content {
      sid       = "SessionTranscriptsS3"
      actions   = ["s3:PutObject", "s3:GetEncryptionConfiguration"]
      resources = ["arn:${local.partition}:s3:::${var.session_log_bucket_name}", "arn:${local.partition}:s3:::${var.session_log_bucket_name}/ssm-sessions/${local.account_id}/*"]
    }
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-ssm-instance"
  description        = "Lets EC2 instances be managed by Systems Manager and use logged Session Manager sessions."
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "instance_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance_session_logging" {
  name   = "session-logging"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.agent_session_logging.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-ssm-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------- Default Host Management Configuration

data "aws_iam_policy_document" "dhmc_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dhmc" {
  count = var.enable_default_host_management ? 1 : 0

  name               = "${var.name_prefix}-ssm-default-host"
  path               = "/service-role/"
  description        = "Default Host Management Configuration: SSM manages every EC2 instance without an instance profile."
  assume_role_policy = data.aws_iam_policy_document.dhmc_assume.json
}

resource "aws_iam_role_policy_attachment" "dhmc" {
  count = var.enable_default_host_management ? 1 : 0

  role       = aws_iam_role.dhmc[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"
}

resource "aws_iam_role_policy" "dhmc_session_logging" {
  count = var.enable_default_host_management ? 1 : 0

  name   = "session-logging"
  role   = aws_iam_role.dhmc[0].id
  policy = data.aws_iam_policy_document.agent_session_logging.json
}

resource "aws_ssm_service_setting" "dhmc" {
  for_each = var.enable_default_host_management ? local.regions : toset([])
  region   = each.key

  setting_id    = "arn:${local.partition}:ssm:${each.key}:${local.account_id}:servicesetting/ssm/managed-instance/default-ec2-instance-management-role"
  setting_value = "service-role/${aws_iam_role.dhmc[0].name}"
}
