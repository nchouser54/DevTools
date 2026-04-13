terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Security Groups
resource "aws_security_group" "nemotron_instances" {
  name_prefix = "nemotron-instances-"
  description = "Security group for Nemotron inference instances"
  vpc_id      = var.vpc_id

  # Ingress from ALB
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    { Name = "nemotron-instances" }
  )
}

resource "aws_security_group" "alb" {
  name_prefix = "nemotron-alb-"
  description = "Security group for Nemotron ALB"
  vpc_id      = var.vpc_id

  # HTTPS ingress
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # HTTP redirect
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP (redirect to HTTPS)"
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.common_tags,
    { Name = "nemotron-alb" }
  )
}

# IAM Role for EC2 instances
resource "aws_iam_role" "nemotron_instance_role" {
  name_prefix = "nemotron-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.common_tags
}

# IAM instance profile
resource "aws_iam_instance_profile" "nemotron" {
  name_prefix = "nemotron-"
  role        = aws_iam_role.nemotron_instance_role.name
}

# IAM Policy: SSM + CloudWatch + ECR + S3
resource "aws_iam_role_policy" "nemotron_instance_policy" {
  name_prefix = "nemotron-"
  role        = aws_iam_role.nemotron_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # SSM Session Manager
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:UpdateInstanceInformation",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply"
        ]
        Resource = "*"
      },
      # CloudWatch
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      # ECR (pull Nemotron model)
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      # S3 (optional: model checkpoints, logs)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = "*"
      }
    ]
  })
}

# Data source: Latest optimized AMI for GovCloud
# Using Ubuntu 22.04 LTS with GPU drivers pre-installed
data "aws_ami" "nemotron_ami" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# User data script for GPU instances (Option 1 & 2)
locals {
  user_data_gpu = base64encode(templatefile("${path.module}/user-data-gpu.sh", {
    model_id              = var.nemotron_model_id
    vllm_max_model_len    = var.vllm_max_model_len
    vllm_max_num_seqs     = var.vllm_max_num_seqs
    vllm_gpu_memory_util  = var.vllm_gpu_memory_utilization
    model_cache_mount     = "/mnt/model-cache"
    enable_detailed_logs  = var.enable_detailed_logging
  }))

  user_data_cpu = base64encode(templatefile("${path.module}/user-data-cpu.sh", {
    model_id              = var.nemotron_model_id
    vllm_max_model_len    = var.vllm_max_model_len
    vllm_max_num_seqs     = var.vllm_max_num_seqs
    model_cache_mount     = "/mnt/model-cache"
    enable_detailed_logs  = var.enable_detailed_logging
  }))

  enabled_options = compact([
    var.option_1_enabled ? "option_1" : "",
    var.option_2_enabled ? "option_2" : "",
    var.option_3_enabled ? "option_3" : "",
    var.option_4_enabled ? "option_4" : ""
  ])

  enabled_option_count = length(local.enabled_options)

  # Determine active option
  active_option = try(local.enabled_options[0], "option_4")

  # Map option to instance type
  instance_type_map = {
    "option_1" = "g4dn.xlarge"
    "option_2" = "p3.2xlarge"
    "option_3" = "c6i.4xlarge"
    "option_4" = "g6.xlarge"
  }

  # Map option to user data
  user_data_map = {
    "option_1" = local.user_data_gpu
    "option_2" = local.user_data_gpu
    "option_3" = local.user_data_cpu
    "option_4" = local.user_data_gpu
  }

  # Get active instance type
  active_instance_type = local.instance_type_map[local.active_option]
  active_user_data     = local.user_data_map[local.active_option]

  option_instance_overrides = {
    "option_1" = [
      {
        instance_type     = "g4dn.xlarge"
        weighted_capacity = "1"
      }
    ]
    "option_2" = [
      {
        instance_type     = "p3.2xlarge"
        weighted_capacity = "1"
      }
    ]
    "option_3" = [
      {
        instance_type     = "c6i.4xlarge"
        weighted_capacity = "1"
      }
    ]
    "option_4" = [
      {
        instance_type     = "g6.xlarge"
        weighted_capacity = "1"
      },
      {
        instance_type     = "g6.2xlarge"
        weighted_capacity = "2"
      },
      {
        instance_type     = "g6.12xlarge"
        weighted_capacity = "8"
      }
    ]
  }

  active_instance_overrides = lookup(local.option_instance_overrides, local.active_option, local.option_instance_overrides["option_4"])

  # Map option to scaling parameters
  option_config = {
    "option_1" = {
      min_size                      = var.option_1_min_size
      max_size                      = var.option_1_max_size
      desired_capacity              = var.option_1_desired_capacity
      scale_up_cpu                  = var.option_1_scale_up_cpu
      scale_down_cpu                = var.option_1_scale_down_cpu
      health_check_grace_period     = 600 # 10 min for GPU model loading
      enable_capacity_rebalance     = true
    }
    "option_2" = {
      min_size                      = var.option_2_min_size
      max_size                      = var.option_2_max_size
      desired_capacity              = var.option_2_desired_capacity
      scale_up_cpu                  = var.option_2_scale_up_cpu
      scale_down_cpu                = var.option_2_scale_down_cpu
      health_check_grace_period     = 600
      enable_capacity_rebalance     = true
    }
    "option_3" = {
      min_size                      = var.option_3_min_size
      max_size                      = var.option_3_max_size
      desired_capacity              = var.option_3_desired_capacity
      scale_up_cpu                  = var.option_3_scale_up_cpu
      scale_down_cpu                = var.option_3_scale_down_cpu
      health_check_grace_period     = 300 # 5 min for CPU warmup
      enable_capacity_rebalance     = false
    }
    "option_4" = {
      min_size                      = var.option_4_min_size
      max_size                      = var.option_4_max_size
      desired_capacity              = var.option_4_desired_capacity
      scale_up_cpu                  = var.option_4_scale_up_cpu
      scale_down_cpu                = var.option_4_scale_down_cpu
      health_check_grace_period     = 600 # 10 min for GPU model loading
      enable_capacity_rebalance     = true
    }
  }

  active_config = local.option_config[local.active_option]
}

# Launch Template
resource "aws_launch_template" "nemotron" {
  name_prefix   = "nemotron-"
  image_id      = data.aws_ami.nemotron_ami.id
  instance_type = local.active_instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.nemotron.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = var.enable_cloudwatch_detailed
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.nemotron_instances.id]
    delete_on_termination       = true
  }

  # Root volume
  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # Model cache volume
  block_device_mappings {
    device_name = "/dev/sdf"

    ebs {
      volume_size           = var.model_cache_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = false  # PERSIST across instance termination
      encrypted             = true
    }
  }

  user_data = local.active_user_data

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.common_tags,
      {
        Name   = "nemotron-instance"
        Option = local.active_option
      }
    )
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(
      var.common_tags,
      {
        Name   = "nemotron-volume"
        Option = local.active_option
      }
    )
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Application Load Balancer
resource "aws_lb" "nemotron_api" {
  name_prefix        = "nemr"  # 6-char limit
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.alb_subnets

  enable_deletion_protection = false
  enable_http2               = true

  tags = merge(
    var.common_tags,
    { Name = "nemotron-api" }
  )
}

# Target Group
resource "aws_lb_target_group" "nemotron" {
  name_prefix = "nem"  # Limited naming
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  deregistration_delay = 30  # Connection draining timeout

  tags = merge(
    var.common_tags,
    { Name = "nemotron-targets" }
  )
}

# ALB Listener: HTTP → HTTPS redirect
resource "aws_lb_listener" "nemotron_http" {
  load_balancer_arn = aws_lb.nemotron_api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ALB Listener: HTTPS
resource "aws_lb_listener" "nemotron_https" {
  load_balancer_arn = aws_lb.nemotron_api.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nemotron.arn
  }

  depends_on = [aws_lb_target_group.nemotron]
}

# Auto Scaling Group
resource "aws_autoscaling_group" "nemotron" {
  name_prefix         = "asg-nemotron-${local.active_option}-"
  launch_template {
    id      = aws_launch_template.nemotron.id
    version = "$Latest"
  }

  min_size                = local.active_config.min_size
  max_size                = local.active_config.max_size
  desired_capacity        = local.active_config.desired_capacity
  vpc_zone_identifier     = var.subnet_ids
  health_check_type       = "ELB"
  health_check_grace_period = local.active_config.health_check_grace_period

  target_group_arns = [aws_lb_target_group.nemotron.arn]

  enabled_metrics = [
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupMinSize",
    "GroupMaxSize",
    "GroupInServiceCapacity",
    "GroupTotalCapacity",
    "GroupTotalInstances",
    "GroupPendingCapacity"
  ]

  # Spot instance configuration
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_allocation_strategy                 = var.spot_allocation_strategy
      spot_instance_pools                      = var.spot_instance_pools
      spot_max_price                           = ""  # Use on-demand price as max
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.nemotron.id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = local.active_instance_overrides
        content {
          instance_type     = override.value.instance_type
          weighted_capacity = override.value.weighted_capacity
        }
      }
    }
  }

  # Capacity rebalance for Spot interruption
  capacity_rebalance = local.active_config.enable_capacity_rebalance

  tag {
    key                 = "Name"
    value               = "nemotron-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "Option"
    value               = local.active_option
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.enabled_option_count == 1
      error_message = "Exactly one inference option must be enabled (option_1_enabled through option_4_enabled)."
    }
  }
}

# CloudWatch Alarm: Scale Up
resource "aws_cloudwatch_metric_alarm" "nemotron_cpu_high" {
  alarm_name          = "nemotron-cpu-high-${local.active_option}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"  # 5 minutes
  statistic           = "Average"
  threshold           = local.active_config.scale_up_cpu
  alarm_description   = "Scale up when CPU > ${local.active_config.scale_up_cpu}%"
  alarm_actions       = [aws_autoscaling_policy.nemotron_scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nemotron.name
  }
}

# CloudWatch Alarm: Scale Down
resource "aws_cloudwatch_metric_alarm" "nemotron_cpu_low" {
  alarm_name          = "nemotron-cpu-low-${local.active_option}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"  # 2 × 5 min = 10 min
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"  # 5 minutes
  statistic           = "Average"
  threshold           = local.active_config.scale_down_cpu
  alarm_description   = "Scale down when CPU < ${local.active_config.scale_down_cpu}%"
  alarm_actions       = [aws_autoscaling_policy.nemotron_scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.nemotron.name
  }
}

# Auto Scaling Policy: Scale Up
resource "aws_autoscaling_policy" "nemotron_scale_up" {
  name                   = "nemotron-scale-up-${local.active_option}"
  scaling_adjustment      = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nemotron.name
}

# Auto Scaling Policy: Scale Down
resource "aws_autoscaling_policy" "nemotron_scale_down" {
  name                   = "nemotron-scale-down-${local.active_option}"
  scaling_adjustment      = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nemotron.name
}
