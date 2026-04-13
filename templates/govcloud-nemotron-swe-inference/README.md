# GovCloud Multi-Model Inference API Template

This template deploys a shared HTTPS endpoint backed by independent Spot autoscaling pools for multiple AI models.

## What it creates

- 1 Application Load Balancer (HTTPS)
- Path-based routing rules per model
- 1 Launch Template per model
- 1 Auto Scaling Group per model
- 1 Target Group per model
- Scale up/down CloudWatch alarms per model

## Model routing pattern

Each model defines a `path_prefix` in `models` map, for example:
- `/v1/models/nemotron`
- `/v1/models/gemma-30b`
- `/v1/models/cpu-fallback`

Requests route to:
- `POST https://<alb>/v1/models/<model>/completions`

## Configuration

Primary config file: `terraform/terraform.tfvars`

For private-only deployments (no public IP use), set:
- `alb_internal = true`
- `alb_subnets` to private subnets
- `alb_ingress_cidrs` to internal client network CIDRs

For strict network control with only allowlisted security groups:
- `manage_security_groups = false` (default)
- provide `alb_security_group_ids` and `instance_security_group_ids`
- template will fail preflight/apply if these are missing in BYO mode

Use `terraform.tfvars.example` as a starting point. Add one block per model under `models`.

### Nemotron Instance Type Notes

- Recommended family for Nemotron in this template: `g6` (L40 GPUs).
- Default Nemotron override ladder:
  - `g6.xlarge` (primary, weight 1)
  - `g6.2xlarge` (fallback, weight 2)
  - `g6.12xlarge` (high-capacity fallback, weight 8)
- This allows Spot diversification while keeping routing in one model pool.
- If you change these, keep `runtime = "gpu"` and adjust weighted capacities consistently.

Example model definition:

```hcl
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
    min_size          = 2
    max_size          = 8
    desired_capacity  = 3
    scale_up_cpu      = 75
    scale_down_cpu    = 30
    path_prefix       = "/v1/models/nemotron"
  }
}
```

## Deploy

```bash
cd scripts
./preflight.sh ../terraform/terraform.tfvars
./deploy.sh ../terraform/terraform.tfvars
```

## Outputs

- `api_base_url`
- `model_routes`
- `asg_names`
- `target_group_arns`

## Notes

- GPU model artifacts are cached under `/mnt/model-cache/<model-name>/huggingface`.
- CPU fallback uses Ollama wrapper in `user-data-cpu.sh`.
- Spot behavior is configured globally (`on_demand_percentage`, `spot_allocation_strategy`) and applied to each model ASG.
