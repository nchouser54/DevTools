#!/usr/bin/env bash
set -euo pipefail

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) BIN_ARCH="amd64" ;;
  aarch64|arm64) BIN_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

KUBECTL_VERSION="v1.31.2"
AWSCLI_VERSION="2.17.50"

curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${BIN_ARCH}/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${BIN_ARCH}-${AWSCLI_VERSION}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update
rm -rf /tmp/aws /tmp/awscliv2.zip

cat >/usr/local/bin/eks-login <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cluster="${EKS_CLUSTER_NAME:-}"
region="${AWS_REGION:-us-gov-west-1}"
namespace="${DEFAULT_KUBE_NAMESPACE:-default}"

if [[ -z "$cluster" ]]; then
  echo "EKS_CLUSTER_NAME is not set. Export it first." >&2
  exit 1
fi

aws eks update-kubeconfig --region "$region" --name "$cluster"
kubectl config set-context --current --namespace "$namespace" >/dev/null 2>&1 || true

echo "kubeconfig ready for cluster '$cluster' in region '$region' (namespace: '$namespace')."
EOF
chmod +x /usr/local/bin/eks-login

cat >/usr/local/bin/kctx-check <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

namespace="${DEFAULT_KUBE_NAMESPACE:-default}"

echo "Current context: $(kubectl config current-context 2>/dev/null || echo unavailable)"
echo "Namespace: $namespace"
echo
kubectl version --client
kubectl get ns "$namespace"
kubectl get pods -n "$namespace"
EOF
chmod +x /usr/local/bin/kctx-check

cat >/etc/profile.d/kubectl-aliases.sh <<'EOF'
alias k=kubectl
complete -o default -F __start_kubectl k
EOF

echo "Installed kubectl, aws, and helper commands: eks-login, kctx-check"
