variable "name_prefix" {
  type        = string
  description = "Prefix for role, policy, key and log group names."
  default     = "sec"
}

variable "regions" {
  type        = list(string)
  description = "Regions to configure Session Manager in. Empty means the provider's region."
  default     = []
}

# ---------------------------------------------------------------- sessions

variable "session_idle_timeout_minutes" {
  type        = number
  description = "Idle minutes before a session is closed (1-60)."
  default     = 20

  validation {
    condition     = var.session_idle_timeout_minutes >= 1 && var.session_idle_timeout_minutes <= 60
    error_message = "Use 1-60 minutes."
  }
}

variable "session_max_duration_minutes" {
  type        = number
  description = "Hard limit on session length in minutes (1-1440)."
  default     = 480

  validation {
    condition     = var.session_max_duration_minutes >= 1 && var.session_max_duration_minutes <= 1440
    error_message = "Use 1-1440 minutes."
  }
}

variable "run_as_user" {
  type        = string
  description = "OS user that shell sessions run as. Null keeps the default ssm-user."
  default     = null
}

variable "session_log_retention_days" {
  type        = number
  description = "CloudWatch retention for session transcripts."
  default     = 365
}

variable "session_log_bucket_name" {
  type        = string
  description = "Optional S3 bucket (for example in a log-archive account) that also receives session transcripts."
  default     = null
}

variable "manage_session_preferences" {
  type        = bool
  description = "Manage the account's Session Manager preferences (the SSM-SessionManagerRunShell document). If the document already exists, import it first."
  default     = true
}

# ---------------------------------------------------------------- access

variable "session_access_tag_values" {
  type        = list(string)
  description = "If set, operators can only reach instances whose ssm-access tag has one of these values (for example [\"platform\"]). Empty means every instance."
  default     = []
}

variable "ssh_os_users" {
  type        = list(string)
  description = "OS users operators may push a temporary SSH key for with EC2 Instance Connect."
  default     = ["ec2-user", "ubuntu"]
}

variable "enable_default_host_management" {
  type        = bool
  description = "Turn on Default Host Management Configuration, so every EC2 instance with IMDSv2 is managed by SSM without an instance profile."
  default     = false
}
