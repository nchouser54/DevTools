aws_region = "us-gov-west-1"

# VPC configuration
vpc_id          = "vpc-xxxxx"
subnet_ids      = ["subnet-private-a", "subnet-private-b", "subnet-private-c"]
alb_subnets     = ["subnet-private-a", "subnet-private-b"]
certificate_arn = "arn:aws-us-gov:acm:us-gov-west-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Private endpoint settings (no public IP exposure)
alb_internal      = true
alb_ingress_cidrs = ["10.0.0.0/8"]

# Networking ownership settings
manage_security_groups      = false
alb_security_group_ids      = ["sg-allowlisted-alb"]
instance_security_group_ids = ["sg-allowlisted-instances"]

# Shared platform settings
enable_spot              = true
on_demand_base_capacity  = 0
on_demand_percentage     = 30
spot_allocation_strategy = "capacity-optimized"
spot_instance_pools      = 3

root_volume_size_gb        = 50
model_cache_volume_size_gb = 200

enable_cloudwatch_detailed = true
enable_detailed_logging    = true

common_tags = {
  Environment = "production"
  Project     = "multi-model-inference"
  ManagedBy   = "terraform"
  Team        = "ai-platform"
}

# Multi-model map: each key creates its own launch template + ASG + target group + route.
models = {
  nemotron = {
    model_id      = "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct"
    runtime       = "gpu"
    instance_type = "g6.xlarge"
    instance_overrides = [
      { instance_type = "g6.xlarge", weighted_capacity = 1 },
      { instance_type = "g6.2xlarge", weighted_capacity = 2 },
      { instance_type = "g6.12xlarge", weighted_capacity = 8 }
    ]
    min_size                    = 2
    max_size                    = 8
    desired_capacity            = 3
    scale_up_cpu                = 75
    scale_down_cpu              = 30
    vllm_max_model_len          = 8192
    vllm_max_num_seqs           = 32
    vllm_gpu_memory_utilization = 0.90
    path_prefix                 = "/v1/models/nemotron"
    health_check_path           = "/health"
  }

  gemma_30b = {
    model_id      = "google/gemma-4-30b-it"
    runtime       = "gpu"
    instance_type = "g6.xlarge"
    instance_overrides = [
      { instance_type = "g6.xlarge", weighted_capacity = 1 },
      { instance_type = "g6.2xlarge", weighted_capacity = 2 }
    ]
    min_size                    = 1
    max_size                    = 4
    desired_capacity            = 1
    scale_up_cpu                = 70
    scale_down_cpu              = 25
    vllm_max_model_len          = 8192
    vllm_max_num_seqs           = 32
    vllm_gpu_memory_utilization = 0.90
    path_prefix                 = "/v1/models/gemma-30b"
    health_check_path           = "/health"
  }

  cpu_fallback = {
    model_id      = "mistral:latest"
    runtime       = "cpu"
    instance_type = "c6i.4xlarge"
    instance_overrides = [
      { instance_type = "c6i.4xlarge", weighted_capacity = 1 }
    ]
    min_size                  = 1
    max_size                  = 3
    desired_capacity          = 1
    scale_up_cpu              = 65
    scale_down_cpu            = 25
    path_prefix               = "/v1/models/cpu-fallback"
    health_check_path         = "/health"
    health_check_grace_period = 300
    capacity_rebalance        = false
  }
}
