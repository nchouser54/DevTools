#!/usr/bin/env bash
# workspace/bootstrap.sh
# Pre-bakes common dependencies into a custom Docker image.
# This script is optional — the Coder startup_script in main.tf handles
# runtime bootstrap for any base image, including ones that skip this step.
set -euo pipefail

# ── Debian / Ubuntu ──────────────────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    tmux \
    ripgrep \
    ca-certificates \
    nodejs \
    npm
  rm -rf /var/lib/apt/lists/*

# ── Alpine Linux ──────────────────────────────────────────────────────────────
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache \
    git \
    curl \
    jq \
    tmux \
    ripgrep \
    ca-certificates \
    nodejs \
    npm

# ── RHEL / Fedora (dnf) ───────────────────────────────────────────────────────
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y \
    git \
    curl \
    jq \
    tmux \
    ca-certificates \
    nodejs \
    npm
  dnf clean all

# ── RHEL / CentOS (yum) ───────────────────────────────────────────────────────
elif command -v yum >/dev/null 2>&1; then
  yum install -y \
    git \
    curl \
    jq \
    tmux \
    ca-certificates \
    nodejs \
    npm
  yum clean all
fi

echo "Universal MCP workspace image bootstrap complete."
