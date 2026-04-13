#!/usr/bin/env bash
# Bootstrap script for eks-ec2-asg-spot-workspace
# Runs inside the workspace after the Coder agent connects.
# Use for post-startup setup that depends on agent availability.

set -euo pipefail

echo "[bootstrap] Starting workspace setup..."

# Example: clone a repository
# cd /home/coder/project && git clone https://github.com/your-org/your-repo.git || true

# Example: install additional development tools
# sudo apt-get update >/dev/null 2>&1 && sudo apt-get install -y --no-install-recommends make build-essential >/dev/null 2>&1 || true

# Example: set Git configuration
# git config --global user.email "${CODER_USER_EMAIL:-developer@example.com}"
# git config --global user.name "${CODER_USER_NAME:-Developer}"

echo "[bootstrap] Workspace setup complete"
