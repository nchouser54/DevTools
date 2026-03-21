#!/usr/bin/env bash
set -euo pipefail

python -m pip install --no-cache-dir \
  boto3 \
  botocore \
  flask \
  openai \
  python-dotenv \
  httpx \
  tenacity \
  structlog \
  atlassian-python-api \
  PyGithub \
  pytest \
  ruff

mkdir -p /etc/ssh/ssh_config.d
cat >/etc/ssh/ssh_config.d/99-devtools-keepalive.conf <<'EOF'
Host *
  ServerAliveInterval 30
  ServerAliveCountMax 6
  TCPKeepAlive yes
  ControlMaster auto
  ControlPersist 10m
EOF

cat >/usr/local/bin/coder-resume <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec tmux new -A -s coder
EOF
chmod +x /usr/local/bin/coder-resume

cat >/etc/profile.d/devtools-session-resilience.sh <<'EOF'
alias coder-resume='/usr/local/bin/coder-resume'
EOF

cat >/usr/local/bin/ai <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${CHATBOT_BASE_URL:-http://127.0.0.1:8080}"

usage() {
  cat <<'USAGE'
Usage:
  ai health
  ai providers
  ai chat "your prompt" [--provider bedrock|azure]
  ai run "your prompt" [--provider bedrock|azure]

Environment:
  CHATBOT_BASE_URL   Override chatbot endpoint (default: http://127.0.0.1:8080)
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

command="$1"
shift || true

case "$command" in
  health)
    curl -fsS "$BASE_URL/health" | jq .
    ;;

  providers)
    curl -fsS "$BASE_URL/capabilities" | jq '{provider_mode, available_providers, active_connectors, allow_connector_writes, auth_required}'
    ;;

  chat|run)
    if [[ $# -lt 1 ]]; then
      echo "error: prompt is required" >&2
      usage
      exit 1
    fi

    prompt="$1"
    shift || true

    provider=""
    if [[ ${1:-} == "--provider" ]]; then
      if [[ -z ${2:-} ]]; then
        echo "error: --provider requires a value (bedrock|azure)" >&2
        exit 1
      fi
      provider="$2"
      shift 2 || true
    fi

    if [[ -n "$provider" ]]; then
      payload=$(jq -n --arg m "$prompt" --arg p "$provider" '{message:$m, provider:$p}')
    else
      payload=$(jq -n --arg m "$prompt" '{message:$m}')
    fi

    curl -fsS -X POST "$BASE_URL/chat" \
      -H 'Content-Type: application/json' \
      -d "$payload" | jq -r '.reply'
    ;;

  *)
    echo "error: unknown command '$command'" >&2
    usage
    exit 1
    ;;
esac
EOF
chmod +x /usr/local/bin/ai
