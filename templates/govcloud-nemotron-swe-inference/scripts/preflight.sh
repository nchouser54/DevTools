#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $(basename "$0") [--skip-aws-auth] [terraform.tfvars path]" >&2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SKIP_AWS_AUTH=false
if [[ "${1:-}" == "--skip-aws-auth" ]]; then
  SKIP_AWS_AUTH=true
  shift
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

if [[ "$SKIP_AWS_AUTH" == "false" ]]; then
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "ERROR: AWS identity check failed. Verify credentials and network access." >&2
    echo "Hint: use --skip-aws-auth for static preflight only." >&2
    exit 1
  fi
else
  echo "WARN: Skipping AWS identity check (--skip-aws-auth)." >&2
fi

if ! grep -Eq '^[[:space:]]*models[[:space:]]*=' "$TFVARS_PATH"; then
  echo "ERROR: models map not found in $TFVARS_PATH" >&2
  exit 1
fi

ENFORCE_PRIVATE="$(grep -E '^[[:space:]]*enforce_private_networking[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' | tr '[:upper:]' '[:lower:]' || true)"
if [[ -z "$ENFORCE_PRIVATE" ]]; then
  ENFORCE_PRIVATE="true"
fi

if [[ "$ENFORCE_PRIVATE" == "true" ]]; then
  ALB_INTERNAL_VALUE="$(grep -E '^[[:space:]]*alb_internal[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' | tr '[:upper:]' '[:lower:]' || true)"
  if [[ -z "$ALB_INTERNAL_VALUE" ]]; then
    ALB_INTERNAL_VALUE="true"
  fi

  if [[ "$ALB_INTERNAL_VALUE" != "true" ]]; then
    echo "ERROR: Private networking policy violation: alb_internal must be true." >&2
    exit 1
  fi

  if grep -Eq '^[[:space:]]*alb_ingress_cidrs[[:space:]]*=.*0\.0\.0\.0/0' "$TFVARS_PATH"; then
    echo "ERROR: Private networking policy violation: alb_ingress_cidrs cannot include 0.0.0.0/0." >&2
    exit 1
  fi
fi

MANAGE_SG_VALUE="$(grep -E '^[[:space:]]*manage_security_groups[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' | tr '[:upper:]' '[:lower:]' || true)"
if [[ -z "$MANAGE_SG_VALUE" ]]; then
  MANAGE_SG_VALUE="false"
fi

if [[ "$MANAGE_SG_VALUE" == "false" ]]; then
  if ! grep -Eq '^[[:space:]]*alb_security_group_ids[[:space:]]*=.*\[[^]]+\]' "$TFVARS_PATH"; then
    echo "ERROR: Provide non-empty alb_security_group_ids when manage_security_groups=false." >&2
    exit 1
  fi
  if ! grep -Eq '^[[:space:]]*instance_security_group_ids[[:space:]]*=.*\[[^]]+\]' "$TFVARS_PATH"; then
    echo "ERROR: Provide non-empty instance_security_group_ids when manage_security_groups=false." >&2
    exit 1
  fi
fi

EFS_CACHE_VALUE="$(grep -E '^[[:space:]]*enable_efs_cache[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' | tr '[:upper:]' '[:lower:]' || true)"
if [[ "$EFS_CACHE_VALUE" == "true" ]]; then
  EFS_FS_ID="$(grep -E '^[[:space:]]*efs_file_system_id[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)"
  if [[ -z "$EFS_FS_ID" ]] || [[ "$EFS_FS_ID" != fs-* ]]; then
    echo "ERROR: efs_file_system_id must be set to a valid EFS ID (fs-xxxxxxxx) when enable_efs_cache=true." >&2
    exit 1
  fi
  echo "INFO: EFS shared model cache enabled: $EFS_FS_ID"
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

terraform -chdir="$TERRAFORM_DIR" init -input=false >/dev/null
terraform -chdir="$TERRAFORM_DIR" validate >/dev/null

echo "Preflight passed: $TFVARS_PATH"
echo "Region: $AWS_REGION_VALUE"
