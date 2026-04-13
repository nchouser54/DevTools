#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [terraform.tfvars path]" >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"
TFVARS_INPUT="${1:-$TERRAFORM_DIR/terraform.tfvars}"

if [[ "$TFVARS_INPUT" != /* ]]; then
  TFVARS_PATH="$(cd -- "$(dirname -- "$TFVARS_INPUT")" && pwd)/$(basename -- "$TFVARS_INPUT")"
else
  TFVARS_PATH="$TFVARS_INPUT"
fi

if [[ ! -f "$TFVARS_PATH" ]]; then
  echo "ERROR: terraform.tfvars file not found: $TFVARS_PATH" >&2
  exit 1
fi

for dep in aws terraform; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: required dependency not found in PATH: $dep" >&2
    exit 1
  fi
done

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  echo "ERROR: AWS identity check failed. Verify credentials and network access." >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*models[[:space:]]*=' "$TFVARS_PATH"; then
  echo "ERROR: models map not found in $TFVARS_PATH" >&2
  exit 1
fi

AWS_REGION_VALUE="$(grep -E '^[[:space:]]*aws_region[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' || true)"
if [[ -z "$AWS_REGION_VALUE" ]]; then
  AWS_REGION_VALUE="${AWS_REGION:-us-gov-west-1}"
fi

# Best-effort check of declared instance types in tfvars.
INSTANCE_TYPES="$(grep -E '^[[:space:]]*instance_type[[:space:]]*=' "$TFVARS_PATH" | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' | tr '\n' ',' | sed 's/,$//' || true)"
if [[ -n "$INSTANCE_TYPES" ]]; then
  if ! aws ec2 describe-instance-type-offerings \
      --region "$AWS_REGION_VALUE" \
      --location-type availability-zone \
      --filters "Name=instance-type,Values=$INSTANCE_TYPES" \
      --query 'InstanceTypeOfferings[].InstanceType' \
      --output text >/dev/null 2>&1; then
    echo "WARN: unable to verify one or more instance offerings in $AWS_REGION_VALUE" >&2
  fi
fi

terraform -chdir="$TERRAFORM_DIR" init -input=false -upgrade >/dev/null
terraform -chdir="$TERRAFORM_DIR" validate >/dev/null

echo "Preflight passed: $TFVARS_PATH"
echo "Region: $AWS_REGION_VALUE"
