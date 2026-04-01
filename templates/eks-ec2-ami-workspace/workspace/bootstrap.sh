#!/usr/bin/env bash
# workspace/bootstrap.sh
#
# PURPOSE
# -------
# Local smoke-test / pre-validation script. Mirrors the sequence the Coder
# agent user-data runs on a real EC2 instance so you can catch issues
# before deploying a new AMI or template change.
#
# Run inside the workspace/Dockerfile container OR on a test EC2 instance:
#
#   export CODER_AGENT_TOKEN=<token>
#   export CODER_SERVER_URL=https://coder.example.com
#   bash workspace/bootstrap.sh
#
# WHAT THE REAL USER-DATA DOES ON EC2
# ------------------------------------
# 1. Sets proxy env vars if provided.
# 2. Installs base packages (curl, jq, git, tmux).
# 3. Detects and mounts the persistent home EBS volume (/dev/xvdh → /home/coder).
#    Only formats on first attach (blkid check prevents re-formatting).
# 4. Creates the 'coder' OS user.
# 5. Runs any operator-supplied user_data_extra commands.
# 6. Decodes and starts the Coder agent init script as the 'coder' user.

set -euo pipefail

# ── Smoke test: verify required env vars ─────────────────────────────────────
: "${CODER_AGENT_TOKEN:?CODER_AGENT_TOKEN must be set for agent authentication}"
: "${CODER_SERVER_URL:?CODER_SERVER_URL must be set so the agent knows where to connect}"

echo "==> bootstrap: verifying connectivity to Coder server at $CODER_SERVER_URL"
curl -fsSL "$CODER_SERVER_URL/healthz" >/dev/null 2>&1 \
  && echo "    [OK] Coder server reachable." \
  || echo "    [WARN] Could not reach $CODER_SERVER_URL/healthz. Check VPC routing and security groups."

# ── Base packages ─────────────────────────────────────────────────────────────
echo "==> bootstrap: installing base packages"
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y --no-install-recommends curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
  yum install -y curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
fi

# ── Create coder user ─────────────────────────────────────────────────────────
echo "==> bootstrap: ensuring coder user exists"
id coder >/dev/null 2>&1 || useradd -m -s /bin/bash coder
mkdir -p /home/coder/project
chown -R coder:coder /home/coder

# ── Coder agent ───────────────────────────────────────────────────────────────
# In the real user-data flow the init_script is base64-encoded into the
# template and decoded at runtime. For local testing, we download the agent
# binary directly and run it.
echo "==> bootstrap: downloading Coder agent binary (smoke test)"
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)          CODER_ARCH="amd64" ;;
  aarch64 | arm64) CODER_ARCH="arm64" ;;
  *)               CODER_ARCH="amd64" ;;
esac

curl -fsSL "$CODER_SERVER_URL/bin/coder-linux-$CODER_ARCH" -o /tmp/coder-agent
chmod +x /tmp/coder-agent

echo "==> bootstrap: starting Coder agent (will connect to $CODER_SERVER_URL)"
CODER_AGENT_TOKEN="$CODER_AGENT_TOKEN" su coder -lc "/tmp/coder-agent agent" &

echo "==> bootstrap: Coder agent started in background (PID $!)"
echo ""
echo "==> PROVISIONER IAM REQUIREMENTS FOR eks-ec2-ami-workspace"
echo "    The Coder provisioner IRSA role needs:"
echo "    ec2:RunInstances, ec2:TerminateInstances, ec2:DescribeInstances,"
echo "    ec2:DescribeInstanceStatus, ec2:CreateVolume, ec2:DeleteVolume,"
echo "    ec2:AttachVolume, ec2:DetachVolume, ec2:DescribeVolumes,"
echo "    ec2:CreateTags, ec2:DescribeImages, ec2:DescribeSubnets,"
echo "    ec2:CreateSecurityGroup, ec2:DeleteSecurityGroup,"
echo "    ec2:AuthorizeSecurityGroupEgress, ec2:DescribeSecurityGroups,"
echo "    iam:PassRole (if using instance_profile_name)"
echo ""
echo "    See docs/iam-policies/eks-ec2-ami-workspace-irsa-policy.json"
