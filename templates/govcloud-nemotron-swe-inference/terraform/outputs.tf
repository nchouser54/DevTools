output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer (HTTPS endpoint)"
  value       = aws_lb.nemotron_api.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.nemotron_api.arn
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.nemotron.arn
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.nemotron.name
}

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.nemotron.id
}

output "active_option" {
  description = "Active deployment option (option_1, option_2, or option_3)"
  value       = local.active_option
}

output "active_instance_type" {
  description = "Active instance type"
  value       = local.active_instance_type
}

output "active_config" {
  description = "Active option configuration"
  value       = local.active_config
  sensitive   = false
}

output "asg_min_size" {
  description = "ASG minimum size"
  value       = local.active_config.min_size
}

output "asg_max_size" {
  description = "ASG maximum size"
  value       = local.active_config.max_size
}

output "asg_desired_capacity" {
  description = "ASG desired capacity"
  value       = local.active_config.desired_capacity
}

output "api_endpoint" {
  description = "Full HTTPS endpoint for Nemotron API"
  value       = "https://${aws_lb.nemotron_api.dns_name}/v1/completions"
}

output "health_check_endpoint" {
  description = "Health check endpoint"
  value       = "https://${aws_lb.nemotron_api.dns_name}/health"
}

output "cloudwatch_scale_up_alarm" {
  description = "CloudWatch alarm name for scale-up"
  value       = aws_cloudwatch_metric_alarm.nemotron_cpu_high.alarm_name
}

output "cloudwatch_scale_down_alarm" {
  description = "CloudWatch alarm name for scale-down"
  value       = aws_cloudwatch_metric_alarm.nemotron_cpu_low.alarm_name
}

output "scale_up_threshold" {
  description = "CPU threshold (%) to trigger scale-up"
  value       = local.active_config.scale_up_cpu
}

output "scale_down_threshold" {
  description = "CPU threshold (%) to trigger scale-down"
  value       = local.active_config.scale_down_cpu
}

output "security_group_instances" {
  description = "Security group ID for instances"
  value       = aws_security_group.nemotron_instances.id
}

output "security_group_alb" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role for instances"
  value       = aws_iam_role.nemotron_instance_role.arn
}

output "deployment_info" {
  description = "Deployment summary information"
  value = {
    option         = local.active_option
    instance_type  = local.active_instance_type
    min_instances  = local.active_config.min_size
    max_instances  = local.active_config.max_size
    desired_count  = local.active_config.desired_capacity
    region         = var.aws_region
    model          = var.nemotron_model_id
    endpoint       = "https://${aws_lb.nemotron_api.dns_name}"
    health_grace   = "${local.active_config.health_check_grace_period}s"
  }
}
