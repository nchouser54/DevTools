# Nemotron 3 SWE Inference API Cluster

Scalable inference API endpoint serving **NVIDIA Nemotron 3 Super Agentic SWE** on AWS GovCloud using **Spot Instances with Auto-Scaling**.

## Features

- **Multi-Option GPU/CPU**: Choose between g4dn.xlarge (T4), p3.2xlarge (V100), or c6i.4xlarge (CPU)
- **Spot Instances**: 70% cost savings with automatic fallback to on-demand
- **Auto-Scaling**: Dynamically scale 2-8 instances based on CPU utilization
- **ALB Front-End**: HTTPS endpoint with health checks and connection draining
- **Model Caching**: Persistent EBS volume survives instance termination
- **vLLM Inference**: High-throughput OpenAI-compatible API
- **GovCloud Optimized**: IMDSv2, partition ARNs, private subnets supported

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Application Load Balancer (HTTPS)               │
│ nemotron-swe-api.*.elb.us-gov-west-1.amazonaws │
└──────────────────┬──────────────────────────────┘
                   │ 443
    ┌──────────────┼──────────────┐
    ↓              ↓              ↓
┌─────────┐  ┌─────────┐  ┌─────────┐
│Instance │  │Instance │  │Instance │
│(Spot)   │  │(Spot)   │  │(Spot)   │
│vLLM     │  │vLLM     │  │vLLM     │
│Nemotron │  │Nemotron │  │Nemotron │
└─────────┘  └─────────┘  └─────────┘

ASG Auto-Scaling: min=2, max=8, desired=3
├─ Scales up when CPU > 75% 
├─ Scales down when CPU < 30%
└─ Spot interruption → auto-replace
```

## Quick Start

### 1. Prerequisites

Ensure you have:
- AWS GovCloud account with VPC and subnets
- SSL certificate in ACM (for HTTPS)
- AMI with GPU drivers (for options 1 & 2)
- Terraform ≥ 1.5.0

### 2. Get Information

```bash
# Get subnets (private, across AZs)
aws ec2 describe-subnets --region us-gov-west-1 \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]'

# Get public subnets (for ALB)
aws ec2 describe-subnets --region us-gov-west-1 \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
           "Name=map-public-ip-on-launch,Values=true" \
  --query 'Subnets[*].[SubnetId]'

# Get SSL certificate ARN
aws acm list-certificates --region us-gov-west-1 \
  --query 'CertificateSummaryList[0].CertificateArn'
```

### 3. Configure

```bash
cp .env.example terraform.tfvars

# Edit terraform.tfvars:
# - Set SUBNET_IDS (3 subnets across AZs)
# - Set VPC_ID
# - Set ALB_SUBNETS (public subnets)
# - Set CERTIFICATE_ARN
# - Choose option: NEMOTRON_OPTION=option_1, option_2, or option_3
```

### 4. Deploy

```bash
cd terraform
terraform init
terraform apply -var-file=../terraform.tfvars
```

### 5. Wait for Instances (~45 minutes)

Instances will:
1. Launch from Spot pool (~5 min)
2. Boot and install Docker (~5 min)
3. Download Nemotron model (~15-20 min, depends on bandwidth)
4. Load model into GPU/CPU (~10 min)
5. Pass health checks and register with ALB (~5 min)

### 6. Test API

```bash
# Get endpoint
ENDPOINT=$(terraform output -raw alb_dns_name)

# Test inference
curl -X POST https://$ENDPOINT/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct",
    "prompt": "def quicksort(arr): # implement quicksort algorithm",
    "max_tokens": 512,
    "temperature": 0.7
  }'
```

## Configuration Options

### Option 1: g4dn.xlarge (T4 GPU) - Fastest

**Best for**: Maximum throughput, cost per token optimization

```hcl
NEMOTRON_OPTION=option_1
OPTION_1_ENABLED=true
OPTION_1_MIN_SIZE=2
OPTION_1_MAX_SIZE=8
OPTION_1_DESIRED_CAPACITY=3
```

**Specs**:
- GPU: 1× NVIDIA T4 (16 GB VRAM)
- CPU: 4 vCPU Intel Xeon
- RAM: 16 GiB
- Throughput: ~1,500 tokens/sec
- Spot cost: $0.158/hr
- 3-instance baseline: $340/month

**Availability**: Low (Spot scarcity in GovCloud)

---

### Option 2: p3.2xlarge (V100 GPU) - Balanced

**Best for**: Good throughput + moderate availability

```hcl
NEMOTRON_OPTION=option_2
OPTION_2_ENABLED=true
OPTION_2_MIN_SIZE=2
OPTION_2_MAX_SIZE=6
OPTION_2_DESIRED_CAPACITY=3
```

**Specs**:
- GPU: 1× NVIDIA V100 (32 GB VRAM)
- CPU: 8 vCPU Intel Xeon
- RAM: 61 GiB
- Throughput: ~2,500 tokens/sec
- Spot cost: $0.918/hr
- 3-instance baseline: $1,980/month

**Availability**: Medium

---

### Option 3: c6i.4xlarge (CPU-only) - Fallback

**Best for**: Always-available fallback, low cost (very slow)

```hcl
NEMOTRON_OPTION=option_3
OPTION_3_ENABLED=true
OPTION_3_MIN_SIZE=3
OPTION_3_MAX_SIZE=20
OPTION_3_DESIRED_CAPACITY=5
```

**Specs**:
- GPU: None (CPU inference via llama.cpp or Ollama)
- CPU: 16 vCPU Intel Xeon
- RAM: 32 GiB
- Throughput: ~250-300 tokens/sec (5-6× slower than T4)
- Spot cost: $0.34/hr
- 5-instance baseline: $1,224/month

**Availability**: High (always available)

---

### Option 4: g6.xlarge (L40 GPU) - Best for Inference

**Best for**: Optimal inference performance, best L40 GPU for inference workloads

```hcl
NEMOTRON_OPTION=option_4
OPTION_4_ENABLED=true
OPTION_4_MIN_SIZE=2
OPTION_4_MAX_SIZE=8
OPTION_4_DESIRED_CAPACITY=3
```

**Specs** (primary g6.xlarge):
- GPU: 1× NVIDIA L40 (48 GB VRAM) - optimized for inference
- CPU: 4 vCPU Intel Xeon
- RAM: 16 GiB
- Throughput: ~2,000 tokens/sec (better than T4, similar to V100)
- Spot cost: ~$0.35-0.45/hr (estimate)
- 3-instance baseline: ~$450-540/month (estimate)

**Multi-g6 Scaling**:
The ASG can scale across **three g6 variants** for cost optimization and Spot availability:

| Instance | GPUs | Weighted Cap | Use Case |
|----------|------|---|---|
| **g6.xlarge** | 1× L40 | 1 | Primary inference instance |
| **g6.2xlarge** | 2× L40 | 2 | Consolidate 2 tasks on 1 instance (cost effective) |
| **g6.12xlarge** | 8× L40 | 8 | High-capacity batches, if Spot available |

When you enable Option 4, the ASG will:
1. Try to launch g6.xlarge (lowest cost per unit)
2. If unavailable on Spot, try g6.2xlarge (half the instances needed but higher per-unit cost)
3. If all g6 Spot exhausted, fall back to g4dn.xlarge or p3.2xlarge (other options as override)

**Example**: If desired_capacity=3 (weighted units):
- Ideal: 3× g6.xlarge (1 GPU each)
- Fallback 1: 2× g6.2xlarge (2 GPUs each) + 1× g6.xlarge
- Fallback 2: 1× g6.12xlarge (8 GPUs, partial utilization)

**Availability**: Low-Medium in GovCloud (newer GPU type, may have limited Spot)

**Recommendation**: Try Option 4 (g6.xlarge) first for best cost/perf. ASG auto-scales across g6 variants. If all g6 Spot exhausted, falls back to Option 1 (g4dn.xlarge).

---

## Auto-Scaling Behavior

The cluster automatically scales based on **CPU utilization**:

### Scale Up (Add Instance)

Triggered when: CPU > 75% for 5 minutes
- ASG launches new instance from Spot pool
- Instance bootstrap runs (25-30 min)
- Once healthy, receives traffic from ALB
- ASG can scale up to `max_size` (8 for option 1)

### Scale Down (Remove Instance)

Triggered when: CPU < 30% for 10 minutes
- ASG marks instance for termination
- ALB drains connections (30 sec timeout)
- Instance shuts down gracefully
- ASG removes from group
- Model cache EBS persists (reused by future instances)

### Spot Interruption

If AWS interrupts a Spot instance for capacity:
- Instance receives 2-minute termination notice
- ALB drains connections
- ASG auto-launches replacement instance
- Replacement becomes healthy, joins ALB

---

## Cost Comparison

| Option | Per Instance/Hr | 3× Baseline | 8× Peak | Throughput | Availability |
|--------|---|---|---|---|---|
| **g4dn.xlarge** | $0.158 | $340/mo | $907/mo | 1.5K tok/s | Low |
| **g6.xlarge** | $0.35-0.45 | $450-540/mo | $1,200-1,440/mo | 2.0K tok/s | Low-Med |
| **p3.2xlarge** | $0.918 | $1,980/mo | $5,286/mo | 2.5K tok/s | Medium |
| **c6i.4xlarge** | $0.34 | $1,224/mo | $4,080/mo | 250 tok/s | High |

**Recommendation**: Try **Option 4 (g6.xlarge)** first for best inference performance. If Spot unavailable in GovCloud, fall back to **Option 1 (g4dn.xlarge)** for cost-effectiveness.

---

## API Endpoints

### OpenAI-Compatible API (vLLM)

```bash
POST https://$ENDPOINT/v1/completions

{
  "model": "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct",
  "prompt": "Your prompt here",
  "max_tokens": 2048,
  "temperature": 0.7
}
```

### Health Check

```bash
GET https://$ENDPOINT/health

# Response: {"status": "ok"}
```

---

## Monitoring

### CloudWatch Metrics

Default CloudWatch metrics:
- `CPUUtilization` (triggers scaling alarms)
- `NetworkIn`, `NetworkOut`
- Custom metric: `VLLMThroughput` (if configured)

### View Scaling Activity

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name asg-nemotron-option_1 \
  --region us-gov-west-1 \
  --max-records 10
```

### Check Instance Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-gov-west-1
```

---

## Troubleshooting

### Instances won't launch

**Check**: Spot availability for selected instance type
```bash
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --region us-gov-west-1 \
  --max-results 5
```

**Fix**: Change `NEMOTRON_OPTION` to a different option or increase `ON_DEMAND_PERCENTAGE`

### Model loading slow

**Check**: Instance logs
```bash
aws ssm start-session --target i-xyz123 --region us-gov-west-1
tail -f /var/log/nemotron-init.log
```

**Typical**: First instance takes 20-30 min to download model; subsequent instances reuse cached volume

### Health checks failing

**Check**: Target group health
```bash
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn)
```

**Check**: Instance SSH logs
```bash
aws ec2 get-console-output --instance-id i-xyz123 --region us-gov-west-1
```

---

## Cleanup

```bash
terraform destroy
```

This terminates:
- All instances
- ASG
- ALB
- Model cache EBS volumes
- All associated resources

---

## GovCloud Notes

- **Region**: us-gov-west-1 only
- **IMDSv2**: Enforced (security best practice)
- **Vpc Endpoints**: Required for private subnets (EC2, ECR, S3)
- **GPU quotas**: Request AWS to increase if needed
- **Partition ARNs**: Use `arn:aws-us-gov` (handled automatically)

---

## Cost Optimization Tips

1. **Use Spot with on-demand fallback**: Default 20% on-demand protects against Spot unavailability
2. **Monitor actual usage**: Use CloudWatch to verify auto-scaling thresholds match workload
3. **Pre-cache model**: Keep baseline capacity high enough to avoid prolonged scaling delays
4. **Graceful shutdown**: Configure connection draining (30 sec) for in-flight requests
5. **GPU instance selection**: Option 1 (T4) is best cost/throughput; Option 2 (V100) for stability

---

## References

- [vLLM Documentation](https://docs.vllm.ai/)
- [Nemotron Model Card](https://huggingface.co/nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct)
- [AWS ASG Scaling Policies](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html)
- [Spot Instance Interruptions](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html)
