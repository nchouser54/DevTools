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

"$SCRIPT_DIR/preflight.sh" "$TFVARS_PATH"

terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" validate
terraform -chdir="$TERRAFORM_DIR" plan -var-file="$TFVARS_PATH"
terraform -chdir="$TERRAFORM_DIR" apply -var-file="$TFVARS_PATH"
