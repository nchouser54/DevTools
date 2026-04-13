# Standalone Infrastructure: GovCloud ASG + Spot Instances

## What This Is

A **standalone Terraform template** for provisioning scalable infrastructure on GovCloud using Auto Scaling Groups with Spot Instances. **Not managed by Coder** — for independent workloads.

## Use Cases

- **CI/CD runners** (GitHub Actions self-hosted, GitLab runners)
- **Application servers** (API servers, web servers, load-balanced)
- **Worker pools** (batch jobs, async processing, queued tasks)
- **Data clusters** (analytics, ML training, Spark workers)

## What You Get

| File | Purpose |
|------|---------|
| **README.md** | Full architecture, variables, monitoring, troubleshooting |
| **QUICKSTART.md** | 5-minute setup guide |
| **terraform/main.tf** | Terraform code (ASG, launch template, security group) |
| **.env.example** | All variables with defaults |
| **docs/iam-policies/govcloud-asg-spot-infrastructure-irsa-policy.json** | Required IAM permissions |

## Key Features

- ✅ **Multi-instance ASG** (configure min/max/desired capacity)
- ✅ **Spot Instances** (70% cost savings)
- ✅ **Automatic replacement** (ASG handles Spot interruptions)
- ✅ **Multi-pool resilience** (fallback instance types)
- ✅ **Systems Manager access** (remote shell without SSH key)
- ✅ **Docker pre-installed** (optional)
- ✅ **CloudWatch monitoring** (detailed metrics)
- ✅ **Load balancer ready** (ALB/NLB integration)
- ✅ **GovCloud-hardened** (IMDSv2, proper partition ARNs)

## 5-Minute Deployment

```bash
# 1. Get AMI & subnets from GovCloud
# 2. Create terraform/terraform.tfvars with your values
# 3. terraform init && terraform apply
# 4. Done — instances launching in ASG
```

See **QUICKSTART.md** for detailed walkthrough.

## Architecture

```
Auto Scaling Group (3 instances desired)
├── Instance 1: Spot t3.medium (10.0.1.10)
├── Instance 2: Spot t3.large (10.0.1.20)
└── Instance 3: On-demand t3.medium (10.0.1.30, fallback)

User-data bootstrap:
├── Install Docker
├── Install Systems Manager agent
├── Enable CloudWatch monitoring
└── Ready for workload

Access:
├── Systems Manager: aws ssm start-session --target i-xyz123
├── SSH: ssh ec2-user@10.0.1.10 (with .ssh/my-key.pem)
└── Load balancer: ALB front-end (optional)
```

## Cost Estimate

**3× t3.medium Spot (8 hrs/day, 22 days/month)**
- Monthly: ~$30
- Annual: ~$360
- Savings vs on-demand: ~70% ($100/month)

**Scale to 6× instances**: ~$60/month ($720/year)

## Configuration Examples

### Example 1: CI/CD Runners
```bash
instance_type = "t3.large"
asg_min_size = 2
asg_max_size = 10
asg_desired_capacity = 3
on_demand_percentage = 20
```

### Example 2: Load-Balanced Web Servers
```bash
instance_type = "m5.xlarge"
asg_min_size = 3
asg_max_size = 6
enable_alb = true
on_demand_percentage = 50  # Higher availability
```

### Example 3: Batch Worker Pool
```bash
instance_type = "c5.2xlarge"
asg_min_size = 2
asg_max_size = 20
on_demand_percentage = 30
# Scale up/down based on queue depth
```

## Key Differences from eks-ec2-asg-spot-workspace

| Aspect | Workspace | Infrastructure |
|--------|-----------|-----------------|
| **Managed by** | Coder | Standalone Terraform |
| **Instances per workspace** | 1 | N (configure min/max) |
| **Access** | Coder relay (SSH/RDP tunneled) | SSM or SSH directly |
| **Persistent storage** | EBS home (/home/coder) | Ephemeral (each instance fresh) |
| **Lifecycle** | Coder controls (start/stop) | You control (Terraform, ASG scaling) |
| **Workload** | Development environments | CI/CD, apps, workers |

## What's Included

```
templates/govcloud-asg-spot-infrastructure/
├── manifest.json
├── README.md (comprehensive reference)
├── QUICKSTART.md (5-min setup)
├── .env.example (all variables)
├── terraform/
│   ├── main.tf (880 lines, fully commented)
│   └── variables.tf (provider setup)
└── (all files committed to repository)

docs/iam-policies/
└── govcloud-asg-spot-infrastructure-irsa-policy.json
```

## Next Steps

1. **Review README.md** for architecture and variables
2. **Follow QUICKSTART.md** for 5-minute deployment
3. **Pick an example** (CI/CD, web, worker) and customize
4. **Deploy** with Terraform: `terraform apply`
5. **Monitor** via CloudWatch or AWS console

---

**Status**: COMPLETE ✓ Ready for immediate use in GovCloud
