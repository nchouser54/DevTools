# Quick Start: GovCloud ASG Spot Infrastructure

Standalone Auto Scaling Group with Spot Instances for infrastructure workloads (CI/CD runners, application servers, worker pools).

## 5-Minute Setup

### 1. Get Prerequisites

```bash
# Get GovCloud AMI
aws ec2 describe-images --region us-gov-west-1 --owners amazon \
  --filters "Name=name,Values=ubuntu/images/*22.04*" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId'

# Get subnets (ideally across AZs)
aws ec2 describe-subnets --region us-gov-west-1 \
  --filters "Name=vpc-id,Values=vpc-xxxxx" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone]'
```

### 2. Create Terraform Config

```bash
cd templates/govcloud-asg-spot-infrastructure/terraform

# Create terraform.tfvars
cat > terraform.tfvars <<EOF
aws_region = "us-gov-west-1"
ami_id = "ami-0abc123def456789"
subnet_ids = ["subnet-xxxxx", "subnet-yyyyy"]
vpc_id = "vpc-xxxxx"

asg_name = "asg-ci-runners"
asg_min_size = 2
asg_max_size = 6
asg_desired_capacity = 3

instance_type = "t3.large"
on_demand_percentage = 20
enable_docker = true
enable_ssm = true
EOF
```

### 3. Deploy

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

### 4. Verify

```bash
# Check ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names asg-ci-runners \
  --region us-gov-west-1

# Check instances
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=asg-ci-runners" \
  --region us-gov-west-1 \
  --query 'Reservations[].Instances[].[InstanceId,InstanceLifecycle,State.Name]'
```

## Access Instances

### Systems Manager (No SSH key needed)

```bash
# Interactive shell
aws ssm start-session --target i-xyz123 --region us-gov-west-1

# Run command on all
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=['docker ps']" \
  --targets "Key=tag:aws:autoscaling:groupName,Values=asg-ci-runners" \
  --region us-gov-west-1
```

### SSH (With EC2 key pair)

```bash
# Get instance IPs
aws ec2 describe-instances \
  --filters "Name=tag:aws:autoscaling:groupName,Values=asg-ci-runners" \
  --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId]' \
  --region us-gov-west-1

# SSH
ssh -i my-key.pem ec2-user@10.0.1.42
```

## Cost Estimate

3× t3.medium Spot in GovCloud:
- Monthly: ~$30 (3 × $0.024/hr × 176 hrs + 20% on-demand fallback)
- Annual: ~$360

6× t3.medium would be ~$60/month.

## Examples

### CI/CD Runners (GitHub Actions)

```bash
instance_type = "t3.large"
asg_min_size = 2
asg_max_size = 10
asg_desired_capacity = 3

# Add to user-data:
# curl -fsSL https://get.github.com | bash
# ./config.sh --url https://github.com/org/repo --token XXXXX
```

### Application Servers (Load-balanced)

```bash
instance_type = "m5.xlarge"
asg_min_size = 3
asg_max_size = 6
asg_desired_capacity = 3
enable_alb = true

# Add instance profile for app permissions (S3, RDS, etc.)
```

### Worker Pool (Batch Jobs)

```bash
instance_type = "c5.2xlarge"
asg_min_size = 2
asg_max_size = 20
on_demand_percentage = 50

# Add to user-data:
# subscribe to job queue (SQS, RabbitMQ, etc.)
```

## Cleanup

```bash
terraform destroy -var-file=terraform.tfvars
```

See README.md for full documentation.
