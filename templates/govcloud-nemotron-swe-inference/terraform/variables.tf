variable "aws_region" {
  description = "AWS GovCloud region"
  type        = string
  default     = "us-gov-west-1"

  validation {
    condition     = can(regex("us-gov-", var.aws_region))
    error_message = "Region must be in AWS GovCloud (us-gov-west-1 or us-gov-east-1)."
  }
}

variable "vpc_id" {
  description = "VPC ID where instances will be launched"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "Must be a valid VPC ID (vpc-xxx)."
  }
}

variable "subnet_ids" {
  description = "List of private subnet IDs (3+ across AZs for resilience)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 3
    error_message = "Must provide at least 3 subnets across availability zones."
  }
}

variable "alb_subnets" {
  description = "List of PUBLIC subnet IDs for ALB (typically 2-3)"
  type        = list(string)

  validation {
    condition     = length(var.alb_subnets) >= 2
    error_message = "Must provide at least 2 public subnets for ALB."
  }
}

variable "certificate_arn" {
  description = "ARN of SSL certificate in AWS Certificate Manager (for HTTPS)"
  type        = string

  validation {
    condition     = can(regex("arn:aws-us-gov:acm:", var.certificate_arn))
    error_message = "Must be a valid GovCloud ACM certificate ARN."
  }
}

# Nemotron Model Configuration
variable "nemotron_model_id" {
  description = "Hugging Face model ID for Nemotron"
  type        = string
  default     = "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct"
}

variable "vllm_max_model_len" {
  description = "vLLM max model sequence length"
  type        = number
  default     = 8192
  
  validation {
    condition     = var.vllm_max_model_len > 0
    error_message = "Must be positive."
  }
}

variable "vllm_max_num_seqs" {
  description = "vLLM maximum concurrent sequences"
  type        = number
  default     = 32

  validation {
    condition     = var.vllm_max_num_seqs > 0
    error_message = "Must be positive."
  }
}

variable "vllm_gpu_memory_utilization" {
  description = "vLLM GPU memory utilization ratio (0.0-1.0)"
  type        = number
  default     = 0.90

  validation {
    condition     = var.vllm_gpu_memory_utilization > 0 && var.vllm_gpu_memory_utilization <= 1.0
    error_message = "Must be between 0.0 and 1.0."
  }
}

# Option 1: g4dn.xlarge (T4 GPU)
variable "option_1_enabled" {
  description = "Enable Option 1 (g4dn.xlarge, T4 GPU)"
  type        = bool
  default     = false
}

variable "option_1_min_size" {
  description = "Option 1 minimum instances"
  type        = number
  default     = 2

  validation {
    condition     = var.option_1_min_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_1_max_size" {
  description = "Option 1 maximum instances"
  type        = number
  default     = 8

  validation {
    condition     = var.option_1_max_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_1_desired_capacity" {
  description = "Option 1 desired instance count"
  type        = number
  default     = 3

  validation {
    condition     = var.option_1_desired_capacity > 0
    error_message = "Must be >= 1."
  }
}

variable "option_1_scale_up_cpu" {
  description = "Option 1 CPU threshold to scale up (%)"
  type        = number
  default     = 75

  validation {
    condition     = var.option_1_scale_up_cpu > 0 && var.option_1_scale_up_cpu <= 100
    error_message = "Must be 1-100."
  }
}

variable "option_1_scale_down_cpu" {
  description = "Option 1 CPU threshold to scale down (%)"
  type        = number
  default     = 30

  validation {
    condition     = var.option_1_scale_down_cpu > 0 && var.option_1_scale_down_cpu <= 100
    error_message = "Must be 1-100."
  }
}

# Option 2: p3.2xlarge (V100 GPU)
variable "option_2_enabled" {
  description = "Enable Option 2 (p3.2xlarge, V100 GPU)"
  type        = bool
  default     = false
}

variable "option_2_min_size" {
  description = "Option 2 minimum instances"
  type        = number
  default     = 2

  validation {
    condition     = var.option_2_min_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_2_max_size" {
  description = "Option 2 maximum instances"
  type        = number
  default     = 6

  validation {
    condition     = var.option_2_max_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_2_desired_capacity" {
  description = "Option 2 desired instance count"
  type        = number
  default     = 3

  validation {
    condition     = var.option_2_desired_capacity > 0
    error_message = "Must be >= 1."
  }
}

variable "option_2_scale_up_cpu" {
  description = "Option 2 CPU threshold to scale up (%)"
  type        = number
  default     = 75

  validation {
    condition     = var.option_2_scale_up_cpu > 0 && var.option_2_scale_up_cpu <= 100
    error_message = "Must be 1-100."
  }
}

variable "option_2_scale_down_cpu" {
  description = "Option 2 CPU threshold to scale down (%)"
  type        = number
  default     = 30

  validation {
    condition     = var.option_2_scale_down_cpu > 0 && var.option_2_scale_down_cpu <= 100
    error_message = "Must be 1-100."
  }
}

# Option 3: c6i.4xlarge (CPU-only)
variable "option_3_enabled" {
  description = "Enable Option 3 (c6i.4xlarge, CPU-only fallback)"
  type        = bool
  default     = false
}

variable "option_3_min_size" {
  description = "Option 3 minimum instances"
  type        = number
  default     = 3

  validation {
    condition     = var.option_3_min_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_3_max_size" {
  description = "Option 3 maximum instances"
  type        = number
  default     = 20

  validation {
    condition     = var.option_3_max_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_3_desired_capacity" {
  description = "Option 3 desired instance count"
  type        = number
  default     = 5

  validation {
    condition     = var.option_3_desired_capacity > 0
    error_message = "Must be >= 1."
  }
}

variable "option_3_scale_up_cpu" {
  description = "Option 3 CPU threshold to scale up (%)"
  type        = number
  default     = 65

  validation {
    condition     = var.option_3_scale_up_cpu > 0 && var.option_3_scale_up_cpu <= 100
    error_message = "Must be 1-100."
  }
}

variable "option_3_scale_down_cpu" {
  description = "Option 3 CPU threshold to scale down (%)"
  type        = number
  default     = 25

  validation {
    condition     = var.option_3_scale_down_cpu > 0 && var.option_3_scale_down_cpu <= 100
    error_message = "Must be 1-100."
  }
}

# Option 4: g6.xlarge (L40 GPU)
variable "option_4_enabled" {
  description = "Enable Option 4 (g6.xlarge, L40 GPU - best for inference)"
  type        = bool
  default     = true
}

variable "option_4_min_size" {
  description = "Option 4 minimum instances"
  type        = number
  default     = 2

  validation {
    condition     = var.option_4_min_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_4_max_size" {
  description = "Option 4 maximum instances"
  type        = number
  default     = 8

  validation {
    condition     = var.option_4_max_size > 0
    error_message = "Must be >= 1."
  }
}

variable "option_4_desired_capacity" {
  description = "Option 4 desired instance count"
  type        = number
  default     = 3

  validation {
    condition     = var.option_4_desired_capacity > 0
    error_message = "Must be >= 1."
  }
}

variable "option_4_scale_up_cpu" {
  description = "Option 4 CPU threshold to scale up (%)"
  type        = number
  default     = 75

  validation {
    condition     = var.option_4_scale_up_cpu > 0 && var.option_4_scale_up_cpu <= 100
    error_message = "Must be 1-100."
  }
}

variable "option_4_scale_down_cpu" {
  description = "Option 4 CPU threshold to scale down (%)"
  type        = number
  default     = 30

  validation {
    condition     = var.option_4_scale_down_cpu > 0 && var.option_4_scale_down_cpu <= 100
    error_message = "Must be 1-100."
  }
}

# Spot Instance Configuration
variable "enable_spot" {
  description = "Enable Spot Instances (70% cost savings)"
  type        = bool
  default     = true
}

variable "on_demand_base_capacity" {
  description = "Number of on-demand instances (baseline for reliability)"
  type        = number
  default     = 0

  validation {
    condition     = var.on_demand_base_capacity >= 0
    error_message = "Must be >= 0."
  }
}

variable "on_demand_percentage" {
  description = "Percentage of on-demand above base capacity (0-100)"
  type        = number
  default     = 20

  validation {
    condition     = var.on_demand_percentage >= 0 && var.on_demand_percentage <= 100
    error_message = "Must be 0-100."
  }
}

variable "spot_allocation_strategy" {
  description = "Spot instance allocation strategy"
  type        = string
  default     = "capacity-optimized"

  validation {
    condition     = contains(["capacity-optimized", "price-capacity-optimized", "lowest-price"], var.spot_allocation_strategy)
    error_message = "Must be capacity-optimized, price-capacity-optimized, or lowest-price."
  }
}

variable "spot_instance_pools" {
  description = "Number of Spot pools to allocate from (for diversity)"
  type        = number
  default     = 3

  validation {
    condition     = var.spot_instance_pools > 0
    error_message = "Must be > 0."
  }
}

# Storage Configuration
variable "root_volume_size_gb" {
  description = "Root volume size (OS + application)"
  type        = number
  default     = 50

  validation {
    condition     = var.root_volume_size_gb >= 30
    error_message = "Must be >= 30 GB."
  }
}

variable "model_cache_volume_size_gb" {
  description = "Model cache volume size (Nemotron weights + embeddings)"
  type        = number
  default     = 150

  validation {
    condition     = var.model_cache_volume_size_gb >= 100
    error_message = "Nemotron 405B requires >= 120 GB. Recommend 150 GB for buffer."
  }
}

# Monitoring & Logging
variable "enable_cloudwatch_detailed" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_detailed_logging" {
  description = "Enable detailed vLLM and system logs"
  type        = bool
  default     = true
}

# Tagging
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "nemotron-swe"
    ManagedBy   = "terraform"
  }
}
