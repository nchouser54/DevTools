#!/usr/bin/env bash
set -euo pipefail

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    tmux \
    ripgrep \
    ca-certificates
  rm -rf /var/lib/apt/lists/*
fi

echo "Shared EC2 workspace pool bootstrap complete."
