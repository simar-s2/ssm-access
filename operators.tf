# Managed policy for the people (or SSO permission sets) that connect to
# instances. It allows shells, SSH over SSM and port forwarding, only through
# the approved session documents, and a temporary SSH key push for SSH.

locals {
  instance_arn = "arn:${local.partition}:ec2:*:${local.account_id}:instance/*"
  target_tag   = var.session_target_tag == null ? [] : [var.session_target_tag]
}

data "aws_iam_policy_document" "operators" {
  statement {
    sid       = "StartSessionOnInstances"
    actions   = ["ssm:StartSession"]
    resources = [local.instance_arn]

    # Refuse sessions that do not name an allowed document below.
    condition {
      test     = "BoolIfExists"
      variable = "ssm:SessionDocumentAccessCheck"
      values   = ["true"]
    }

    dynamic "condition" {
      for_each = local.target_tag
      content {
        test     = "StringEquals"
        variable = "ssm:resourceTag/${condition.value.key}"
        values   = condition.value.values
      }
    }
  }

  statement {
    sid     = "SessionDocuments"
    actions = ["ssm:StartSession"]
    resources = [
      "arn:${local.partition}:ssm:*:${local.account_id}:document/SSM-SessionManagerRunShell",
      "arn:${local.partition}:ssm:*::document/AWS-StartSSHSession",
      "arn:${local.partition}:ssm:*::document/AWS-StartPortForwardingSession",
      "arn:${local.partition}:ssm:*::document/AWS-StartPortForwardingSessionToRemoteHost",
    ]
  }

  statement {
    sid       = "OwnSessionsOnly"
    actions   = ["ssm:ResumeSession", "ssm:TerminateSession"]
    resources = ["arn:${local.partition}:ssm:*:${local.account_id}:session/$${aws:userid}-*"]
  }

  # These List/Describe calls do not support resource-level permissions.
  statement {
    sid       = "FindInstances"
    actions   = ["ssm:DescribeInstanceInformation", "ssm:DescribeSessions", "ec2:DescribeInstances"]
    resources = ["*"]
  }

  statement {
    sid       = "ConnectionStatus"
    actions   = ["ssm:GetConnectionStatus"]
    resources = [local.instance_arn]
  }

  statement {
    sid       = "SessionEncryption"
    actions   = ["kms:GenerateDataKey"]
    resources = [for k in aws_kms_key.sessions : k.arn]
  }

  # SSH over SSM: the client pushes a public key that the instance accepts for 60 seconds.
  statement {
    sid       = "TemporarySshKey"
    actions   = ["ec2-instance-connect:SendSSHPublicKey"]
    resources = [local.instance_arn]

    condition {
      test     = "StringEquals"
      variable = "ec2:osuser"
      values   = var.ssh_os_users
    }

    dynamic "condition" {
      for_each = local.target_tag
      content {
        test     = "StringEquals"
        variable = "ec2:ResourceTag/${condition.value.key}"
        values   = condition.value.values
      }
    }
  }
}

resource "aws_iam_policy" "operators" {
  name        = "${var.name_prefix}-ssm-operators"
  description = "Session Manager shells, SSH over SSM and port forwarding, through approved documents only."
  policy      = data.aws_iam_policy_document.operators.json
}
