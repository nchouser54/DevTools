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
