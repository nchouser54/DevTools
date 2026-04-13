#!/usr/bin/env bash
# warm-cache.sh — Two-phase scale-up for EFS shared model cache.
#
# Phase 1: After `terraform apply`, each ASG is already running at its configured
#          desired_capacity. This script temporarily scales every pool DOWN to 1,
#          waits until that single instance is healthy in the ALB target group
#          (confirming the model is fully downloaded and cached on EFS), then
#          scales each pool back UP to the desired capacity from Terraform output.
#
# Usage:
#   ./warm-cache.sh [terraform dir] [--timeout 3600]
#
# Requirements: aws CLI, jq, terraform (to read outputs)
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [terraform-dir] [--timeout <seconds>]" >&2
  echo "  terraform-dir defaults to the terraform/ sibling of this script." >&2
  echo "  --timeout is the maximum seconds to wait per model for a healthy target (default: 3600)." >&2
}

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
TIMEOUT=3600

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    *) TERRAFORM_DIR="$1"; shift ;;
  esac
done

if [[ ! -d "$TERRAFORM_DIR" ]]; then
  echo "ERROR: Terraform directory not found: $TERRAFORM_DIR" >&2
  exit 1
fi

for dep in aws jq terraform; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: required dependency not found: $dep" >&2
    exit 1
  fi
done

echo "==> Reading Terraform outputs from $TERRAFORM_DIR"
TF_OUTPUT="$(terraform -chdir="$TERRAFORM_DIR" output -json)"

ASG_NAMES="$(echo "$TF_OUTPUT" | jq -r '.asg_names.value | to_entries[] | "\(.key)=\(.value)"')"
TG_ARNS="$(echo "$TF_OUTPUT"   | jq -r '.target_group_arns.value | to_entries[] | "\(.key)=\(.value)"')"
AWS_REGION="$(echo "$TF_OUTPUT" | jq -r '.deployment_summary.value.region')"

if [[ -z "$ASG_NAMES" ]]; then
  echo "ERROR: No asg_names output found. Run terraform apply first." >&2
  exit 1
fi

# Build associative maps: model_key -> ASG name / TG ARN
declare -A ASG_MAP
declare -A TG_MAP

while IFS='=' read -r key val; do
  ASG_MAP["$key"]="$val"
done <<< "$ASG_NAMES"

while IFS='=' read -r key val; do
  TG_MAP["$key"]="$val"
done <<< "$TG_ARNS"

# -----------------------------------------------------------------------
# Phase 1: Scale each pool to 1 (if currently > 1) and record original size
# -----------------------------------------------------------------------
declare -A ORIG_DESIRED

echo ""
echo "==> Phase 1: scaling each model pool to desired=1 to warm EFS cache"
for model_key in "${!ASG_MAP[@]}"; do
  asg="${ASG_MAP[$model_key]}"
  current_desired="$(aws autoscaling describe-auto-scaling-groups \
    --region "$AWS_REGION" \
    --auto-scaling-group-names "$asg" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)"

  ORIG_DESIRED["$model_key"]="$current_desired"

  if [[ "$current_desired" -gt 1 ]]; then
    echo "  [$model_key] scaling $asg: $current_desired -> 1"
    aws autoscaling set-desired-capacity \
      --region "$AWS_REGION" \
      --auto-scaling-group-name "$asg" \
      --desired-capacity 1
  else
    echo "  [$model_key] $asg already at desired=$current_desired, no change"
  fi
done

# -----------------------------------------------------------------------
# Phase 2: Wait for each pool's single instance to be healthy in the TG
# -----------------------------------------------------------------------
echo ""
echo "==> Phase 2: waiting for each model pool to report 1 healthy target"
echo "    (this confirms the model is downloaded and the EFS cache is warm)"
echo "    Timeout per model: ${TIMEOUT}s"
echo ""

ALL_READY=true
for model_key in "${!TG_MAP[@]}"; do
  tg_arn="${TG_MAP[$model_key]}"
  asg="${ASG_MAP[$model_key]}"
  elapsed=0

  echo "  [$model_key] waiting on target group: $tg_arn"

  while true; do
    healthy_count="$(aws elbv2 describe-target-health \
      --region "$AWS_REGION" \
      --target-group-arn "$tg_arn" \
      --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
      --output text)"

    if [[ "$healthy_count" -ge 1 ]]; then
      echo "  [$model_key] healthy! (${elapsed}s elapsed)"
      break
    fi

    if [[ "$elapsed" -ge "$TIMEOUT" ]]; then
      echo "  [$model_key] TIMEOUT after ${TIMEOUT}s — model may still be downloading." >&2
      echo "             Check /var/log/nemotron-init.log on the instance." >&2
      ALL_READY=false
      break
    fi

    echo "  [$model_key] not healthy yet (${elapsed}s / ${TIMEOUT}s) — waiting 30s..."
    sleep 30
    elapsed=$((elapsed + 30))
  done
done

# -----------------------------------------------------------------------
# Phase 3: Scale all pools back to their original desired capacity
# -----------------------------------------------------------------------
echo ""
echo "==> Phase 3: scaling all model pools back to configured capacity"
for model_key in "${!ASG_MAP[@]}"; do
  asg="${ASG_MAP[$model_key]}"
  orig="${ORIG_DESIRED[$model_key]}"

  current="$(aws autoscaling describe-auto-scaling-groups \
    --region "$AWS_REGION" \
    --auto-scaling-group-names "$asg" \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text)"

  if [[ "$current" -lt "$orig" ]]; then
    echo "  [$model_key] scaling $asg: $current -> $orig"
    aws autoscaling set-desired-capacity \
      --region "$AWS_REGION" \
      --auto-scaling-group-name "$asg" \
      --desired-capacity "$orig"
  else
    echo "  [$model_key] $asg already at $current (target=$orig), no change"
  fi
done

echo ""
if [[ "$ALL_READY" == "true" ]]; then
  echo "==> warm-cache complete: EFS cache is warm, all pools scaled to capacity."
else
  echo "WARN: One or more models timed out. Scale-up was still attempted." >&2
  echo "      New instances will still benefit from any partial cache already written." >&2
  exit 1
fi
