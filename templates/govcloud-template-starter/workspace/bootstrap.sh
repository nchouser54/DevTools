#!/usr/bin/env bash
set -euo pipefail

ENABLE_HELM="${ENABLE_HELM:-false}"
HELM_VERSION="${HELM_VERSION:-v3.16.2}"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    unzip \
    jq \
    git \
    bash-completion
  rm -rf /var/lib/apt/lists/*
elif command -v apk >/dev/null 2>&1; then
  apk add --no-cache ca-certificates curl unzip jq git bash
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y ca-certificates curl unzip jq git bash-completion
  dnf clean all
elif command -v yum >/dev/null 2>&1; then
  yum install -y ca-certificates curl unzip jq git bash-completion
  yum clean all
fi

if [[ "$ENABLE_HELM" == "true" ]]; then
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64) HELM_ARCH="amd64" ;;
    aarch64|arm64) HELM_ARCH="arm64" ;;
    *) HELM_ARCH="amd64" ;;
  esac

  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${HELM_ARCH}.tar.gz" -o /tmp/helm.tgz
  tar -xzf /tmp/helm.tgz -C /tmp
  mv "/tmp/linux-${HELM_ARCH}/helm" /usr/local/bin/helm
  chmod +x /usr/local/bin/helm
  rm -rf /tmp/helm.tgz "/tmp/linux-${HELM_ARCH}"
fi

echo "GovCloud starter bootstrap complete. Add template-specific runtime tooling here."
