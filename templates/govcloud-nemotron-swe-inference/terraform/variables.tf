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
  description = "Private subnet IDs for model instances"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "Provide at least 2 private subnets."
  }
}

variable "alb_subnets" {
  description = "Subnet IDs for ALB (use private subnets when alb_internal=true)"
  type        = list(string)

  validation {
    condition     = length(var.alb_subnets) >= 2
    error_message = "Provide at least 2 subnets for ALB."
  }
}

variable "certificate_arn" {
  description = "GovCloud ACM certificate ARN for HTTPS listener"
  type        = string

  validation {
    condition     = can(regex("arn:aws-us-gov:acm:", var.certificate_arn))
    error_message = "Must be a valid GovCloud ACM certificate ARN."
  }
}

variable "ami_id" {
  description = "Optional AMI override. When set, this AMI is used for all model pools."
  type        = string
  default     = ""
}

variable "alb_internal" {
  description = "Whether ALB is internal/private only"
  type        = bool
  default     = true
}

variable "alb_ingress_cidrs" {
  description = "CIDR blocks allowed to reach ALB listeners (443/80). Leave empty for defaults."
  type        = list(string)
  default     = []
}

variable "manage_security_groups" {
  description = "If true, template creates and manages ALB/instance security groups. Keep false to use only pre-approved SGs."
  type        = bool
  default     = false
}

variable "alb_security_group_ids" {
  description = "Pre-approved ALB security group IDs to attach when manage_security_groups=false."
  type        = list(string)
  default     = []
}

variable "instance_security_group_ids" {
  description = "Pre-approved instance security group IDs to attach when manage_security_groups=false."
  type        = list(string)
  default     = []
}

variable "enforce_private_networking" {
  description = "If true, deployment fails when ALB is public or ALB ingress allows 0.0.0.0/0."
  type        = bool
  default     = true
}

variable "models" {
  description = "Map of model pools to deploy behind one ALB endpoint"
  type = map(object({
    model_id      = string
    runtime       = optional(string, "gpu")
    instance_type = string
    instance_overrides = optional(list(object({
      instance_type     = string
      weighted_capacity = number
    })), [])
    min_size                    = optional(number, 1)
    max_size                    = optional(number, 4)
    desired_capacity            = optional(number, 1)
    scale_up_cpu                = optional(number, 75)
    scale_down_cpu              = optional(number, 30)
    health_check_grace_period   = optional(number, 600)
    capacity_rebalance          = optional(bool, true)
    vllm_max_model_len          = optional(number, 8192)
    vllm_max_num_seqs           = optional(number, 32)
    vllm_gpu_memory_utilization = optional(number, 0.90)
    tensor_parallel_size        = optional(number, 1)
    vllm_extra_args             = optional(string, "")
    path_prefix                 = optional(string, "")
    health_check_path           = optional(string, "/health")
  }))

  default = {
    nemotron = {
      # REAP 25%-pruned MoE checkpoint: 92B effective params at BF16 ≈ 184 GB.
      # Fits on g6.48xlarge (8× L40S / Ada SM 8.9, 384 GB) without quantization.
      # ~25 GB/GPU headroom after weights for KV cache; add --quantization fp8 to
      # vllm_extra_args if you need larger context or more concurrent sequences.
      # Pruning method: arXiv:2510.13999. Community draft — not an NVIDIA release.
      # For production, swap model_id for a verified checkpoint and benchmark quality.
      model_id      = "0xSero/NVIDIA-Nemotron-3-Super-120B-A12B-BF16-REAP-25pct-draft"
      runtime       = "gpu"
      instance_type = "g6.48xlarge"
      instance_overrides = [
        { instance_type = "g6.48xlarge", weighted_capacity = 1 },
        { instance_type = "p4d.24xlarge", weighted_capacity = 1 }
      ]
      min_size                    = 1
      max_size                    = 4
      desired_capacity            = 1
      scale_up_cpu                = 75
      scale_down_cpu              = 30
      tensor_parallel_size        = 8
      vllm_max_model_len          = 16384
      vllm_max_num_seqs           = 32
      vllm_gpu_memory_utilization = 0.90
      vllm_extra_args             = ""
      health_check_grace_period   = 1200
      path_prefix                 = "/v1/models/nemotron"
      health_check_path           = "/health"
    }
    gemma_30b = {
      # Gemma-4-30B requires ~60 GB VRAM at fp16 (fits on 4× L4 = 96 GB with headroom).
      # g6.12xlarge has 4× L4 GPUs; tensor_parallel_size=4 splits the model across all 4.
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
      tensor_parallel_size        = 4
      vllm_max_model_len          = 8192
      vllm_max_num_seqs           = 32
      vllm_gpu_memory_utilization = 0.90
      vllm_extra_args             = ""
      path_prefix                 = "/v1/models/gemma-30b"
      health_check_path           = "/health"
    }
  }

  validation {
    condition     = length(var.models) > 0
    error_message = "At least one model definition is required in models map."
  }
}

variable "enable_spot" {
  description = "Enable spot pricing strategy"
  type        = bool
  default     = true
}

variable "on_demand_base_capacity" {
  description = "On-demand base capacity"
  type        = number
  default     = 0
}

variable "on_demand_percentage" {
  description = "On-demand percentage above base"
  type        = number
  default     = 20

  validation {
    condition     = var.on_demand_percentage >= 0 && var.on_demand_percentage <= 100
    error_message = "on_demand_percentage must be between 0 and 100."
  }
}

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy"
  type        = string
  default     = "capacity-optimized"

  validation {
    condition     = contains(["capacity-optimized", "price-capacity-optimized", "lowest-price"], var.spot_allocation_strategy)
    error_message = "Must be capacity-optimized, price-capacity-optimized, or lowest-price."
  }
}

variable "spot_instance_pools" {
  description = "Number of spot pools"
  type        = number
  default     = 3
}

variable "root_volume_size_gb" {
  description = "Root EBS size"
  type        = number
  default     = 50
}

variable "model_cache_volume_size_gb" {
  description = "Model cache EBS size"
  type        = number
  default     = 150
}

variable "enable_cloudwatch_detailed" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

variable "enable_detailed_logging" {
  description = "Enable detailed logs"
  type        = bool
  default     = true
}

variable "enable_efs_cache" {
  description = "Mount a shared EFS file system for model weights cache. When true, Spot replacements reuse already-downloaded models and skip re-downloading on startup."
  type        = bool
  default     = false
}

variable "efs_file_system_id" {
  description = "EFS file system ID (fs-xxxxxxxx) to use as shared model cache. Required when enable_efs_cache=true. Provide an existing EFS — the template does not create one."
  type        = string
  default     = ""

  validation {
    condition     = var.efs_file_system_id == "" || can(regex("^fs-[0-9a-f]+$", var.efs_file_system_id))
    error_message = "efs_file_system_id must be empty or a valid EFS ID (fs-xxxxxxxx)."
  }
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Environment = "production"
    Project     = "multi-model-inference"
    ManagedBy   = "terraform"
  }
}
