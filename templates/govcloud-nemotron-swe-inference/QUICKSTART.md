# Quick Start: Multi-Model Inference on Spot

This template deploys one public endpoint and one autoscaling pool per model.

## 1) Prepare configuration

```bash
cd terraform
cp ../terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set:
- `vpc_id`
- `subnet_ids`
- `alb_subnets`
- `certificate_arn`
- `alb_internal = true`
- `alb_ingress_cidrs` for your internal client networks
- `models` map (add one block per model)

## 2) Authenticate AWS

```bash
aws sts get-caller-identity
```

## 3) Run preflight checks

```bash
cd ../scripts
./preflight.sh ../terraform/terraform.tfvars
```

## 4) Deploy

```bash
./deploy.sh ../terraform/terraform.tfvars
```

## 5) Verify outputs

```bash
cd ../terraform
terraform output api_base_url
terraform output model_routes
```

Use routes like:
- `/v1/models/nemotron/completions`
- `/v1/models/gemma-30b/completions`
- `/v1/models/cpu-fallback/completions`

Note: with `alb_internal = true`, the endpoint is private and only reachable from networks in `alb_ingress_cidrs` (or connected private networks such as VPN/Direct Connect/VPC peers).

## Example request

```bash
ENDPOINT=$(terraform output -raw alb_dns_name)

curl -X POST "https://${ENDPOINT}/v1/models/nemotron/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/Nemotron-3-Super-Agentic-SWE-405B-Instruct",
    "prompt": "Review this code for bugs",
    "max_tokens": 256,
    "temperature": 0.2
  }'
```

## Notes

- Each model has independent ASG scaling and Spot policy.
- Add/remove model blocks in `models` map and re-apply.
- Default route forwards to the alphabetically first model key.
