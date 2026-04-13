# Quick Start: EKS EC2 ASG Spot Workspace

## What This Template Solves

You want to provide developer AMIs on GovCloud **at scale** with **maximum cost savings** using **Spot Instances**. This template handles:

- ✅ **Auto Scaling Group** management (Coder controls start/stop via desired capacity)
- ✅ **Spot Instances** (70% cost savings vs on-demand)
- ✅ **Persistent home** (EBS survives Spot interruptions)
- ✅ **Multi-pool resilience** (fallback instance types for Spot availability)
- ✅ **GovCloud compliance** (IMDSv2, proper partition ARNs, outbound-only security)

## Prerequisites

### 1. GovCloud Account Setup

- AWS GovCloud region: `us-gov-west-1` (or desired region)
- VPC with a private/public subnet (outbound HTTPS to Coder server)
- Get your subnet ID and VPC ID:
  ```bash
  aws ec2 describe-subnets --region us-gov-west-1 --filters "Name=vpc-id,Values=vpc-xxxxx" --query 'Subnets[0].[SubnetId,VpcId]'
  ```

### 2. AMI ID

Get a valid GovCloud AMI:

```bash
# Ubuntu 22.04 LTS in GovCloud
aws ec2 describe-images \
  --region us-gov-west-1 \
  --owners amazon \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].[ImageId,Name]' \
  --output text
```

Copy the AMI ID (e.g., `ami-0abc123def456789`).

### 3. Coder Provisioner IAM Role

Your Coder provisioner pod needs ASG + launch template permissions. Merge these statements into the existing provisioner role policy:

```bash
cat <<'EOF'
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
}
EOF
```

For the full policy, see: [docs/iam-policies/eks-ec2-asg-spot-workspace-irsa-policy.json](../docs/iam-policies/eks-ec2-asg-spot-workspace-irsa-policy.json)

Apply it to your provisioner service account's IAM role.

### 4. (Optional) Coder Workspace for Import

You need one running Coder workspace with Terraform support. If you don't have one, set up Coder on your EKS cluster first.

---

## Step 1: Prepare Environment Variables

Copy the template and fill in your values:

```bash
cp templates/eks-ec2-asg-spot-workspace/.env.example .env
```

Edit `.env`:

| Variable | Example | Notes |
|----------|---------|-------|
| `AWS_REGION` | `us-gov-west-1` | GovCloud region |
| `SUBNET_ID` | `subnet-0abc123def456789` | Private or public subnet with outbound HTTPS |
| `VPC_ID` | `vpc-0abc123def456789` | VPC containing the subnet |
| `AMI_ID` | `ami-0abc123def456789` | Your GovCloud AMI (Ubuntu, RHEL, Windows, etc.) |
| `INSTANCE_TYPE` | `t3.medium` | Primary instance type |
| `HOME_VOLUME_SIZE_GB` | `50` | Persistent home volume size |

**Optional but recommended:**

| Variable | Example | Purpose |
|----------|---------|---------|
| `INSTANCE_TYPE_FALLBACKS` | `["t3.large","m5.large"]` | Fallback types for Spot diversification |
| `ON_DEMAND_PERCENTAGE` | `20` | % on-demand if Spot unavailable (0-100) |
| `ENABLE_XRDP` | `true` | Linux desktop access (Linux only) |
| `ENABLE_MCP_GITHUB` | `true` | GitHub integration for Claude Code |

---

## Step 2: Import the Template into Coder

### Option A: Via Coder Dashboard

1. Login to your Coder server.
2. **Templates** → **Create template** → **Upload from Git**
3. Paste the git repo URL and branch: `https://github.com/your-org/devtools` → `main`
4. Select template path: `templates/eks-ec2-asg-spot-workspace`
5. Review variables and click **Create template**

### Option B: Via Coder CLI

```bash
coder templates create \
  --from-dir ./templates/eks-ec2-asg-spot-workspace \
  --name "AWS GovCloud ASG Spot"
```

---

## Step 3: Create Your First Workspace

In the Coder dashboard:

1. **Create workspace** → Select **AWS GovCloud ASG Spot** template
2. Fill in required parameters:
   - **ami_id**: Your GovCloud AMI from Step 1
   - **subnet_id**: Your target subnet
   - **instance_type**: (default `t3.medium` is fine)
3. Click **Create workspace**

Coder will:

```
1. Create a launch template (instance config)
2. Create an Auto Scaling Group (min=1, max=1, desired=0 initially)
3. Create a persistent EBS home volume
4. Start the ASG → launch Spot Instance from your AMI
5. Run user-data → coder user created, EBS mounted at /home/coder
6. Start Coder agent → connects outbound to Coder server
7. Show agent as "Connected" ✓
```

---

## Step 4: Connect to Your Workspace

### Linux (SSH)

```bash
coder ssh <workspace-name>
```

VS Code Remote-SSH works seamlessly.

### Windows (RDP)

```bash
coder port-forward <workspace-name> --tcp 3389:3389
# Then in RDP client: localhost:3389
# Username: coder (or Administrator)
```

### Linux Desktop (if `enable_xrdp=true`)

```bash
coder port-forward <workspace-name> --tcp 3389:3389
# Then RDP to localhost:3389
```

---

## Step 5: Verify Spot Is Running

Check the EC2 console:

```bash
aws ec2 describe-instances \
  --region us-gov-west-1 \
  --filters "Name=tag:coder:workspace,Values=<workspace-name>" \
  --query 'Reservations[0].Instances[0].[InstanceLifecycle,InstanceType,State.Name]' \
  --output text
```

Expected output:
```
spot    t3.medium    running
```

---

## Cost Verification

### Estimate Monthly Savings

```bash
# On-demand t3.medium: ~$0.040/hour
# Spot t3.medium (GovCloud): ~$0.012/hour
# Daily cost (9 hours work): $0.108 vs $0.36
# Monthly cost (20 days): $2.16 vs $7.20
# Savings: $5/month per dev

# 50 developers: $250/month = $3,000/year
```

Monitor in AWS Cost Explorer → Filter by tag `coder:workspace`.

---

## Troubleshooting

### Workspace created but instance won't launch

**Symptom**: ASG desired capacity is 1 but no instance running.

**Cause**: Spot unavailable for your instance type in the AZ.

**Fix**:
1. Add fallback types: `instance_type_fallbacks=["t3.large","m5.large"]`
2. Or increase on-demand fallback: `on_demand_percentage=20`
3. Or change `subnet_id` to a different AZ

### Agent never connects

**Symptom**: Instance is running (`aws ec2 describe-instances`) but Coder shows "Offline".

**Cause**: Security group blocks outbound HTTPS, or Coder server URL unreachable.

**Fix**:
1. Check security group: `aws ec2 describe-security-groups --query 'SecurityGroups[?Tags[?Key==`coder:workspace`]]'`
2. Verify egress rules allow 443: `aws ec2 describe-security-group-rules --filters Name=group-id,Values=sg-xxxxx`
3. SSH manually (if using EC2 key pair): `ssh -i key.pem ec2-user@<instance-ip>` and check `/var/log/coder-userdata.log`

### Home volume empty after restart

**Symptom**: `/home/coder` exists but is empty on workspace start.

**Cause**: `home_device_name` doesn't match NVMe remapping. (E.g., you set `/dev/xvdh` but instance sees `/dev/nvme1n1`.)

**Fix**:
1. SSH into instance and run: `lsblk` to see EBS device name
2. Update `home_device_name` variable to match
3. Re-import template with corrected value

### Spot interruption every few hours

**Symptom**: Workspace goes offline suddenly; ASG replaces instance.

**Cause**: High Spot interruption rate in your AZ (normal for GovCloud).

**Fix**:
1. Set `on_demand_percentage=50` to run 50% on-demand (more stable, ~45% cost savings)
2. Or add fallback types to spread across more Spot pools
3. Or move to a different AZ (change `subnet_id`)

---

## Next Steps

### 1. Pre-baked AMI (Recommended)

Build a custom AMI with common tools pre-installed to **cut startup time from 2 min to 30 sec**:

```bash
# Tools to bake in:
# - git, nodejs, npm, python3, curl, jq
# - coder OS user (pre-created)
# - Docker daemon (optional)

# Use Packer to automate
packer build -var region=us-gov-west-1 ami-builder.hcl
```

### 2. Shared Workspace Pools

Scale to multiple developers sharing a single instance:

1. Set `asg_max_size=3` to allow up to 3 instances
2. Load-balance Coder workspace creation across instances
3. See [shared-ec2-workspace-pool](../templates/shared-ec2-workspace-pool/) template

### 3. Monitoring

Add CloudWatch alarms:

```bash
# Alert if instance is not running (Spot interruption or failure)
aws cloudwatch put-metric-alarm \
  --alarm-name coder-spot-interruption \
  --metric-name GroupInServiceInstances \
  --namespace AWS/AutoScaling \
  --threshold 1 --comparison-operator LessThanThreshold
```

### 4. Custom Bootstrap

Add to `user_data_extra` in `.env`:

```bash
# Example: pre-clone a Git repo
git clone https://github.com/my-org/my-prod-repo.git /home/coder/project

# Example: pre-install Docker
curl https://get.docker.com | bash
sudo usermod -aG docker coder
```

---

## Support & References

- [Template README](./README.md) — Full architecture, variables, lifecycle, GovCloud notes
- [IAM Policy](../docs/iam-policies/eks-ec2-asg-spot-workspace-irsa-policy.json) — Required provisioner permissions
- [Single Instance Template](../templates/eks-ec2-ami-workspace/) — For interactive, on-demand workloads
- [Spot Instance Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html) — AWS reference
- [Coder Docs](https://coder.com/docs) — Coder docs index
