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

data "aws_partition" "current" {}

locals {
  models = {
    for name, cfg in var.models : name => {
      model_id      = cfg.model_id
      runtime       = cfg.runtime
      instance_type = cfg.instance_type
      instance_overrides = length(cfg.instance_overrides) > 0 ? [
        for o in cfg.instance_overrides : {
          instance_type     = o.instance_type
          weighted_capacity = tostring(o.weighted_capacity)
        }
        ] : [{
          instance_type     = cfg.instance_type
          weighted_capacity = "1"
      }]
      min_size                    = cfg.min_size
      max_size                    = cfg.max_size
      desired_capacity            = cfg.desired_capacity
      scale_up_cpu                = cfg.scale_up_cpu
      scale_down_cpu              = cfg.scale_down_cpu
      health_check_grace_period   = cfg.health_check_grace_period
      capacity_rebalance          = cfg.capacity_rebalance
      vllm_max_model_len          = cfg.vllm_max_model_len
      vllm_max_num_seqs           = cfg.vllm_max_num_seqs
      vllm_gpu_memory_utilization = cfg.vllm_gpu_memory_utilization
      path_prefix                 = cfg.path_prefix != "" ? cfg.path_prefix : "/v1/models/${name}"
      health_check_path           = cfg.health_check_path
    }
  }

  model_names        = sort(keys(local.models))
  default_model_name = local.model_names[0]

  alb_ingress_cidrs_resolved = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : (
    var.alb_internal ? ["10.0.0.0/8"] : ["0.0.0.0/0"]
  )

  effective_alb_security_group_ids      = var.manage_security_groups ? [aws_security_group.alb[0].id] : var.alb_security_group_ids
  effective_instance_security_group_ids = var.manage_security_groups ? [aws_security_group.nemotron_instances[0].id] : var.instance_security_group_ids
  selected_ami_id                       = length(trimspace(var.ami_id)) > 0 ? var.ami_id : data.aws_ami.ubuntu.id

  # EFS shared model cache DNS (resolved per region; empty when EFS cache is disabled)
  efs_dns_name = var.enable_efs_cache ? "${var.efs_file_system_id}.efs.${var.aws_region}.amazonaws.com" : ""
}

# Security Groups
resource "aws_security_group" "nemotron_instances" {
  count = var.manage_security_groups ? 1 : 0

  name_prefix = "nemotron-instances-"
  description = "Security group for multi-model inference instances"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "multi-model-instances" })
}

resource "aws_security_group" "alb" {
  count = var.manage_security_groups ? 1 : 0

  name_prefix = "multimodel-alb-"
  description = "Security group for multi-model ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.alb_ingress_cidrs_resolved
    description = "HTTPS"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.alb_ingress_cidrs_resolved
    description = "HTTP redirect"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "multi-model-alb" })
}

resource "aws_iam_role" "inference_instance_role" {
  name_prefix = "multi-model-instance-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_instance_profile" "inference" {
  name_prefix = "multi-model-"
  role        = aws_iam_role.inference_instance_role.name
}

resource "aws_iam_role_policy" "inference_instance_policy" {
  name_prefix = "multi-model-"
  role        = aws_iam_role.inference_instance_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "ssmmessages:CreateControlChannel",
            "ssmmessages:CreateDataChannel",
            "ssmmessages:OpenControlChannel",
            "ssmmessages:OpenDataChannel",
            "ssm:UpdateInstanceInformation",
            "ec2messages:AcknowledgeMessage",
            "ec2messages:DeleteMessage",
            "ec2messages:FailMessage",
            "ec2messages:GetEndpoint",
            "ec2messages:GetMessages",
            "ec2messages:SendReply",
            "cloudwatch:PutMetricData",
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents",
            "ecr:GetAuthorizationToken",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = "*"
        }
      ],
      var.enable_efs_cache ? [
        {
          Sid    = "EFSSharedModelCache"
          Effect = "Allow"
          Action = [
            "elasticfilesystem:ClientMount",
            "elasticfilesystem:ClientWrite",
            "elasticfilesystem:ClientRootAccess",
            "elasticfilesystem:DescribeMountTargets"
          ]
          Resource = "arn:${data.aws_partition.current.partition}:elasticfilesystem:${var.aws_region}:*:file-system/${var.efs_file_system_id}"
        }
      ] : []
    )
  })
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

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

resource "aws_launch_template" "model" {
  for_each = local.models

  name_prefix   = "mdl-${replace(each.key, "_", "-")}-"
  image_id      = local.selected_ami_id
  instance_type = each.value.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.inference.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = var.enable_cloudwatch_detailed
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = local.effective_instance_security_group_ids
    delete_on_termination       = true
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  block_device_mappings {
    device_name = "/dev/sdf"
    ebs {
      volume_size           = var.model_cache_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  user_data = each.value.runtime == "gpu" ? base64encode(templatefile("${path.module}/user-data-gpu.sh", {
    model_id             = each.value.model_id
    vllm_max_model_len   = each.value.vllm_max_model_len
    vllm_max_num_seqs    = each.value.vllm_max_num_seqs
    vllm_gpu_memory_util = each.value.vllm_gpu_memory_utilization
    model_cache_mount    = "/mnt/model-cache/${each.key}"
    enable_detailed_logs = var.enable_detailed_logging
    enable_efs_cache     = var.enable_efs_cache
    efs_dns_name         = local.efs_dns_name
    })) : base64encode(templatefile("${path.module}/user-data-cpu.sh", {
    model_id             = each.value.model_id
    vllm_max_model_len   = each.value.vllm_max_model_len
    vllm_max_num_seqs    = each.value.vllm_max_num_seqs
    model_cache_mount    = "/mnt/model-cache/${each.key}"
    enable_detailed_logs = var.enable_detailed_logging
    enable_efs_cache     = var.enable_efs_cache
    efs_dns_name         = local.efs_dns_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name      = "model-${each.key}"
      ModelName = each.key
      ModelId   = each.value.model_id
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(var.common_tags, {
      Name      = "model-volume-${each.key}"
      ModelName = each.key
    })
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.manage_security_groups || length(var.instance_security_group_ids) > 0
      error_message = "Provide instance_security_group_ids when manage_security_groups=false."
    }

    precondition {
      condition     = !var.enable_efs_cache || length(trimspace(var.efs_file_system_id)) > 0
      error_message = "efs_file_system_id must be set to a valid EFS ID (fs-xxxxxxxx) when enable_efs_cache=true."
    }
  }
}

resource "aws_lb" "inference_api" {
  name_prefix        = "mmapi"
  load_balancer_type = "application"
  internal           = var.alb_internal
  security_groups    = local.effective_alb_security_group_ids
  subnets            = var.alb_subnets

  enable_deletion_protection = false
  enable_http2               = true

  lifecycle {
    precondition {
      condition     = var.enforce_private_networking ? var.alb_internal : true
      error_message = "Private networking policy violation: alb_internal must be true when enforce_private_networking=true."
    }

    precondition {
      condition     = var.enforce_private_networking ? !contains(local.alb_ingress_cidrs_resolved, "0.0.0.0/0") : true
      error_message = "Private networking policy violation: alb_ingress_cidrs may not include 0.0.0.0/0 when enforce_private_networking=true."
    }

    precondition {
      condition     = var.manage_security_groups || length(var.alb_security_group_ids) > 0
      error_message = "Provide alb_security_group_ids when manage_security_groups=false."
    }
  }

  tags = merge(var.common_tags, { Name = "multi-model-api" })
}

resource "aws_lb_target_group" "model" {
  for_each = local.models

  name     = "tg-${substr(replace(each.key, "_", "-"), 0, 20)}-${substr(md5(each.key), 0, 8)}"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = each.value.health_check_path
    matcher             = "200"
  }

  deregistration_delay = 30

  tags = merge(var.common_tags, { Name = "tg-${each.key}" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.inference_api.arn
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

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.inference_api.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.model[local.default_model_name].arn
  }
}

resource "aws_lb_listener_rule" "model_route" {
  for_each = local.models

  listener_arn = aws_lb_listener.https.arn
  priority     = 100 + index(local.model_names, each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.model[each.key].arn
  }

  condition {
    path_pattern {
      values = [
        each.value.path_prefix,
        "${each.value.path_prefix}/*",
      ]
    }
  }
}

resource "aws_autoscaling_group" "model" {
  for_each = local.models

  name_prefix               = "asg-${replace(each.key, "_", "-")}-"
  min_size                  = each.value.min_size
  max_size                  = each.value.max_size
  desired_capacity          = each.value.desired_capacity
  vpc_zone_identifier       = var.subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = each.value.health_check_grace_period
  target_group_arns         = [aws_lb_target_group.model[each.key].arn]

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = var.on_demand_base_capacity
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      spot_allocation_strategy                 = var.spot_allocation_strategy
      spot_instance_pools                      = var.spot_instance_pools
      spot_max_price                           = ""
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.model[each.key].id
        version            = "$Latest"
      }

      dynamic "override" {
        for_each = each.value.instance_overrides
        content {
          instance_type     = override.value.instance_type
          weighted_capacity = override.value.weighted_capacity
        }
      }
    }
  }

  capacity_rebalance = each.value.capacity_rebalance

  tag {
    key                 = "Name"
    value               = "model-${each.key}"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.common_tags, { ModelName = each.key, ModelId = each.value.model_id })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  for_each = local.models

  name                   = "${each.key}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.model[each.key].name
}

resource "aws_autoscaling_policy" "scale_down" {
  for_each = local.models

  name                   = "${each.key}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.model[each.key].name
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.models

  alarm_name          = "${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.scale_up_cpu
  alarm_description   = "Scale up ${each.key} when CPU > ${each.value.scale_up_cpu}%"
  alarm_actions       = [aws_autoscaling_policy.scale_up[each.key].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.model[each.key].name
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  for_each = local.models

  alarm_name          = "${each.key}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = each.value.scale_down_cpu
  alarm_description   = "Scale down ${each.key} when CPU < ${each.value.scale_down_cpu}%"
  alarm_actions       = [aws_autoscaling_policy.scale_down[each.key].arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.model[each.key].name
  }
}
