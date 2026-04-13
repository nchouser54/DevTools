# Quick Start: Nemotron 3 SWE Inference API

Deploy a scalable Nemotron 3 inference cluster in 5 steps.

## Step 1: Gather AWS Information (5 minutes)

Get your VPC subnet and certificate information:

```bash
# List subnets in your VPC
REGION=us-gov-west-1
VPC_ID=vpc-xxxxx

# Get 3+ private subnets (for instances)
aws ec2 describe-subnets \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
           "Name=tag:Type,Values=Private" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
  --output text

# Get 2+ public subnets (for ALB)
aws ec2 describe-subnets \
  --region $REGION \
  --filters "Name=vpc-id,Values=$VPC_ID" \
           "Name=tag:Type,Values=Public" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]' \
  --output text

# Get SSL certificate ARN
aws acm list-certificates \
  --region $REGION \
  --query 'CertificateSummaryList[0].[CertificateArn,DomainName]' \
  --output text
```

**Expected Output**:
```
subnet-abc123  us-gov-west-1a
subnet-def456  us-gov-west-1b
subnet-ghi789  us-gov-west-1c

arn:aws-us-gov:acm:us-gov-west-1:123456789:certificate/abc123
```

## Step 2: Create Terraform Variables File (2 minutes)

```bash
cd terraform
cp ../terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region = "us-gov-west-1"

# Your VPC
vpc_id = "vpc-xxxxx"

# 3+ private subnets (separate with comma)
subnet_ids = ["subnet-abc123", "subnet-def456", "subnet-ghi789"]

# 2+ public subnets for ALB
alb_subnets = ["subnet-public-123", "subnet-public-456"]

# Your SSL certificate
certificate_arn = "arn:aws-us-gov:acm:us-gov-west-1:123456789:certificate/abc123"

# Choose ONE option:
option_1_enabled = false   # g4dn.xlarge (T4 GPU)
option_2_enabled = false   # p3.2xlarge (V100 GPU)
option_3_enabled = false   # c6i.4xlarge (CPU-only)
option_4_enabled = true    # g6.xlarge family (L40 GPU) - RECOMMENDED default

# Common settings
on_demand_percentage = 20  # 20% on-demand, 80% Spot
spot_allocation_strategy = "capacity-optimized"

common_tags = {
  Environment = "production"
  Project     = "nemotron-swe"
  Team        = "ai-platform"
}
```

## Step 3: Initialize and Plan (2 minutes)

```bash
terraform init
terraform plan -var-file=terraform.tfvars -out=tfplan
```

Review the plan output. Should show:
- 1 ALB
- 1 Target Group
- 1 Security Group (instances) + 1 (ALB)
- 1 Launch Template
- 1 Auto Scaling Group
- 2 CloudWatch Alarms

## Step 4: Deploy (1 minute)

```bash
terraform apply tfplan
```

**Output**:
```
Apply complete! Resources created.

Outputs:
alb_dns_name = "nemr-abc123.elb.us-gov-west-1.amazonaws.com"
asg_name = "asg-nemotron-option_1-abc123"
active_option = "option_1"
api_endpoint = "https://nemr-abc123.elb.us-gov-west-1.amazonaws.com/v1/completions"
```

## Step 5: Wait for Instances (45 minutes)

Instances will:
1. **Launch** (2-5 min): Spot instance provisioning
2. **Boot** (3-5 min): OS startup, Docker install
3. **Download** (10-20 min): Nemotron model (~120 GB)
4. **Load** (10-15 min): Model into GPU VRAM
5. **Health check** (2-5 min): Register with ALB

### Monitor Progress

```bash
# Check instances
aws ec2 describe-instances \
  --region us-gov-west-1 \
  --filters "Name=tag:Name,Values=nemotron-instance" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,LaunchTime]'

# Check instance logs
aws ec2 get-console-output --instance-id i-xyz123 --region us-gov-west-1

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-gov-west-1 \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]'
```

### SSH into Instance (Troubleshooting)

```bash
# Get an instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-gov-west-1 \
  --filters "Name=tag:Name,Values=nemotron-instance" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Start SSM session
aws ssm start-session --target $INSTANCE_ID --region us-gov-west-1

# Inside instance:
tail -f /var/log/nemotron-init.log       # Watch initialization
docker logs vllm                          # vLLM logs
docker ps                                 # Check containers
```

---

## Test API (After Healthy)

Once all instances are healthy, test the API:

```bash
ENDPOINT=$(terraform output -raw alb_dns_name)

# Health check
curl https://$ENDPOINT/health

# Inference request
curl -X POST https://$ENDPOINT/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct",
    "prompt": "def quicksort(arr):\n    # Implement quicksort",
    "max_tokens": 256,
    "temperature": 0.7
  }' | jq .
```

**Expected Response**:
```json
{
  "id": "...",
  "object": "text_completion",
  "created": 1681234567,
  "model": "...",
  "choices": [
    {
      "text": "quicksort is a sorting algorithm that works by...",
      "index": 0,
      "finish_reason": "length"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 256,
    "total_tokens": 276
  }
}
```

---

## Monitor Auto-Scaling

```bash
# Watch scaling activity
watch -n 5 'aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name $(terraform output -raw asg_name) \
  --region us-gov-west-1 \
  --max-records 5 \
  --query "Activities[*].[StartTime,Description]" --output text'

# Check current capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names $(terraform output -raw asg_name) \
  --region us-gov-west-1 \
  --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,Instances[].InstanceId]'

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-names $(terraform output -raw cloudwatch_scale_up_alarm) \
  --region us-gov-west-1 \
  --query 'MetricAlarms[*].[AlarmName,StateValue]'
```

---

## Troubleshooting

### Instances won't launch / Status stuck in "pending"

**Check Spot availability**:
```bash
aws ec2 describe-spot-price-history \
  --instance-types g4dn.xlarge \
  --region us-gov-west-1 \
  --max-results 5
```

If Spot is unavailable, increase `on_demand_percentage` to 100:
```bash
terraform apply -var on_demand_percentage=100
```

Or switch to a different option:
```bash
terraform apply \
  -var option_1_enabled=false \
  -var option_2_enabled=true
```

### Model download stuck

Model is 120 GB. First instance takes 15-20 min to download. Check:
```bash
INSTANCE_ID=i-xyz123
aws ssm start-session --target $INSTANCE_ID
# Inside instance:
tail -f /var/log/nemotron-init.log
docker logs vllm
df -h /mnt/model-cache  # Check disk space
```

### Health checks failing

Instances need 10 minutes after launch for model loading. Wait for health check grace period:
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Description]'

# If stuck, check instance logs
aws ec2 get-console-output --instance-id i-xyz123 | tail -50
```

### Cost too high

Check your actual instance types:
```bash
aws ec2 describe-instances \
  --region us-gov-west-1 \
  --filters "Name=tag:Name,Values=nemotron-instance" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,SpotInstanceRequestId]'
```

If using p3.2xlarge (expensive), switch to g4dn.xlarge:
```bash
terraform apply \
  -var option_1_enabled=true \
  -var option_2_enabled=false
```

---

## Clean Up

```bash
terraform destroy
```

This will:
- Terminate all instances
- Delete ASG
- Delete ALB
- Delete security groups
- **Keep** model cache EBS volume (to avoid accidental deletion)

To also delete the model cache:
```bash
# Find the volume
aws ec2 describe-volumes \
  --region us-gov-west-1 \
  --filters "Name=tag:Name,Values=nemotron-volume" \
  --query 'Volumes[*].[VolumeId,State]'

# Delete it
aws ec2 delete-volume --volume-id vol-xyz123 --region us-gov-west-1
```

---

## Next Steps

- **Monitoring**: Set up CloudWatch dashboard for throughput, latency, cost
- **API Gateway**: Add AWS API Gateway for authentication, rate limiting
- **Autoscaling**: Adjust CPU thresholds based on actual workload
- **Multi-model**: Add endpoints for different model variants
- **Logging**: Send logs to CloudWatch Logs or S3 for analysis
