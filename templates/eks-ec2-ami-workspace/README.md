# EKS EC2 AMI Workspace

Launch a fresh EC2 instance from **any AMI** as a Coder workspace in AWS GovCloud. The Coder agent is injected via EC2 `user_data` for Linux (bash) or Windows (PowerShell). A **persistent encrypted EBS volume** is attached to `/home/coder` on every start so your data survives workspace stop/start cycles — even though the EC2 instance itself is terminated on stop.

## Architecture

```
Workspace START                      Workspace STOP
──────────────                       ──────────────
aws_instance.workspace created   →   aws_instance.workspace terminated
aws_volume_attachment.home attaches  aws_volume_attachment.home detached
user_data: mounts EBS → starts agent  aws_ebs_volume.home  (PERSISTS)
agent → phones home to Coder server
```

Key design decisions:
- **EC2 instance**: ephemeral — terminated on workspace stop, recreated from AMI on start.
- **EBS home volume**: persistent — survives stop/start, encrypted at rest (`gp3`, 50 GiB default).
- **No inbound ports**: Coder agent connects outbound only; SSH and RDP are tunneled through the agent relay.
- **IMDSv2 enforced**: `http_tokens = required` — protects against SSRF metadata attacks.

## Prerequisites

### Coder provisioner pod (IRSA role)

See `docs/iam-policies/eks-ec2-ami-workspace-irsa-policy.json` for the full IAM policy. Summary:

| Permission group | Actions required |
|---|---|
| EC2 launch/terminate | `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:Describe*` |
| EBS management | `ec2:CreateVolume`, `ec2:DeleteVolume`, `ec2:AttachVolume`, `ec2:DetachVolume` |
| Security groups | `ec2:CreateSecurityGroup`, `ec2:DeleteSecurityGroup`, `ec2:AuthorizeSecurityGroup*` |
| IAM pass-through | `iam:PassRole` to `ec2.amazonaws.com` (if using `instance_profile_name`) |

### Target subnet

| Requirement | Details |
|---|---|
| **Outbound HTTPS (443)** | EC2 must reach the Coder server URL after launch |
| **EC2 service endpoints** | If private VPC: create VPC endpoints for `ec2`, `ebs` in `us-gov-west-1` |
| **Availability zone** | `home_device_name` volume is created in the subnet's AZ automatically |

## Variables reference

### Required

| Variable | Description |
|---|---|
| `ami_id` | AMI ID in the target region (`ami-xxxx`) |
| `subnet_id` | VPC subnet ID to place the instance in |
| `instance_type` | EC2 instance type (`t3.medium`, `m5.xlarge`, etc.) |

### Common optional

| Variable | Default | Description |
|---|---|---|
| `os_type` | `linux` | `linux` or `windows` |
| `aws_region` | `us-gov-west-1` | AWS GovCloud region |
| `vpc_id` | *(auto from subnet)* | VPC ID for security group |
| `key_name` | `""` | EC2 key pair for out-of-band SSH (not required for Coder) |
| `instance_profile_name` | `""` | IAM instance profile to attach |
| `associate_public_ip` | `false` | Public IP (needed if no NAT/private routing) |
| `root_volume_size_gb` | `30` | Root EBS size in GiB |
| `home_volume_size_gb` | `50` | Persistent home EBS size in GiB (encrypted gp3) |
| `home_volume_iops` | `3000` | IOPS for gp3 home volume |
| `home_device_name` | `/dev/xvdh` | Linux device name for home EBS attachment |
| `user_data_extra` | `""` | Extra bash commands to run before the Coder agent starts |
| `https_proxy` | `""` | HTTPS proxy for isolated VPCs |
| `enable_xrdp` | `false` | Linux only: install/configure XRDP for desktop access over Coder port-forward |
| `xrdp_port` | `3389` | Linux XRDP listen port |

### MCP

| Variable | Default | Description |
|---|---|---|
| `enable_mcp_filesystem` | `true` | Register filesystem MCP for Claude Code |
| `mcp_allowed_root` | `/home/coder/project` | Root path for filesystem MCP |
| `enable_mcp_github` | `false` | Register GitHub MCP |
| `mcp_github_token` | `""` | GitHub PAT (sensitive) |

## Workspace lifecycle

| Event | EC2 instance | EBS home volume |
|---|---|---|
| **Create** | Launched from AMI; user_data runs; agent starts | Created (formatted on first use) |
| **Stop** | **Terminated** | **Persists** (detached, kept) |
| **Start** | Launched from same AMI fresh; home EBS re-attached | Re-attached and re-mounted |
| **Delete** | Terminated (if running) | **Deleted** with the workspace |

`/home/coder` data such as repos, dotfiles, and shell history persists across stop/start. The root filesystem (`/`, OS packages, etc.) resets to the AMI on every start.

## Accessing the workspace

### Linux (SSH)
```sh
coder ssh <workspace-name>
```
VS Code Remote-SSH works via the Coder CLI extension.

### Linux desktop (XRDP)
If you set `enable_xrdp=true`, user-data installs XRDP + XFCE (best effort by distro) and starts the XRDP service:

```sh
# Forward XRDP through Coder agent relay
coder port-forward <workspace-name> --tcp 3389:3389

# Connect your RDP client to localhost:3389
```

If you changed `xrdp_port`, replace `3389` with your configured port.

### Windows (RDP)
```sh
# Terminal 1 — forward RDP port through the Coder agent relay
coder port-forward <workspace-name> --tcp 3389:3389

# RDP client — connect to:
#   Server:   localhost:3389
#   Username: coder  (or Administrator)
#   Password: check user_data or Windows password policy
```

## Common failure causes (and fixes)

| Symptom | Likely cause | Fix |
|---|---|---|
| Instance launches but agent never connects | Coder server URL unreachable from EC2 | Check subnet routing, SG egress, VPC endpoints; try `associate_public_ip = true` |
| `Error: UnauthorizedOperation` in Terraform | Missing IRSA permissions | Apply `eks-ec2-ami-workspace-irsa-policy.json` to the provisioner role |
| `Error: InvalidAMIID.NotFound` | AMI not in target region / wrong account | Verify AMI exists in `aws_region` and is owned/shared with your account |
| Home volume mounts but `/home/coder` is empty on restart | `home_device_name` doesn't match NVMe remapping | The user-data includes NVMe heuristics; set `home_device_name = /dev/xvdf` or adjust as needed |
| agent connects, then user-data errors in `/var/log/coder-userdata.log` | Package install fails | Add required repos in `user_data_extra`, or use a pre-baked AMI |
| Windows: RDP not accessible | Windows Firewall rule missing | user-data enables the RDP firewall rule; ensure `instance_type` has completed EC2 initialization before connecting |
| `InvalidGroup.NotFound` on re-apply | SG deleted out of band | `terraform apply` recreates it; use `additional_tags` to identify Coder SGs |

## GovCloud-specific notes

- **Partition**: IAM ARNs use `arn:aws-us-gov`.
- **EC2 service endpoint**: `ec2.us-gov-west-1.amazonaws.com` (FIPS: `ec2-fips.us-gov-west-1.amazonaws.com`).
- **IMDSv2** is enforced by this template — some older user-data scripts that use `curl http://169.254.169.254/latest/...` without the token header will fail. Update them to use `TOKEN=$(curl -X PUT .../api/token ...)`.
- **GovCloud AMI IDs** differ from commercial region AMI IDs — do not copy AMI IDs from AWS public docs without verifying in your GovCloud account.
- **KMS encryption**: The EBS home volume is encrypted using the default EBS KMS key for the account. For CMEK, add `kms_key_id` to the `aws_ebs_volume` block and grant the provisioner role `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey`, `kms:CreateGrant`.

## Pre-baked AMI recommendation

To reduce workspace start time, build a custom AMI with:
- Common packages already installed (`git`, `jq`, `nodejs`, `npm`, `curl`)
- The `coder` OS user created
- (Optional) Pre-pulled Claude Code binary

Use `workspace/bootstrap.sh` to smoke-test your AMI content in a container before baking.
