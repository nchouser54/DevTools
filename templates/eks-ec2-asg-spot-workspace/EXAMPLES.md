# Deployment Examples: EKS EC2 ASG Spot Workspace

This document shows three real-world configurations for GovCloud developer teams.

---

## Example 1: Cost-Optimized Development Team (Recommended for Most Teams)

**Goal**: Support 20–50 developers with **maximum Spot savings** and **acceptable interruption risk**.

### Configuration

```bash
# .env
AWS_REGION=us-gov-west-1
SUBNET_ID=subnet-prod-us-gov-west-1a
VPC_ID=vpc-prod
AMI_ID=ami-ubuntu-22-04-custom-devtools-v1

INSTANCE_TYPE=t3.large
INSTANCE_TYPE_FALLBACKS=["m5.large","t2.large"]
OS_TYPE=linux

HOME_VOLUME_SIZE_GB=100
HOME_VOLUME_IOPS=3000
ENABLE_XRDP=false

# Spot configuration: max savings
ASG_MIN_SIZE=1
ASG_MAX_SIZE=1
SPOT_INSTANCE_POOLS=3
ON_DEMAND_PERCENTAGE=0  # 100% Spot

ENABLE_MCP_FILESYSTEM=true
ENABLE_MCP_GITHUB=true
MCP_GITHUB_TOKEN=${GITHUB_TOKEN}
```

### Results

- **Cost/developer/month**: ~$12 (t3.large Spot)
- **50 developers**: $600/month = **$7,200/year**
- **Savings vs on-demand**: ~$26,400/year
- **Interruption frequency**: ~5% chance per day (tolerable for dev work; just stop/restart)
- **Startup time**: ~2 min (cold AMI) → ~30 sec (pre-baked)

### Deployment Command

```bash
coder templates create \
  --from-dir ./templates/eks-ec2-asg-spot-workspace \
  --name "GovCloud Dev Team (Spot)"
```

---

## Example 2: Resilient Production-Critical (Finance/Healthcare)

**Goal**: Support 10–20 developers with **high availability** and **predictable costs**.

### Configuration

```bash
# .env
AWS_REGION=us-gov-west-1
SUBNET_ID=subnet-prod-us-gov-west-1a  # Primary AZ
VPC_ID=vpc-prod
AMI_ID=ami-ubuntu-22-04-hardened-prod

INSTANCE_TYPE=m5.xlarge  # Larger for more headroom
INSTANCE_TYPE_FALLBACKS=["m5.2xlarge","c5.2xlarge"]
OS_TYPE=linux

HOME_VOLUME_SIZE_GB=200
HOME_VOLUME_IOPS=6000
ENABLE_XRDP=false

# Spot + on-demand hybrid: 70% Spot, 30% on-demand
ASG_MIN_SIZE=1
ASG_MAX_SIZE=1
SPOT_INSTANCE_POOLS=4
ON_DEMAND_PERCENTAGE=30  # 30% fallback to on-demand if Spot unavailable

ENABLE_MCP_FILESYSTEM=true
ENABLE_MCP_GITHUB=true
MCP_GITHUB_TOKEN=${GITHUB_TOKEN}
```

### Results

- **Cost/developer/month**: ~$50 (m5.xlarge, 30% on-demand buffer)
- **20 developers**: $1,000/month = **$12,000/year**
- **Savings vs pure on-demand**: ~$16,000/year (40% reduction)
- **Interruption frequency**: <1% (on-demand fallback kicks in)
- **Uptime**: 99.5%+ (practical guarantee)

### Deployment Command

```bash
coder templates create \
  --from-dir ./templates/eks-ec2-asg-spot-workspace \
  --name "GovCloud Production (Hybrid)"
```

---

## Example 3: Data Science Team (Large Memory)

**Goal**: Support 5–10 data scientists with **memory-heavy instances** and **GPU (future)** for ML workloads.

### Configuration

```bash
# .env
AWS_REGION=us-gov-west-1
SUBNET_ID=subnet-prod-us-gov-west-1a
VPC_ID=vpc-prod
AMI_ID=ami-ubuntu-22-04-cuda-pytorch-v1  # Pre-baked with PyTorch, CUDA

INSTANCE_TYPE=r5.2xlarge  # Memory optimized (64 GiB RAM)
INSTANCE_TYPE_FALLBACKS=["r5.4xlarge","m5.4xlarge"]  # Larger fallbacks
OS_TYPE=linux

HOME_VOLUME_SIZE_GB=500
HOME_VOLUME_IOPS=10000  # Higher IOPS for training data I/O
ENABLE_XRDP=false

# Hybrid: Spot + on-demand for GPU-node stability
ASG_MIN_SIZE=1
ASG_MAX_SIZE=1
SPOT_INSTANCE_POOLS=2
ON_DEMAND_PERCENTAGE=50  # 50% fallback (GPU interruptions are expensive)

# Extra user-data: pre-cache datasets
USER_DATA_EXTRA="""
mkdir -p /data
# Download pre-baked training datasets
aws s3 sync s3://ml-datasets-gov/ /data/datasets --region us-gov-west-1 &
"""

ENABLE_MCP_FILESYSTEM=true
ENABLE_MCP_GITHUB=false  # Data scientists don't need GitHub MCP as much
```

### Results

- **Cost/data scientist/month**: ~$150 (r5.2xlarge, 50% on-demand)
- **10 data scientists**: $1,500/month = **$18,000/year**
- **Savings vs pure on-demand**: ~$18,000/year (50% reduction)
- **Startup time**: ~1 minute (datasets cached on AMI)
- **GPU-ready**: Replace `instance_type` with `g4dn.xlarge` when GPUs available in GovCloud

### Deployment Command

```bash
coder templates create \
  --from-dir ./templates/eks-ec2-asg-spot-workspace \
  --name "GovCloud Data Science (Memory)"
```

---

## Example 4: Shared Developer Pool (Advanced)

**Goal**: Support **unlimited developers** with a **shared instance pool** (divvy up resources).

**Note**: Requires [shared-ec2-workspace-pool](../templates/shared-ec2-workspace-pool/) template instead.

This template is **not recommended** for shared pools because:
- Each workspace owns its own ASG (1:1 mapping).
- For true pooling, use the dedicated shared-pool template.

However, you *can* approximate pooling:

```bash
# Increase asg_max_size for "max concurrent developers"
ASG_MAX_SIZE=5  # Allow up to 5 instances for burst capacity

# But with desired_capacity=1, only 1 instance per workspace
# This wastes ASG features; use shared-pool template instead
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] GovCloud account with VPC + subnet ready
- [ ] AMI ID identified and tested (launch manually first)
- [ ] Coder provisioner IAM role has merged ASG permissions
- [ ] Subnet has outbound HTTPS access to Coder server
- [ ] Coder server is reachable from target subnet (test with EC2 instance)

### During Deployment

- [ ] Fill in `.env` with your values
- [ ] Run `coder templates create --from-dir ./templates/eks-ec2-asg-spot-workspace`
- [ ] Verify template imported successfully
- [ ] Check Terraform variables in Coder dashboard match `.env`

### Post-Deployment (First Workspace)

- [ ] Create test workspace
- [ ] Wait ~3 minutes for instance and agent
- [ ] Verify `coder ssh <workspace-name>` works
- [ ] Check instance is Spot: `aws ec2 describe-instances ... | grep InstanceLifecycle`
- [ ] Verify home volume: `df -h /home/coder`
- [ ] Stop workspace and verify home EBS persists (AWS console)
- [ ] Start workspace and verify home EBS remounts
- [ ] Create 5× test workspaces to verify multi-ASG setup

### Monitoring

- [ ] Set up CloudWatch alarms for Spot interference
- [ ] Create cost dashboard (EC2 + EBS by `coder:workspace` tag)
- [ ] Track interruption frequency monthly

---

## Performance Baselines

| Metric | Value | Notes |
|--------|-------|-------|
| Instance launch time | 45–60 sec | From ASG desired_capacity=1 to running |
| User-data execution | 30–60 sec | Package install + EBS mount + agent startup |
| Agent connection | 30–45 sec | From agent init script start to Coder relay |
| Total workspace ready | 2–3 min | End-to-end from create to `coder ssh` |
| Spot interruption frequency (GovCloud) | ~5% per 24h | Varies by AZ + instance type |
| EBS reattach time | <30 sec | On workspace start (same AZ) |
| Home volume data integrity | 100% | No data loss, survives interruptions |

---

## Cost Breakdown (50-Dev Team, t3.large Spot)

| Component | Unit cost | Monthly | Annual |
|-----------|-----------|---------|--------|
| **EC2 Spot** | $0.024/hr | $288 | $3,456 |
| **EBS home (100 GiB)** | $0.10/GiB/month | $5,000 | $60,000 |
| **Total per developer** | — | $~106 | $~1,272 |
| **50 developers** | — | $5,300 | $63,600 |
| **vs on-demand (t3.large)** | ~$0.080/hr or $60/month | $3,000 | $36,000 |
| **Annual savings** | — | — | ~$27,000 |

**Note**: EBS cost is high here; reduce `home_volume_size_gb` or use cheaper storage (e.g., S3 + EFS for shared projects).

---

## Troubleshooting Deployment

### Template import fails: "Invalid Terraform"

**Fix**: Check `coder/main.tf` for syntax errors. Run:
```bash
terraform validate -chdir=templates/eks-ec2-asg-spot-workspace/coder
```

### ASG creates but no instance launches

**Fix**: Check Spot availability in your AZ:
```bash
aws ec2 describe-spot-price-history \
  --instance-types t3.large \
  --availability-zone us-gov-west-1a \
  --region us-gov-west-1 \
  --max-results 1
```

If no results, Spot is unavailable; set `on_demand_percentage=100` temporarily.

### Agent never connects (outbound blocked)

**Fix**: Test outbound HTTPS from subnet:
```bash
# Launch a test EC2 in the subnet and run:
curl -v https://your-coder-server.example.com
```

If it hangs, check security group rules and NAT Gateway.

---

## References

- [Template README](./README.md) — Full architecture details
- [AWS Spot Pricing](https://aws.amazon.com/ec2/spot/pricing/) — GovCloud pricing
- [Coder Provisioning](https://coder.com/docs/v2/latest/admin/provisioning) — Coder provisioning workflow
