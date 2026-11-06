# Setup

Every way to deploy it, and every option. The short version is in the [README](../README.md).

## Deploy

### Deploy with Terraform

```hcl
module "ssm_access" {
  source = "git::https://github.com/simar-s2/ssm-access.git?ref=v0.1.0"

  enable_default_host_management = true            # optional, account-wide
}

resource "aws_iam_role_policy_attachment" "operators" {
  role       = "my-sso-or-team-role"
  policy_arn = module.ssm_access.operator_policy_arn
}
```

For a private subnet without a NAT gateway, add the endpoints and a jump host (full version in [examples/private-vpc](../examples/private-vpc)):

```hcl
module "endpoints" {
  source     = "git::https://github.com/simar-s2/ssm-access.git//modules/vpc-endpoints?ref=v0.1.0"
  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0aaa...", "subnet-0bbb..."]
}

module "jump_host" {
  source                = "git::https://github.com/simar-s2/ssm-access.git//modules/jump-host?ref=v0.1.0"
  vpc_id                = "vpc-0123456789abcdef0"
  subnet_id             = "subnet-0aaa..."
  instance_profile_name = module.ssm_access.instance_profile_name
  allow_internet_https  = false
}
```

If someone has already saved Session Manager preferences in the console, import the document first: `terraform import 'module.ssm_access.aws_ssm_document.preferences["us-east-1"]' SSM-SessionManagerRunShell`.

### Or deploy with CloudFormation

```bash
git clone https://github.com/simar-s2/ssm-access && cd ssm-access
scripts/deploy.sh --profile my-account --regions us-east-1,us-west-2 \
  --param EnableDefaultHostManagement=true
```

### Connect

You need the AWS CLI v2 and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html).

```bash
# A shell
aws ssm start-session --target i-0123456789abcdef0

# A database in the VPC on localhost:5432, through the jump host
aws ssm start-session --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters host=mydb.cluster-abc.us-east-1.rds.amazonaws.com,portNumber=5432,localPortNumber=5432
```

### SSH and VS Code

```bash
install -m 755 bin/ssm-ssh ~/.local/bin/
ssm-ssh config dev-box i-0123456789abcdef0 --profile dev >> ~/.ssh/config   # or a Name tag instead of the ID
ssh dev-box
```

In VS Code, run **Remote-SSH: Connect to Host** and pick `dev-box`. `scp` and `rsync` work the same way. The instance needs `ec2-instance-connect` (preinstalled on Amazon Linux 2023 and Ubuntu 20.04+).

## Configuration

### Terraform inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name_prefix` | `string` | `sec` | Prefix for role, policy, key and log group names |
| `regions` | `list(string)` | `[]` (provider region) | Regions to configure Session Manager in |
| `session_idle_timeout_minutes` | `number` | `20` | Idle sessions close after this |
| `session_max_duration_minutes` | `number` | `480` | Hard limit on session length |
| `run_as_user` | `string` | `null` (ssm-user) | OS user sessions run as |
| `session_log_retention_days` | `number` | `365` | CloudWatch retention for transcripts |
| `session_log_bucket_name` | `string` | `null` | Also write transcripts to this S3 bucket |
| `manage_session_preferences` | `bool` | `true` | Manage the `SSM-SessionManagerRunShell` document |
| `session_access_tag_values` | `list(string)` | `[]` (all instances) | Limit operators to instances whose `ssm-access` tag has one of these values |
| `ssh_os_users` | `list(string)` | `["ec2-user", "ubuntu"]` | OS users operators may push SSH keys for |
| `enable_default_host_management` | `bool` | `false` | Default Host Management Configuration |

### Terraform outputs

| Name | Description |
|---|---|
| `instance_profile_name`, `instance_role_arn` | Attach to instances (not needed with DHMC) |
| `operator_policy_arn` | Attach to the people who connect |
| `session_kms_key_arns` | Session key per region |
| `session_log_group_name` | Where transcripts go |

### Submodules

| Module | Inputs | Outputs |
|---|---|---|
| [vpc-endpoints](../modules/vpc-endpoints) | `vpc_id`, `subnet_ids`, `allowed_cidr_blocks` (VPC CIDR), `services` (ssm, ssmmessages, ec2messages, logs, kms), `name_prefix` | `endpoint_ids`, `security_group_id` |
| [jump-host](../modules/jump-host) | `vpc_id`, `subnet_id`, `instance_profile_name`, `instance_type` (`t4g.micro`), `architecture` (`arm64`), `root_volume_gb` (16), `allow_internet_https` (true), `patch_reboot` (`if-needed`), `name`, `tags` | `instance_id`, `security_group_id` |

### CloudFormation parameters

`HomeRegion`, `NamePrefix`, `SessionIdleTimeoutMinutes`, `SessionMaxDurationMinutes`, `SessionLogRetentionDays`, `RunAsUser`, `ManageSessionPreferences`, `EnableDefaultHostManagement`, `SshOsUsers`, `SessionAccessTagValues`. The deploy script sets `HomeRegion` to the first region; pass the rest with `--param Key=Value`.
