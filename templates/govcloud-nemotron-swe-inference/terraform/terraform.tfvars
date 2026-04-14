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

root_volume_size_gb        = 150 # DL Base GPU AMI root snapshot ~100 GB; Docker + vLLM image add ~30 GB
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
    # REAP 25%-pruned MoE checkpoint (community research, not an NVIDIA release).
    # 92B effective params at BF16 ≈ 184 GB — fits on g6.48xlarge (8× L40S, 384 GB)
    # without any quantization. Pruning method: arXiv:2510.13999.
    # To recover more KV-cache headroom, add: vllm_extra_args = "--quantization fp8"
    # (FP8 is supported on L40S / Ada SM 8.9).
    model_id      = "0xSero/NVIDIA-Nemotron-3-Super-120B-A12B-BF16-REAP-25pct-draft"
    runtime       = "gpu"
    instance_type = "g6.48xlarge"
    instance_overrides = [
      { instance_type = "g6.48xlarge", weighted_capacity = 1 },
      { instance_type = "p4d.24xlarge", weighted_capacity = 1 } # fallback if g6.48xl Spot unavailable
    ]
    min_size                    = 1
    max_size                    = 4
    desired_capacity            = 1
    scale_up_cpu                = 75
    scale_down_cpu              = 30
    tensor_parallel_size        = 8
    vllm_max_model_len          = 16384 # generous context — 25GB/GPU remaining after weights
    vllm_max_num_seqs           = 32
    vllm_gpu_memory_utilization = 0.90
    # REAP checkpoint uses custom model code; this flag is required for vLLM to load it.
    vllm_extra_args           = "--trust-remote-code"
    health_check_grace_period = 1200 # MoE loads faster than dense 405B
    path_prefix               = "/v1/models/nemotron"
    health_check_path         = "/health"
  }

  gemma_30b = {
    model_id      = "google/gemma-4-30b-it"
    runtime       = "gpu"
    instance_type = "g6.12xlarge"
    instance_overrides = [
      { instance_type = "g6.12xlarge", weighted_capacity = 1 },
      { instance_type = "g5.12xlarge", weighted_capacity = 1 }
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
