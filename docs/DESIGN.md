# Design notes

How a connection through ssm-access works, the choices I made, and what it costs.

## Architecture

```mermaid
flowchart LR
    subgraph laptop["Operator laptop"]
        vscode["VS Code Remote-SSH<br/>ssh / scp / rsync"]
        proxy["ssm-ssh proxy"]
        cli["aws ssm start-session<br/>+ Session Manager plugin"]
        vscode --> proxy --> cli
    end

    subgraph aws["AWS account"]
        iam["Operator policy<br/>approved documents only"]
        eic["EC2 Instance Connect<br/>key valid 60 s"]
        ssm["Systems Manager<br/>Session Manager"]
        logs[("CloudWatch Logs<br/>KMS-encrypted transcripts")]
        subgraph vpc["Private subnet"]
            ep["SSM VPC endpoints<br/>or NAT gateway"]
            ec2["EC2 instance<br/>SSM agent, no inbound rules"]
        end
    end

    proxy -->|"SendSSHPublicKey"| eic -.-> ec2
    cli -->|"StartSession"| iam --> ssm
    ec2 -->|"outbound HTTPS only"| ep --> ssm
    ssm --> logs
```

One SSH connection through `ssm-ssh`:

```mermaid
sequenceDiagram
    participant S as ssh / VS Code
    participant P as ssm-ssh proxy
    participant E as EC2 Instance Connect
    participant M as Session Manager
    participant I as Instance (sshd on :22)
    S->>P: ProxyCommand ssm-ssh proxy i-0abc 22 ec2-user
    P->>E: SendSSHPublicKey (ec2-user, id_ed25519.pub)
    Note over E,I: the instance accepts this key for 60 seconds
    P->>M: StartSession AWS-StartSSHSession portNumber=22
    M->>I: tunnel through the SSM agent
    S->>I: SSH handshake and key authentication over the tunnel
```

## What it does, in detail

- **Instances with no open ports.** Security groups have no inbound rules and instances need no public IP. The SSM agent on each instance makes an outbound HTTPS connection to Systems Manager, and sessions run over it.
- **Encrypted, recorded sessions.** Account-wide Session Manager preferences encrypt every session with a KMS key and stream the transcript to an encrypted CloudWatch Logs group (optionally also to S3 in a log-archive account), with idle and maximum session timeouts.
- **Least-privilege operator policy.** People can start shells, SSH over SSM and port forwarding only through the approved session documents, can only end their own sessions, and can optionally be limited to instances tagged `ssm-access=<team>`.
- **SSH for tools that need it.** `ssm-ssh` makes `ssh`, `scp`, `rsync` and VS Code Remote-SSH work through Session Manager. Each connection pushes your public key with EC2 Instance Connect, the instance accepts it for 60 seconds, and nothing is written to `authorized_keys`.
- **Instances managed without instance profiles (optional).** Default Host Management Configuration makes every EC2 instance with IMDSv2 SSM-managed automatically, which also gives [org-patch-manager](https://github.com/simar-s2/org-patch-manager) full coverage.
- **Submodules** for SSM VPC endpoints (private subnets with no NAT gateway) and a private, IMDSv2-only jump host.

**Tech:** Terraform (AWS provider 6), CloudFormation, AWS Systems Manager Session Manager, EC2 Instance Connect, KMS, CloudWatch Logs, Bash, pytest, GitHub Actions.

## Why it's built this way

- **No inbound path to attack.** There's no port 22 to scan and no bastion to patch; access is an IAM decision that CloudTrail records, and the transcript is in CloudWatch.
- **`ssm:SessionDocumentAccessCheck`.** Without it, a caller can omit the document name and fall back to the default shell document. With it, every session must use a document the policy lists, so the encryption and logging preferences can't be bypassed.
- **60-second keys instead of managed keys.** The private key never leaves the laptop, and the instance holds the public key only long enough for one login. There's nothing to rotate or revoke on the instance, and removing someone's IAM access removes their SSH access.
- **A fixed `ssm-access` tag.** CloudFormation can't build an IAM condition key from a parameter, so both deploy paths use the same fixed key, with the allowed values configurable.
- **DHMC is opt-in.** It changes how every instance in the account and region is managed, so it should be a deliberate choice. Its role gets the same session-logging permissions as the instance profile, so logging works either way.
- **The jump host is disposable.** Private subnet, no inbound rules, IMDSv2 with a hop limit of 1, encrypted root volume, and the `patch-reboot` tag so [org-patch-manager](https://github.com/simar-s2/org-patch-manager) patches it nightly.

## Cost

Session Manager, EC2 Instance Connect and Default Host Management Configuration are free. What you pay for:

- **KMS:** one key per region (about $1 per month) plus requests.
- **CloudWatch Logs:** ingestion and storage of session transcripts, usually small.
- **VPC interface endpoints**, only if you use the submodule: each endpoint is billed per hour per Availability Zone (about $7 per month each in us-east-1) plus data processed. Five endpoints in two AZs is roughly $70 per month, so drop `logs` and `kms` from `services` if the subnet already has a NAT gateway for those.
- **Jump host**, only if you use the submodule: a `t4g.micro` and a 16 GB gp3 volume.

## Project layout

```
main.tf, operators.tf, ...   root module: role, profile, preferences, keys, logs, operator policy
modules/vpc-endpoints/       SSM endpoints for subnets without NAT
modules/jump-host/           private AL2023 host reachable only through Session Manager
bin/ssm-ssh                  SSH over SSM client (ProxyCommand and config generator)
cloudformation/              the same setup as one template
scripts/deploy.sh            one-command CloudFormation deploy
scripts/demo.sh              the recording in the README
examples/                    Terraform examples
tests/                       pytest (ssm-ssh, deploy script) and terraform test
```
