terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region"
  default     = "us-gov-west-1"
}

variable "asg_name" {
  type        = string
  description = "Auto Scaling Group name"
  default     = "asg-infrastructure-workers"
}

variable "ami_id" {
  type        = string
  description = "AMI ID (must exist in target region)"
}

variable "instance_type" {
  type        = string
  description = "Primary EC2 instance type"
  default     = "t3.medium"
}

variable "instance_type_fallbacks" {
  type        = list(string)
  description = "Fallback instance types for Spot pool diversity"
  default     = []
}

variable "os_type" {
  type        = string
  description = "Operating system: linux or windows"
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], lower(var.os_type))
    error_message = "Must be 'linux' or 'windows'"
  }
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs for ASG (cross-AZ recommended)"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID (auto-detected if omitted)"
  default     = ""
}

variable "asg_min_size" {
  type        = number
  description = "Minimum instances in ASG"
  default     = 2
}

variable "asg_max_size" {
  type        = number
  description = "Maximum instances in ASG"
  default     = 6
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired number of instances"
  default     = 3
}

variable "spot_instance_pools" {
  type        = number
  description = "Number of Spot capacity pools"
  default     = 3
}

variable "spot_allocation_strategy" {
  type        = string
  description = "Spot allocation strategy: capacity-optimized, lowest-price, diversified"
  default     = "capacity-optimized"
}

variable "spot_max_price" {
  type        = string
  description = "Max Spot bid (empty = on-demand price cap)"
  default     = ""
}

variable "on_demand_percentage" {
  type        = number
  description = "Percentage of on-demand instances (0-100)"
  default     = 20

  validation {
    condition     = var.on_demand_percentage >= 0 && var.on_demand_percentage <= 100
    error_message = "Must be between 0 and 100"
  }
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name"
  default     = ""
}

variable "key_name" {
  type        = string
  description = "EC2 key pair (optional, use SSM instead)"
  default     = ""
}

variable "associate_public_ip" {
  type        = bool
  description = "Assign public IP (set true if no NAT)"
  default     = false
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root EBS volume size"
  default     = 50
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS volume type"
  default     = "gp3"
}

variable "root_volume_iops" {
  type        = number
  description = "IOPS for gp3"
  default     = 3000
}

variable "enable_docker" {
  type        = bool
  description = "Install Docker daemon"
  default     = true
}

variable "enable_ssm" {
  type        = bool
  description = "Enable Systems Manager agent"
  default     = true
}

variable "enable_cloudwatch_detailed" {
  type        = bool
  description = "Enable detailed CloudWatch monitoring"
  default     = true
}

variable "https_proxy" {
  type        = string
  description = "HTTPS proxy URL"
  default     = ""
}

variable "http_proxy" {
  type        = string
  description = "HTTP proxy URL"
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "NO_PROXY list"
  default     = "169.254.169.254,169.254.170.2,localhost,127.0.0.1"
}

variable "enable_alb" {
  type        = bool
  description = "Create ALB for instances"
  default     = false
}

variable "alb_subnets" {
  type        = list(string)
  description = "Public subnets for ALB"
  default     = []
}

variable "alb_security_groups" {
  type        = list(string)
  description = "Security groups for ALB"
  default     = []
}

variable "enable_target_group" {
  type        = bool
  description = "Register instances with target group"
  default     = false
}

variable "target_group_arn" {
  type        = string
  description = "Target group ARN for load balancer"
  default     = ""
}

variable "environment" {
  type        = string
  description = "Environment tag"
  default     = "production"
}

variable "project" {
  type        = string
  description = "Project tag"
  default     = "infrastructure"
}

variable "cost_center" {
  type        = string
  description = "Cost center tag"
  default     = "engineering"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional resource tags"
  default     = {}
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_ami" "selected" {
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
  owners = ["self", "amazon", "aws-marketplace"]
}

data "aws_subnet" "first" {
  id = var.subnet_ids[0]
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  is_windows = lower(var.os_type) == "windows"
  vpc_id     = length(trimspace(var.vpc_id)) > 0 ? var.vpc_id : data.aws_subnet.first.vpc_id

  common_tags = merge(var.additional_tags, {
    Name               = var.asg_name
    Environment        = var.environment
    Project            = var.project
    CostCenter         = var.cost_center
    ManagedBy          = "terraform"
  })

  instance_types = concat([var.instance_type], var.instance_type_fallbacks)

  # Linux user-data
  linux_userdata = base64encode(<<-USERDATA
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee /var/log/user-data.log | logger -t user-data) 2>&1

    echo "[user-data] Infrastructure bootstrap starting"

    # Proxy settings
    %{if length(trimspace(var.https_proxy)) > 0}
    export HTTPS_PROXY="${var.https_proxy}"
    export https_proxy="${var.https_proxy}"
    %{endif}
    %{if length(trimspace(var.http_proxy)) > 0}
    export HTTP_PROXY="${var.http_proxy}"
    export http_proxy="${var.http_proxy}"
    %{endif}

    # Base packages
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y --no-install-recommends curl wget git ca-certificates >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl wget git ca-certificates >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl wget git ca-certificates >/dev/null 2>&1
    fi

    # Docker
    %{if var.enable_docker}
    if ! command -v docker >/dev/null 2>&1; then
      curl -fsSL https://get.docker.com | bash >/dev/null 2>&1 || true
    fi
    %{endif}

    # Systems Manager agent
    %{if var.enable_ssm}
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y amazon-ssm-agent >/dev/null 2>&1 || true
      systemctl enable amazon-ssm-agent 2>/dev/null || true
      systemctl start amazon-ssm-agent 2>/dev/null || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y amazon-ssm-agent >/dev/null 2>&1 || true
      systemctl enable amazon-ssm-agent 2>/dev/null || true
      systemctl start amazon-ssm-agent 2>/dev/null || true
    fi
    %{endif}

    # CloudWatch agent (optional detailed monitoring)
    %{if var.enable_cloudwatch_detailed}
    # Placeholder: install and configure CloudWatch agent
    # wget https://s3.amazonaws.com/amazoncloudwatch-agent-us-gov-west-1/linux/amd64/latest/amazon-cloudwatch-agent.rpm
    %{endif}

    echo "[user-data] Bootstrap complete"
  USERDATA
  )

  # Windows user-data
  windows_userdata = base64encode(<<-WINUD
    <powershell>
    Set-ExecutionPolicy Bypass -Scope Process -Force

    Write-Host "[user-data] Infrastructure bootstrap starting"

    # Proxy settings
    %{if length(trimspace(var.https_proxy)) > 0}
    [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", "${var.https_proxy}", "Machine")
    %{endif}
    %{if length(trimspace(var.http_proxy)) > 0}
    [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", "${var.http_proxy}", "Machine")
    %{endif}

    # Docker
    %{if var.enable_docker}
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
      Install-Package -Name Docker -ProviderName DockerProvider -Force -WarningAction SilentlyContinue | Out-Null
    }
    %{endif}

    # Systems Manager agent
    %{if var.enable_ssm}
    $ssmAgent = Get-Service -Name AmazonSSMAgent -ErrorAction SilentlyContinue
    if ($null -eq $ssmAgent) {
      # SSM agent pre-installed on AWS AMIs; just ensure it's running
      Start-Service -Name AmazonSSMAgent -ErrorAction SilentlyContinue
    }
    %{endif}

    Write-Host "[user-data] Bootstrap complete"
    </powershell>
  WINUD
  )
}

# ── Security Group ────────────────────────────────────────────────────────────

resource "aws_security_group" "asg_instances" {
  name        = "${var.asg_name}-sg"
  description = "Security group for ASG instances"
  vpc_id      = local.vpc_id

  # Inbound: Allow from self (inter-instance communication)
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    self            = true
    description     = "Allow inter-instance communication"
  }

  # Egress: Allow all
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, {
    Name = "${var.asg_name}-sg"
  })
}

# ── Launch Template ───────────────────────────────────────────────────────────

resource "aws_launch_template" "asg_instances" {
  name_prefix   = "${var.asg_name}-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.asg_instances.id]

  # t-series burstable instances
  credit_specification {
    cpu_credits = "unlimited"
  }

  # Root volume
  block_device_mappings {
    device_name = data.aws_ami.selected.root_device_name

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = var.root_volume_type
      iops                  = var.root_volume_type == "gp3" ? var.root_volume_iops : null
      delete_on_termination = true
      encrypted             = true
    }
  }

  # IMDSv2 enforcement
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Monitoring
  monitoring {
    enabled = var.enable_cloudwatch_detailed
  }

  user_data = local.is_windows ? local.windows_userdata : local.linux_userdata

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "infrastructure" {
  name              = var.asg_name
  vpc_zone_identifier = var.subnet_ids

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Load balancer target group (optional)
  dynamic "target_group_arns" {
    for_each = var.enable_target_group && length(trimspace(var.target_group_arn)) > 0 ? [var.target_group_arn] : []
    content {
      arn = target_group_arns.value
    }
  }

  mixed_instances_policy {
    instances_distribution {
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_instance_pools                       = var.spot_instance_pools
      spot_allocation_strategy                  = var.spot_allocation_strategy
      spot_max_price                            = length(trimspace(var.spot_max_price)) > 0 ? var.spot_max_price : ""
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.asg_instances.id
        version            = "$Latest"
      }

      dynamic "overrides" {
        for_each = local.instance_types
        content {
          instance_type = overrides.value
        }
      }
    }
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  tag {
    key                 = "Name"
    value               = var.asg_name
    propagate_to_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_to_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_launch_template.asg_instances]
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.infrastructure.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.infrastructure.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.asg_instances.id
}

output "launch_template_version" {
  description = "Launch template version"
  value       = aws_launch_template.asg_instances.latest_version_number
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.asg_instances.id
}

output "instance_count" {
  description = "Desired capacity"
  value       = var.asg_desired_capacity
}
