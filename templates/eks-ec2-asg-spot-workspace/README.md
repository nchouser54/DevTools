# EKS EC2 ASG Spot Workspace

Launch **cost-optimized developer workspaces** using Auto Scaling Groups with Spot Instances on AWS GovCloud. Each workspace runs on a single Spot Instance in an ASG, with a persistent encrypted EBS home volume that survives Spot interruptions or instance replacement.

## Architecture

```
Coder Workspace
      ↓
 Terraform applies
      ↓
 aws_launch_template (instance config + user-data)
      ↓
 aws_autoscaling_group (min=1, max=1, desired=1)
      ↓
 Spot Instance (or on-demand fallback if configured)
      ↓
 aws_ebs_volume (persistent /home/coder, encrypted, survives interruptions)
```

## Key Design Decisions

| Component | Choice | Why |
|-----------|--------|-----|
| **Instance lifecycle** | Ephemeral via ASG | Spot can be interrupted; ASG auto-replaces with clean AMI |
| **Home storage** | Persistent EBS (`/home/coder`) | Repos, dotfiles, shell history survive ASG churn |
| **Spot configuration** | 100% Spot by default | Maximum cost savings; toggle `on_demand_percentage` for resilience |
| **Security groups** | Outbound-only | Coder agent connects outbound; SSH/RDP tunneled via relay |
| **IMDSv2** | Enforced | Protects against SSRF; required in GovCloud |

## Prerequisites

### Coder provisioner IAM role (IRSA)

Your Coder provisioner pod needs these additional permissions beyond the standard `eks-ec2-ami-workspace` policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ASGManagement",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:SetDesiredCapacity"
      ],
      "Resource": "arn:aws-us-gov:autoscaling:*:*:autoScalingGroup:*:autoScalingGroupName/coder-*"
    },
    {
      "Sid": "LaunchTemplateManagement",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateLaunchTemplate",
        "ec2:CreateLaunchTemplateVersion",
        "ec2:DeleteLaunchTemplate",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeLaunchTemplateVersions"
      ],
      "Resource": [
        "arn:aws-us-gov:ec2:*:*:launch-template/*"
      ]
    },
    {
      "Sid": "SpotPricing",
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeSpotPriceHistory"
      ],
      "Resource": "*"
    }
  ]
}
```

Merge this with the existing `eks-ec2-ami-workspace-irsa-policy.json` (which covers EC2 instance, volume, and security group management).

### Network & connectivity

See [eks-ec2-ami-workspace README](../eks-ec2-ami-workspace/README.md#prerequisites) for VPC, subnet, and proxy requirements. They are identical.

## Variables Reference

### Required

| Variable | Description |
|----------|-------------|
| `ami_id` | AMI ID in target region (e.g., `ami-0123456789abcdef0`). Must exist in your GovCloud account. |
| `subnet_id` | VPC subnet ID for instance placement. Must have outbound HTTPS access to Coder server. |

### Auto Scaling Group (ASG)

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_type` | `t3.medium` | Primary instance type. Override with `instance_type_fallbacks` for mixed-instance policy. |
| `asg_min_size` | `1` | Minimum instances in ASG. Typically `1` for single workspace. |
| `asg_max_size` | `1` | Maximum instances in ASG. Increase for shared developer pools. |
| `asg_desired_capacity` | `1` | Current targets. Coder scales to 1 on start, 0 on stop. |
| `spot_instance_pools` | `2` | Number of Spot capacity pools for diversification. Higher = more resilient. |
| `spot_allocation_strategy` | `capacity-optimized` | Allocate to pools with optimal capacity. Minimizes interruption rate. |
| `spot_max_price` | `""` (on-demand price) | Max Spot bid. Leave empty to use current Spot price. |
| `on_demand_percentage` | `0` | Reserve N% capacity for on-demand (fallback). `0` = 100% Spot. Try `20` if Spot unavailable. |
| `instance_type_fallbacks` | `[]` | Additional instance types for Spot pools (e.g., `["t3.large", "m5.large"]`). |

### EBS & Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `home_volume_size_gb` | `50` | Persistent home volume size in GiB. |
| `home_volume_type` | `gp3` | EBS volume type (`gp3` recommended for balance). |
| `home_volume_iops` | `3000` | IOPS for gp3. Minimum 3000, maximum 16000. |
| `home_device_name` | `/dev/xvdh` | Device name for EBS attachment on Linux. |
| `root_volume_size_gb` | `30` | Root EBS size. Increased from AMI's default. |

### Instance & Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `os_type` | `linux` | Operating system: `linux` or `windows`. |
| `aws_region` | `us-gov-west-1` | AWS GovCloud region. |
| `vpc_id` | `""` (auto from subnet) | VPC ID for security group. Auto-detected if omitted. |
| `key_name` | `""` | EC2 key pair for out-of-band SSH (optional). |
| `instance_profile_name` | `""` | IAM instance profile name. Grants instance permissions to AWS services. |
| `associate_public_ip` | `false` | Assign public IP. Set to `true` if subnet has no NAT. |

### User Data & Proxy

| Variable | Default | Description |
|----------|---------|-------------|
| `https_proxy` | `""` | HTTPS proxy URL for isolated VPCs. |
| `http_proxy` | `""` | HTTP proxy URL. |
| `no_proxy` | Standard list | Comma-separated hosts/CIDRs to bypass proxy. |
| `user_data_extra` | `""` | Extra bash commands (Linux) or PowerShell (Windows) before agent starts. Use for custom package installs. |

### Linux Desktop & MCP

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_xrdp` | `false` | Enable XRDP on Linux for desktop access over port-forward. |
| `xrdp_port` | `3389` | XRDP listen port if enabled. |
| `enable_mcp_filesystem` | `true` | Register filesystem MCP for Claude Code. |
| `mcp_allowed_root` | `/home/coder/project` | Root path for filesystem MCP. |
| `enable_mcp_github` | `false` | Register GitHub MCP (requires token). |
| `mcp_github_token` | `""` | GitHub Personal Access Token (sensitive). |

## Workspace Lifecycle

### Create

1. Coder creates the launch template with instance config and user-data.
2. Coder creates the ASG with `desired_capacity=1`.
3. AWS launches a Spot Instance from the template (or on-demand if Spot unavailable).
4. user-data runs:
   - Installs base dependencies (`git`, `curl`, `jq`, etc.).
   - Mounts persistent home EBS volume at `/home/coder`.
   - Creates `coder` OS user.
   - Starts Coder agent (connects outbound to Coder server).
5. Coder workspace is ready; agent comes online.

### Stop

1. Coder sets `asg_desired_capacity=0`.
2. ASG terminates the running Spot Instance.
3. Persistent home EBS volume is detached but **retained**.

### Start

1. Coder sets `asg_desired_capacity=1`.
2. ASG launches a fresh Spot Instance (or different instance type if previous unavailable).
3. Fresh AMI boots; user-data re-mounts the persistent home EBS.
4. Agent restarts and reconnects.
5. `/home/coder` data (repos, dotfiles, shell history) is intact.

### Delete

1. Coder deletes the ASG (terminates instance) and persistent home volume.

### Spot Interruption (unexpected)

1. AWS interrupts the Spot Instance (no fault of Coder).
2. ASG detects instance unhealthy after ~5 minutes, replaces it.
3. Replacement instance mounts the same persistent home EBS.
4. **Result**: Workspace temporarily offline; next start works normally with all data intact.

## Cost Savings

### Typical GovCloud Spot pricing

| Instance Type | On-demand | Spot | Savings |
|---------------|-----------|------|---------|
| `t3.medium` | $0.040/hr | $0.012/hr | **70%** |
| `t3.large` | $0.080/hr | $0.024/hr | **70%** |
| `m5.xlarge` | $0.192/hr | $0.058/hr | **70%** |

### Per-developer annual cost (assuming 8 hrs/day, 250 working days/year)

| Setup | Instance type | 8h/day cost | Annual cost |
|-------|---------------|------------|------------|
| On-demand | `t3.medium` | $0.32 | **$800** |
| Spot (this template) | `t3.medium` | $0.096 | **$240** |
| **Savings** | — | — | **$560/dev/year** |

For 50 developers: **$28,000 annual savings**.

## Spot Interruption Handling

### Default behavior (100% Spot)

- **Interruption rate**: ~5% over 24 hours for `t3.medium` in GovCloud (varies by AZ and time).
- **Impact**: Workspace goes offline; manual `coder start` brings it back.
- **Data**: Safe—persistent home is untouched.

### Enhanced resilience (mixed on-demand/Spot)

To reduce interruptions, set:

```hcl
on_demand_percentage = 20  # Reserve 20% for on-demand
```

This runs instances on-demand if Spot is unavailable. Trade-off: cost increases to ~80% of on-demand pricing.

### Monitoring Spot health

Add CloudWatch alarm (optional in `coder/main.tf`):

```hcl
resource "aws_cloudwatch_metric_alarm" "asg_spot_interruption" {
  alarm_name          = "coder-asg-spot-interruption-${local.ws_slug}"
  alarm_description   = "Alert when ASG instance is not running (Spot interruption or unavailability)"
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 0.5
  comparison_operator = "LessThanThreshold"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.developer_workspace.name
  }

  # SNS topic or other action
  # alarm_actions = [aws_sns_topic.alerts.arn]
}
```

## Accessing the Workspace

### Linux (SSH)

```sh
coder ssh <workspace-name>
```

### Linux desktop (XRDP)

If `enable_xrdp=true`:

```sh
coder port-forward <workspace-name> --tcp 3389:3389
# Then connect RDP client to localhost:3389
```

### Windows (RDP)

```sh
coder port-forward <workspace-name> --tcp 3389:3389
# Then connect RDP client to localhost:3389 (user: `coder` or `Administrator`)
```

## Common Failure Causes & Fixes

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| ASG created but instance doesn't launch | Spot unavailable in region for instance type | Add fallback types in `instance_type_fallbacks` or set `on_demand_percentage > 0` |
| Instance launches but agent never connects | Coder server URL unreachable from subnet | Check subnet routing, security group egress, VPC endpoints (for private subnets) |
| Persistent home mounts but empty on restart | `home_device_name` mismatch on NVMe remapping | Adjust `home_device_name` in template or let user-data heuristics resolve it |
| `UnauthorizedOperation` in Terraform | Missing IRSA permissions | Merge ASG + launch template policies (above) into provisioner role |
| Spot interruption every few hours | High interruption rate in AZ | Use mixed on-demand/Spot or move to different AZ (change `subnet_id`) |

## GovCloud-Specific Notes

- **Partition**: IAM ARNs use `arn:aws-us-gov`. Already handled in policies above.
- **Spot availability**: GovCloud has lower Spot availability than commercial AWS. Always include 2+ fallback instance types.
- **EC2 service endpoint**: Uses standard `ec2.us-gov-west-1.amazonaws.com` (FIPS optional).
- **KMS encryption**: EBS home volume uses default account KMS key. For customer-managed key, add `kms_key_id` to `aws_ebs_volume` block and grant provisioner role `kms:*` permissions.
- **IMDS**: IMDSv2 enforced to prevent SSRF attacks.

## Quick Start

1. **Copy `.env.example` to `.env`** and fill in your region, subnet, VPC, and AMI ID.
2. **Provision IAM role** with merged policies (standard EC2 + ASG/launch template permissions above).
3. **Import into Coder** using the standard import flow.
4. **Create a workspace**: specify `ami_id`, `subnet_id`, and optionally `instance_type_fallbacks` for mixed-instance resilience.
5. **Start the workspace**: ASG launches Spot Instance; agent connects in ~2 minutes.
6. **Stop the workspace**: ASG terminates instance; home persistent volume retained.

## Pre-Baked AMI Recommendation

To reduce startup time from 2 minutes to ~30 seconds, build a custom AMI with:

- Common dev tools pre-installed (`git`, `nodejs`, `npm`, `python3`, `curl`, `jq`).
- `coder` OS user pre-created with shell configured.
- (Optional) Docker daemon or other runtime pre-installed.
- (Optional) Coder agent binary pre-pulled (if available for your architecture).

Use `Packer` or the AWS EC2 Image Builder to automate AMI builds, then reference that AMI ID in workspace variables.

## Related Templates

- [eks-ec2-ami-workspace](../eks-ec2-ami-workspace/) — single instance per workspace (simpler, interactive use cases).
- [shared-ec2-workspace-pool](../shared-ec2-workspace-pool/) — shared instance runtime profiles (different pooling model).
- [govcloud-template-starter](../govcloud-template-starter/) — starter scaffold for custom GovCloud templates.

## Further Reading

- AWS docs: [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-basics.html)
- AWS docs: [Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- Coder docs: [Terraform Provider](https://registry.terraform.io/providers/coder/coder/latest/docs)
