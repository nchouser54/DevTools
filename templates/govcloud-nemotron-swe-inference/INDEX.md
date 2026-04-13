# Index: Nemotron 3 SWE Inference API Architecture

## Overview

Scalable Nemotron 3 Super Agentic SWE inference API on AWS GovCloud with:
- **Multi-option** GPU/CPU configurations
- **Spot Instances** (70% cost savings)
- **Auto-Scaling** (2-8 instances based on CPU)
- **Application Load Balancer** (HTTPS, health checks)
- **Persistent Model Cache** (survives instance termination)

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          INTERNET                               │
│                    (HTTPS Port 443)                             │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                        ┌──────▼──────┐
                        │ AWS ACM Cert│
                        │   (HTTPS)   │
                        └──────┬──────┘
                               │
                    ┌──────────▼──────────┐
                    │  Application Load   │
                    │    Balancer (ALB)   │
                    │ 443 → 8000:HTTP    │
                    │  Health Checks      │
                    │  Connection Drain   │
                    └──────────┬──────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
         ┌──────▼─────┐ ┌──────┼─────┐ ┌──────▼─────┐
         │  Instance 1 │ │ Instance 2 │ │ Instance 3 │
         │ (Spot)      │ │  (Spot)    │ │  (Spot)    │
         │ g4dn.xlarge │ │ g4dn.xlarge│ │ g4dn.xlarge│
         │ T4 GPU      │ │ T4 GPU     │ │ T4 GPU     │
         │ vLLM        │ │ vLLM       │ │ vLLM       │
         │ Port 8000   │ │ Port 8000  │ │ Port 8000  │
         └──────┬──────┘ └──────┬─────┘ └──────┬─────┘
                │              │              │
                └──────────────┼──────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Auto Scaling Group  │
                    │                     │
                    │ Min: 2              │
                    │ Max: 8              │
                    │ Desired: 3          │
                    │ Health Grace: 10min │
                    └─────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
         ┌────▼────┐      ┌────▼────┐     ┌────▼────┐
         │ Subnet A │      │ Subnet B │     │ Subnet C│
         │ AZ A     │      │ AZ B     │     │ AZ C    │
         └──────────┘      └──────────┘     └─────────┘
                               │
                    ┌──────────▼──────────┐
                    │  CloudWatch Alarms  │
                    │  CPU > 75% → +1     │
                    │  CPU < 30% → -1     │
                    └─────────────────────┘
                               │
                    ┌──────────▼──────────┐
                    │ Persistent EBS Vol  │
                    │ Model Cache         │
                    │ /mnt/model-cache/   │
                    │ (survives termination)
                    └─────────────────────┘
```

---

## File Structure

```
govcloud-nemotron-swe-inference/
├── manifest.json                          # Template metadata
├── README.md                              # Full documentation (2000+ lines)
├── QUICKSTART.md                          # 5-step deployment guide
├── INDEX.md                               # This file
├── terraform.tfvars.example               # Configuration template
├── .env.example                           # Environment variables (reference only)
│
├── terraform/
│   ├── main.tf                            # Core infrastructure (850 lines)
│   │   ├── Security Groups (instances + ALB)
│   │   ├── IAM Role + Instance Profile
│   │   ├── Launch Template (dynamic for all 3 options)
│   │   ├── Application Load Balancer
│   │   ├── Target Group (with health checks)
│   │   ├── ASG (mixed instances, Spot + on-demand)
│   │   └── CloudWatch Alarms (scale-up/down)
│   │
│   ├── variables.tf                       # All input variables (400 lines)
│   │   ├── AWS region (GovCloud validation)
│   │   ├── VPC + subnet configuration
│   │   ├── Nemotron model config
│   │   ├── Option 1/2/3 parameters
│   │   ├── Spot instance settings
│   │   ├── Storage configuration
│   │   └── Monitoring + tagging
│   │
│   ├── outputs.tf                         # Terraform outputs (100 lines)
│   │   ├── ALB DNS name + ARN
│   │   ├── ASG configuration
│   │   ├── Launch template info
│   │   ├── Active option + instance type
│   │   ├── API endpoints (completions + health)
│   │   ├── CloudWatch alarm names
│   │   └── Deployment summary
│   │
│   ├── user-data-gpu.sh                   # GPU instance bootstrap (180 lines)
│   │   ├── Docker installation
│   │   ├── NVIDIA Docker runtime
│   │   ├── EBS volume mount (/mnt/model-cache)
│   │   ├── vLLM container pull + start
│   │   ├── Model download (Hugging Face)
│   │   └── Health check setup
│   │
│   └── user-data-cpu.sh                   # CPU instance bootstrap (180 lines)
│       ├── Docker installation
│       ├── Ollama setup (CPU inference)
│       ├── EBS volume mount
│       ├── Model download
│       └── OpenAI-compatible API wrapper
│
└── docs/
    └── iam-policy-provisioner.json        # IAM permissions for Terraform user
```

---

## Configuration Options

### Option 1: g4dn.xlarge (T4 GPU) ⭐ RECOMMENDED

**Best for**: Cost-conscious, high throughput

```hcl
option_1_enabled           = true
option_1_min_size          = 2
option_1_max_size          = 8
option_1_desired_capacity  = 3
option_1_scale_up_cpu      = 75
option_1_scale_down_cpu    = 30
```

| Metric | Value |
|--------|-------|
| **GPU** | 1× NVIDIA T4 (16 GB) |
| **CPU** | 4 vCPU Intel Xeon |
| **RAM** | 16 GiB |
| **Spot Cost/hr** | $0.158 |
| **Monthly (3×)** | $340 |
| **Monthly (8×)** | $907 |
| **Throughput** | ~1,500 tokens/sec |
| **Availability** | Low (Spot scarcity) |

---

### Option 2: p3.2xlarge (V100 GPU)

**Best for**: High throughput, medium availability

```hcl
option_2_enabled           = true
option_2_min_size          = 2
option_2_max_size          = 6
option_2_desired_capacity  = 3
option_2_scale_up_cpu      = 75
option_2_scale_down_cpu    = 30
```

| Metric | Value |
|--------|-------|
| **GPU** | 1× NVIDIA V100 (32 GB) |
| **CPU** | 8 vCPU Intel Xeon |
| **RAM** | 61 GiB |
| **Spot Cost/hr** | $0.918 |
| **Monthly (3×)** | $1,980 |
| **Monthly (8×)** | $5,286 |
| **Throughput** | ~2,500 tokens/sec |
| **Availability** | Medium |

---

### Option 3: c6i.4xlarge (CPU-only)

**Best for**: Fallback, always-on capability, cost under pressure

```hcl
option_3_enabled           = true
option_3_min_size          = 3
option_3_max_size          = 20
option_3_desired_capacity  = 5
option_3_scale_up_cpu      = 65
option_3_scale_down_cpu    = 25
```

| Metric | Value |
|--------|-------|
| **GPU** | None (CPU inference) |
| **CPU** | 16 vCPU Intel Xeon |
| **RAM** | 32 GiB |
| **Spot Cost/hr** | $0.340 |
| **Monthly (5×)** | $1,224 |
| **Monthly (20×)** | $4,896 |
| **Throughput** | ~250 tokens/sec (5-6× slower) |
| **Availability** | High (always available) |

---

### Option 4: g6.xlarge (L40 GPU) ✅ RECOMMENDED FOR INFERENCE

**Best for**: Optimal inference performance with L40 GPU (purpose-built for inference)

```hcl
option_4_enabled           = true
option_4_min_size          = 2
option_4_max_size          = 8
option_4_desired_capacity  = 3
option_4_scale_up_cpu      = 75
option_4_scale_down_cpu    = 30
```

| Metric | Value |
|--------|-------|
| **GPU** | 1× NVIDIA L40 (48 GB VRAM) |
| **CPU** | 4 vCPU Intel Xeon |
| **RAM** | 16 GiB |
| **Spot Cost/hr** | $0.35-0.45 (estimate) |
| **Monthly (3×)** | $450-540 (estimate) |
| **Monthly (8×)** | $1,200-1,440 (estimate) |
| **Throughput** | ~2,000 tokens/sec |
| **Availability** | Low-Medium (newer GPU, may have limited Spot in GovCloud) |

**Multi-g6 Scaling**:
The ASG automatically scales across three g6 variants for Spot availability and cost optimization:

| Instance Type | GPUs | Weighted Capacity | Use Case |
|---|---|---|---|
| **g6.xlarge** | 1× L40 | 1 | Primary inference instance |
| **g6.2xlarge** | 2× L40 | 2 | Consolidate 2 tasks on 1 instance |
| **g6.12xlarge** | 8× L40 | 8 | High-capacity instance (if Spot available) |

**How Multi-g6 Scaling Works**:
1. ASG targets desired_capacity units (e.g., 3 units)
2. First tries to launch **g6.xlarge** (1 unit each, lowest cost)
3. If Spot unavailable, tries **g6.2xlarge** (2 units each, half instances but higher per-unit)
4. If all g6 Spot exhausted, falls back to **g4dn.xlarge**, **p3.2xlarge**, or other configured options
5. Seamlessly consolidates capacity across instance sizes

**Example**: desired_capacity=3 weighted units
- **Scenario A** (all g6 available): 3× g6.xlarge (1 GPU each)
- **Scenario B** (g6.xlarge unavailable): 1× g6.2xlarge (2 GPUs) + 1× g6.xlarge (1 GPU)
- **Scenario C** (all g6 Spot exhausted): Falls back to g4dn.xlarge or on-demand

**Recommendation**: Option 4 is optimal for inference workloads. Try g6 first; ASG auto-handles Spot unavailability by scaling across variants.

---

## Auto-Scaling Behavior

### Scale-Up Trigger

```
CPU > 75% for 5 minutes
    ↓
CloudWatch alarm fires
    ↓
ASG scaling policy: +1 instance
    ↓
New instance launches from Spot pool (~2-5 min)
    ↓
Instance boots + installs software (~5 min)
    ↓
Model loads into GPU/CPU (~10-15 min)
    ↓
Health check passes
    ↓
ALB registers instance + sends traffic
    ↓
Total: ~25-30 min before handling requests
```

### Scale-Down Trigger

```
CPU < 30% for 10 minutes (2 eval periods × 5 min each)
    ↓
CloudWatch alarm fires
    ↓
ASG scaling policy: -1 instance
    ↓
ALB marks instance for draining
    ↓
30-second connection drain period
    ↓
Instance terminates
    ↓
Root volume deleted
    ↓
Model cache EBS volume PERSISTS (detached)
    ↓
Next instance reuses cache volume (no re-download)
```

---

## API Interface

### OpenAI-Compatible Completions

```bash
POST https://<ENDPOINT>/v1/completions

{
  "model": "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct",
  "prompt": "def quicksort(arr): # implement quicksort",
  "max_tokens": 512,
  "temperature": 0.7,
  "top_p": 0.9,
  "frequency_penalty": 0,
  "presence_penalty": 0
}
```

### Health Check

```bash
GET https://<ENDPOINT>/health

# Response: {"status": "ok"}
```

---

## Deployment Checklist

- [ ] AWS GovCloud account with VPC
- [ ] 3+ private subnets across AZs
- [ ] 2+ public subnets for ALB
- [ ] SSL certificate in AWS ACM
- [ ] Terraform ≥ 1.5.0 installed
- [ ] AWS CLI configured for GovCloud
- [ ] IAM user with provisioner policy attached
- [ ] GPU quota increased (if using Option 1 or 2)
- [ ] Required data (subnet IDs, certificate ARN)
- [ ] terraform.tfvars file created

---

## Cost Comparison

### Baseline Scenario (3 instances running 24/7)

| Option | Instance | Unit Cost | Monthly |
|--------|----------|-----------|---------|
| **Option 1** | g4dn.xlarge | $0.158/hr | $340 |
| **Option 4** | g6.xlarge | $0.40/hr | $480 (estimate) |
| **Option 2** | p3.2xlarge | $0.918/hr | $1,980 |
| **Option 3** | c6i.4xlarge | $0.340/hr | $1,224 |

### Peak Scenario (8 instances during traffic spike)

| Option | Instances | Unit Cost | Duration | Cost |
|--------|-----------|-----------|----------|------|
| **Option 1** | 8× g4dn | $0.158/hr | 4 hrs/day | $19/day ($570/month) |
| **Option 4** | 8× g6 | $0.40/hr | 4 hrs/day | $48/day ($1,440/month) |
| **Option 2** | 8× p3 | $0.918/hr | 4 hrs/day | $110/day ($3,300/month) |
| **Option 3** | 8× c6i | $0.340/hr | 4 hrs/day | $44/day ($1,320/month) |

### Spot + On-Demand Mixed (20% on-demand for stability)

With 20% on-demand + 80% Spot:
- Baseline cost increases ~16% (on-demand premium)
- Ensures availability during Spot interruptions
- Automatic replacement fallback

**Recommendation**: Start with **Option 1** (most cost-effective). If Spot unavailable, swap to **Option 2** or **Option 3**.

---

## Security

### Network Security

- **IAM Role**: Minimal permissions (EC2, SSM, CloudWatch, S3 for logs)
- **Security Groups**: 
  - Inbound: ALB on port 8000, SSM on port 443
  - Outbound: All (for model download from Hugging Face)
- **IMDSv2**: Enforced (no IMDSv1 fallback)
- **Encryption**: EBS volumes encrypted at rest

### Access Control

- **SSM Session Manager**: No SSH keys required; uses IAM for authentication
- **ALB**: HTTPS only (HTTP redirects to 443)
- **Instance access**: IAM role only (no public IPs, no SSH)

---

## Monitoring

### CloudWatch Metrics

- `CPUUtilization` (instance-level, 5-min aggregation)
- `NetworkIn`, `NetworkOut`
- `EBSVolumeReadBytes`, `EBSVolumeWriteBytes`
- Alarms: CPU high (scale-up), CPU low (scale-down)

### CloudWatch Logs

- Application logs: `/var/log/nemotron-init.log` (initial bootstrap)
- Runtime logs: `docker logs vllm` (inference server)
- Optional: CloudWatch agent for detailed system metrics

### Alarms

```
nemotron-cpu-high-option_1: CPU > 75% → Scale up
nemotron-cpu-low-option_1:  CPU < 30% → Scale down
```

---

## Troubleshooting Guide

### Problem: Instances won't launch

**Cause**: Spot capacity unavailable  
**Fix**: Increase `on_demand_percentage` to 100 or switch options

### Problem: Model takes 30+ minutes to load

**Cause**: First instance downloads 120 GB model from Hugging Face  
**Fix**: Normal; subsequent instances reuse cached volume (~5 min)

### Problem: Health checks failing

**Cause**: vLLM not ready within grace period  
**Fix**: Increase `health_check_grace_period` to 900 (15 min)

### Problem: API responses slow

**Cause**: Instances not fully healthy yet  
**Fix**: Wait for all instances to pass health checks (~45 min after deploy)

### Problem: High cost without traffic

**Cause**: Baseline capacity too high  
**Fix**: Reduce `desired_capacity` or use smaller instance type

---

## GovCloud Considerations

- **Region**: `us-gov-west-1` (only option)
- **Partition**: `arn:aws-us-gov` (not `arn:aws`)
- **GPU Availability**: Limited; Option 3 (CPU) provides fallback
- **VPC Endpoints**: Support for private subnets (EC2, ECR, S3)
- **Certificate**: Must be in same GovCloud region

---

## Next Steps After Deployment

1. **Monitor**: Watch CloudWatch for CPU, latency, error rates
2. **Test**: Load test with concurrent requests to verify scaling
3. **Optimize**: Adjust vLLM parameters (`max_num_seqs`, `gpu_memory_utilization`)
4. **Integrate**: Connect to application via HTTPS endpoint
5. **Automate**: Deploy via CI/CD pipeline (GitHub Actions, AWS CodePipeline)
6. **Secure**: Add API Gateway for authentication, rate limiting, DDoS protection

---

## References

- [Nemotron Model Card](https://huggingface.co/nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct)
- [vLLM Documentation](https://docs.vllm.ai/)
- [AWS Spot Instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html)
- [Auto Scaling Groups](https://docs.aws.amazon.com/autoscaling/ec2/userguide/what-is-amazon-ec2-auto-scaling.html)
- [ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [GovCloud Guide](https://docs.aws.amazon.com/govcloud-us/)
