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
TFVARS_INPUT="${1:-$SCRIPT_DIR/../terraform.tfvars}"

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

get_tfvar_value() {
  local key="$1"
  local line value
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$TFVARS_PATH" | tail -n 1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    return
  fi

  value="${line#*=}"
  value="${value%%#*}"
  value="$(echo "$value" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  echo "$value"
}

to_bool() {
  local raw="$1"
  raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '"' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  if [[ "$raw" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

count_enabled=0
selected_option=""
for option in 1 2 3 4; do
  key="option_${option}_enabled"
  value="$(to_bool "$(get_tfvar_value "$key")")"
  if [[ "$value" == "true" ]]; then
    count_enabled=$((count_enabled + 1))
    selected_option="option_${option}"
  fi
done

if [[ "$count_enabled" -ne 1 ]]; then
  echo "ERROR: exactly one option must be enabled in $TFVARS_PATH (option_1_enabled..option_4_enabled)." >&2
  exit 1
fi

AWS_REGION_VALUE="$(get_tfvar_value "aws_region" | tr -d '"')"
if [[ -z "$AWS_REGION_VALUE" ]]; then
  AWS_REGION_VALUE="${AWS_REGION:-us-gov-west-1}"
fi

required_types=()
case "$selected_option" in
  option_1)
    required_types=("g4dn.xlarge")
    ;;
  option_2)
    required_types=("p3.2xlarge")
    ;;
  option_3)
    required_types=("c6i.4xlarge")
    ;;
  option_4)
    required_types=("g6.xlarge" "g6.2xlarge" "g6.12xlarge")
    ;;
  *)
    echo "ERROR: unknown selected option: $selected_option" >&2
    exit 1
    ;;
esac

required_csv="$(IFS=,; echo "${required_types[*]}")"

offerings_output=""
if offerings_output="$(aws ec2 describe-instance-type-offerings \
  --region "$AWS_REGION_VALUE" \
  --location-type availability-zone \
  --filters "Name=instance-type,Values=$required_csv" \
  --query 'InstanceTypeOfferings[].InstanceType' \
  --output text 2>/dev/null)"; then
  for t in "${required_types[@]}"; do
    if ! echo " $offerings_output " | grep -q " $t "; then
      echo "WARN: Spot offering for $t not found in region $AWS_REGION_VALUE (best effort check)." >&2
    fi
  done
else
  echo "WARN: unable to query spot offerings in region $AWS_REGION_VALUE (best effort check skipped)." >&2
fi

echo "Preflight passed for $TFVARS_PATH"
echo "Selected option: $selected_option"
echo "Region: $AWS_REGION_VALUE"
