output "alb_dns_name" {
  description = "DNS name for the shared multi-model endpoint"
  value       = aws_lb.inference_api.dns_name
}

output "api_base_url" {
  description = "Base HTTPS URL for all model routes"
  value       = "https://${aws_lb.inference_api.dns_name}"
}

output "model_routes" {
  description = "Per-model route prefixes"
  value = {
    for k, v in local.models : k => {
      model_id    = v.model_id
      runtime     = v.runtime
      path_prefix = v.path_prefix
      url         = "https://${aws_lb.inference_api.dns_name}${v.path_prefix}/completions"
    }
  }
}

output "target_group_arns" {
  description = "Target groups by model"
  value       = { for k, tg in aws_lb_target_group.model : k => tg.arn }
}

output "asg_names" {
  description = "Auto scaling group names by model"
  value       = { for k, asg in aws_autoscaling_group.model : k => asg.name }
}

output "launch_template_ids" {
  description = "Launch template IDs by model"
  value       = { for k, lt in aws_launch_template.model : k => lt.id }
}

output "deployment_summary" {
  description = "High-level deployment details"
  value = {
    region        = var.aws_region
    models        = keys(local.models)
    default_model = local.default_model_name
    endpoint      = "https://${aws_lb.inference_api.dns_name}"
  }
}
