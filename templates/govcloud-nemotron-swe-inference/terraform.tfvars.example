aws_region = "us-gov-west-1"

# VPC Configuration
vpc_id = "vpc-xxxxx"

# Private subnets for EC2 instances (3+, across AZs)
subnet_ids = [
  "subnet-xxxxx",
  "subnet-yyyyy",
  "subnet-zzzzz"
]

# Public subnets for ALB (2+)
alb_subnets = [
  "subnet-public-xxxxx",
  "subnet-public-yyyyy"
]

# SSL certificate for HTTPS
certificate_arn = "arn:aws-us-gov:acm:us-gov-west-1:account-id:certificate/cert-id"

# Nemotron Model Configuration
nemotron_model_id           = "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct"
vllm_max_model_len          = 8192
vllm_max_num_seqs           = 32
vllm_gpu_memory_utilization = 0.90

# Option 1: g4dn.xlarge (T4 GPU)
option_1_enabled           = false
option_1_min_size          = 2
option_1_max_size          = 8
option_1_desired_capacity  = 3
option_1_scale_up_cpu      = 75
option_1_scale_down_cpu    = 30

# Option 2: p3.2xlarge (V100 GPU) - More powerful, more expensive
option_2_enabled           = false
option_2_min_size          = 2
option_2_max_size          = 6
option_2_desired_capacity  = 3
option_2_scale_up_cpu      = 75
option_2_scale_down_cpu    = 30

# Option 3: c6i.4xlarge (CPU-only) - Always available, very slow
option_3_enabled           = false
option_3_min_size          = 3
option_3_max_size          = 20
option_3_desired_capacity  = 5
option_3_scale_up_cpu      = 65
option_3_scale_down_cpu    = 25

# Option 4: g6.xlarge (L40 GPU) - RECOMMENDED default for inference
option_4_enabled           = true
option_4_min_size          = 2
option_4_max_size          = 8
option_4_desired_capacity  = 3
option_4_scale_up_cpu      = 75
option_4_scale_down_cpu    = 30

# Spot Instance Configuration
enable_spot                 = true
on_demand_base_capacity     = 0      # Start with pure Spot
on_demand_percentage        = 20     # 20% on-demand above base (for stability)
spot_allocation_strategy    = "capacity-optimized"
spot_instance_pools         = 3      # Diversify across pools

# Storage
root_volume_size_gb         = 50
model_cache_volume_size_gb  = 150    # Nemotron 405B is ~120 GB

# Monitoring & Logging
enable_cloudwatch_detailed  = true
enable_detailed_logging     = true

# Common Tags
common_tags = {
  Environment = "production"
  Project     = "nemotron-swe"
  ManagedBy   = "terraform"
  CostCenter  = "ai-platform"
  Owner       = "team-ai"
}
