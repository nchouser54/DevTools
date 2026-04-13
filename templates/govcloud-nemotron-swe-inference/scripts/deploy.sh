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

# If EFS shared model cache is enabled, run two-phase warm-up:
# scale each pool to 1, wait for healthy (cache warm), then scale to configured capacity.
EFS_CACHE_VALUE="$(grep -E '^[[:space:]]*enable_efs_cache[[:space:]]*=' "$TFVARS_PATH" | tail -n1 | sed -E 's/.*=[[:space:]]*"?([^" ]+)"?.*/\1/' | tr '[:upper:]' '[:lower:]' || true)"
if [[ "$EFS_CACHE_VALUE" == "true" ]]; then
  echo ""
  echo "==> EFS cache enabled: running warm-cache to pre-populate model weights before scale-out"
  chmod +x "$SCRIPT_DIR/warm-cache.sh"
  "$SCRIPT_DIR/warm-cache.sh" "$TERRAFORM_DIR"
fi
