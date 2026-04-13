# GovCloud ASG Spot Infrastructure Template

Standalone Auto Scaling Group with Spot Instances on AWS GovCloud for **scalable infrastructure** (not Coder-managed).

Use this for:
- CI/CD build runners (GitHub Actions self-hosted, GitLab runners)
- Application servers (API servers, web servers)
- Worker pools (batch jobs, async processing)
- Data processing clusters (Spark, Kubernetes worker nodes)

**Key differences from `eks-ec2-asg-spot-workspace`:**
- No Coder management; direct infrastructure
- Multi-instance ASG (min=2, max=6, etc.)
- Metric-based scaling (CPU, memory, custom metrics)
- Load balancer integration (ALB/NLB)
- Systems Manager (SSM) for remote access
- Instance profiles for AWS service permissions

---

## Architecture

```
┌─────────────────────────────────────────┐
│ Auto Scaling Group (Multi-instance)     │
│ desired_capacity: 3                     │
│ min_size: 2, max_size: 6                │
└──────────────┬──────────────────────────┘
               │
    ┌──────────┼──────────┐
    ↓          ↓          ↓
┌────────┐ ┌────────┐ ┌────────┐
│ Spot 1 │ │ Spot 2 │ │ Spot 3 │
│ t3.med │ │t3.large│ │ m5.med │
└────────┘ └────────┘ └────────┘

If Spot unavailable:
    ↓
┌────────┐
│ On-Dm  │  (fallback, 20% of capacity)
│ t3.med │
└────────┘
```

---

## Prerequisites

### IAM Instance Profile

Instances need permissions for:
- SSM (Systems Manager): `ssm:UpdateInstanceInformation`, `ec2messages:AcknowledgeMessage`, etc.
- Optional: ECR, S3, CloudWatch, SNS (app-specific)

See `docs/iam-policies/govcloud-asg-spot-infrastructure-irsa-policy.json`.

### Networking

- Multiple subnets across AZs (for ASG distribution)
- Subnets have egress to:
  - Package repositories (apt, yum, etc.)
  - Docker registry (if `enable_docker=true`)
  - AWS service endpoints (EC2, SSM, CloudWatch, etc.)

---

## Variables Reference

### Auto Scaling Group

| Variable | Default | Description |
|----------|---------|-------------|
| `asg_name` | `asg-infrastructure` | ASG name (must be unique per region) |
| `asg_min_size` | `2` | Minimum instances |
| `asg_max_size` | `6` | Maximum instances |
| `asg_desired_capacity` | `3` | Initial desired capacity |
| `enable_target_group` | `false` | Register instances with target group (ALB/NLB) |
| `target_group_arn` | `""` | Target group ARN for load balancer |

### Spot Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `instance_type` | `t3.medium` | Primary instance type |
| `instance_type_fallbacks` | `[]` | Fallback types (e.g., `["t3.large","m5.medium"]`) |
| `spot_instance_pools` | `3` | Number of Spot pools for diversification |
| `spot_allocation_strategy` | `capacity-optimized` | Allocation strategy |
| `spot_max_price` | `""` | Max Spot bid (empty = on-demand price) |
| `on_demand_percentage` | `20` | % on-demand fallback (0-100) |

### Instance Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ami_id` | required | AMI ID for instances |
| `os_type` | `linux` | `linux` or `windows` |
| `aws_region` | `us-gov-west-1` | GovCloud region |
| `subnet_ids` | required | List of subnet IDs (cross-AZ) |
| `vpc_id` | auto-detected | VPC ID |
| `instance_profile_name` | `""` | IAM instance profile |
| `key_name` | `""` | EC2 key pair for manual SSH (optional with SSM) |
| `associate_public_ip` | `false` | Public IP (set true if no NAT) |

### EBS & Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `root_volume_size_gb` | `50` | Root EBS size |
| `root_volume_type` | `gp3` | EBS type |
| `root_volume_iops` | `3000` | IOPS for gp3 |

### Features

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_docker` | `true` | Install Docker daemon |
| `enable_ssm` | `true` | Enable Systems Manager agent for remote shell access |
| `enable_cloudwatch_detailed` | `true` | Detailed CloudWatch monitoring |
| `https_proxy` | `""` | HTTPS proxy for isolated VPCs |
| `http_proxy` | `""` | HTTP proxy |

### Load Balancer (Optional)

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_alb` | `false` | Create ALB for instances |
| `alb_subnets` | `""` | Public subnets for ALB |
| `alb_security_groups` | `""` | Security group for ALB |

### Tagging

| Variable | Default | Description |
|----------|---------|-------------|
| `environment` | `production` | Environment tag |
| `project` | `infrastructure` | Project tag |
| `cost_center` | `engineering` | Cost center tag |

---

## Instance Lifecycle

| Event | What happens |
|-------|---|
| **Create ASG** | Terraform creates ASG with desired_capacity=3 |
| **Launch** | ASG launches 3 instances (Spot or on-demand) |
| **Running** | Instances run user-data, install apps, join target group (if ALB) |
| **Scaling up** | ASG launches new instances on CPU > 70% (if metric-based scaling enabled) |
| **Scaling down** | ASG terminates instances on CPU < 30% (if metric-based scaling enabled) |
| **Spot interruption** | AWS interrupts Spot instance; ASG auto-replaces |
| **Manual termination** | `aws autoscaling terminate-instance-in-auto-scaling-group ...` |
| **Delete ASG** | `terraform destroy` terminates all instances |

---

## Access Methods

### Systems Manager (Recommended)

```bash
# Start interactive shell session (no SSH key needed)
aws ssm start-session --target i-xyz123 --region us-gov-west-1

# Run command on all instances
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=['sudo systemctl status docker']" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=asg-infrastructure-workers"
```

### SSH (If using EC2 key pair)

```bash
# Get instance IPs (only if associated_public_ip=true or NAT)
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=asg-infrastructure-workers" \
  --query 'Reservations[].Instances[].[PrivateIpAddress,PublicIpAddress,InstanceId]'

# SSH to instance
ssh -i my-key.pem ec2-user@10.0.1.42
```

---

## Monitoring & Scaling

### CloudWatch Metrics

Instances publish:
- `CPUUtilization`
- `NetworkIn`, `NetworkOut`
- Custom metrics (if app sends them)

### Metric-Based Scaling (Optional)

Add scaling policies to `terraform/main.tf`:

```hcl
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  autoscaling_group_name = aws_autoscaling_group.infrastructure.name
  cooldown               = 300
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "asg-cpu-high"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 300
  threshold           = 70
  evaluation_periods  = 2
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}
```

---

## Cost Optimization

### Baseline (3 instances, t3.medium Spot, 8 hrs/day, 22 work days/month)

| Component | Monthly cost |
|-----------|---|
| **EC2 Spot** (3 × $0.024/hr × 176 hrs) | $12.67 |
| **EC2 on-demand fallback** (20% + interruptions) | $2.50 |
| **EBS root** (3 × 50 GiB × $0.10) | $15.00 |
| **Total** | ~$30/month |

### Annual at scale (6 instances average, larger instances)

Scale to m5.xlarge Spot:
- Per instance: $0.058/hr × 176 hrs = $10.21/month
- 6 instances = $61.26 + EBS = **~$85/month = $1,020/year**
- Savings vs on-demand: **~$1,500/year**

---

## GovCloud-Specific Notes

- **Partition ARNs**: Use `arn:aws-us-gov`
- **Spot availability**: Lower than commercial AWS; always include fallback types
- **SSM endpoints**: Create VPC endpoints for `ssm`, `ec2messages`, `ssmmessages` in private subnets
- **Service endpoints**: `ec2.us-gov-west-1.amazonaws.com`, `autoscaling.us-gov-west-1.amazonaws.com`

---

## Use Cases & Examples

### CI/CD Runners (GitHub Actions)

```bash
INSTANCE_TYPE=t3.large
ASG_MIN_SIZE=1
ASG_MAX_SIZE=10
ASG_DESIRED_CAPACITY=2

# user-data installs:
# - GitHub Actions self-hosted runner
# - Docker
# - Git, Node.js, etc.
```

### Application Servers (Load-balanced API)

```bash
INSTANCE_TYPE=m5.xlarge
ASG_MIN_SIZE=3
ASG_MAX_SIZE=6
ENABLE_ALB=true

# user-data installs:
# - Docker
# - Application runtime (Python, Node.js, Java)
# - Health check endpoint
```

### Worker Pool (Batch Jobs)

```bash
INSTANCE_TYPE=c5.2xlarge
ASG_MIN_SIZE=2
ASG_MAX_SIZE=20
ON_DEMAND_PERCENTAGE=50

# user-data installs:
# - Job queue client (SQS, RabbitMQ, etc.)
# - Processing dependencies
# - CloudWatch logging agent
```

---

## Deployment Steps

1. **Fill in `.env.example`** with your VPC, subnets, and AMI
2. **Apply IAM policy** to instance profile role
3. **Run Terraform**: `terraform -chdir=terraform apply -var-file=../terraform.tfvars`
4. **Verify**: `aws autoscaling describe-auto-scaling-groups --asg-names=asg-infrastructure-workers`
5. **Monitor**: CloudWatch dashboard for CPU, instance count, Spot interruptions

---

## Troubleshooting

### Instances won't launch

**Check**: Spot availability for your instance types in the AZs
```bash
aws ec2 describe-spot-price-history --instance-types t3.medium m5.medium \
  --region us-gov-west-1 --max-results 5
```

**Fix**: Add more fallback types or increase `on_demand_percentage`

### SSM session fails

**Check**: VPC endpoints exist for `ssm`, `ec2messages`, `ssmmessages`
```bash
aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=*ssm*"
```

### ASG not registering with Load Balancer

**Check**: Target group ARN is correct and instances pass health checks
```bash
aws elbv2 describe-target-health --target-group-arn <arn>
```

---

## References

- AWS docs: [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/)
- AWS docs: [Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- AWS docs: [Systems Manager](https://docs.aws.amazon.com/systems-manager/)
