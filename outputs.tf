output "instance_profile_name" {
  description = "Instance profile to attach to EC2 instances (not needed with Default Host Management Configuration)."
  value       = aws_iam_instance_profile.instance.name
}

output "instance_role_arn" {
  description = "Role behind the instance profile."
  value       = aws_iam_role.instance.arn
}

output "session_kms_key_arns" {
  description = "Session encryption key per region."
  value       = { for r, k in aws_kms_key.sessions : r => k.arn }
}

output "session_log_group_name" {
  description = "CloudWatch log group that holds session transcripts in each region."
  value       = local.log_group_name
}
