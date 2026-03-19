#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[devtools-init] $*"
}

warn() {
  echo "[devtools-init][warn] $*" >&2
}

# Defaults for local execution and first-run behavior.
: "${WORKSPACE_SIZE:=medium}"
: "${GIT_REPO_URL:=}"
: "${GIT_REPO_BRANCH:=main}"
: "${MCP_ALLOWED_ROOT:=/workspaces}"
: "${MCP_ENABLE_FILESYSTEM:=true}"
: "${MCP_ENABLE_GITHUB:=false}"
: "${MCP_GITHUB_TOKEN:=}"
: "${MCP_GITHUB_SERVER_URL:=https://github.com}"
: "${MCP_GITHUB_REPOSITORY:=owner/repo}"
: "${MCP_GITHUB_BRANCH:=main}"
: "${MCP_ENABLE_JIRA:=false}"
: "${MCP_JIRA_SERVER_URL:=https://your-org.atlassian.net}"
: "${MCP_JIRA_PROJECT_KEY:=TEAM}"
: "${MCP_JIRA_USER_EMAIL:=you@example.com}"
: "${MCP_JIRA_TOKEN:=}"
: "${MCP_ENABLE_CONFLUENCE:=false}"
: "${MCP_CONFLUENCE_SERVER_URL:=https://your-org.atlassian.net/wiki}"
: "${MCP_CONFLUENCE_SPACE_KEY:=ENG}"
: "${MCP_CONFLUENCE_USER_EMAIL:=you@example.com}"
: "${MCP_CONFLUENCE_TOKEN:=}"
: "${AUTO_RENDER_MCP_CONFIG:=true}"
: "${ENABLE_CLAUDE_CODE_CLI:=false}"
: "${CLAUDE_CODE_MCP_CONFIG_PATH:=}"
: "${VSCODE_MCP_CONFIG_PATH:=}"
: "${GIT_AUTHOR_NAME:=}"
: "${GIT_AUTHOR_EMAIL:=}"

if [[ -n "${GIT_AUTHOR_NAME}" ]]; then
  git config --global user.name "${GIT_AUTHOR_NAME}" || warn "failed to set git user.name"
fi

if [[ -n "${GIT_AUTHOR_EMAIL}" ]]; then
  git config --global user.email "${GIT_AUTHOR_EMAIL}" || warn "failed to set git user.email"
fi

clone_repo_if_needed() {
  if [[ -z "${GIT_REPO_URL}" ]]; then
    log "GIT_REPO_URL not provided; skipping repository clone"
    return
  fi

  local repo_name
  repo_name="$(basename "${GIT_REPO_URL}")"
  repo_name="${repo_name%.git}"

  local target_dir="/workspaces/${repo_name}"

  if [[ ! -d "${target_dir}/.git" ]]; then
    log "cloning ${GIT_REPO_URL} into ${target_dir}"
    git clone "${GIT_REPO_URL}" "${target_dir}"
  else
    log "repository already exists at ${target_dir}; fetching latest refs"
    git -C "${target_dir}" fetch --all --prune
  fi

  log "checking out branch ${GIT_REPO_BRANCH}"
  if git -C "${target_dir}" show-ref --verify --quiet "refs/heads/${GIT_REPO_BRANCH}"; then
    git -C "${target_dir}" checkout "${GIT_REPO_BRANCH}"
  else
    git -C "${target_dir}" checkout -B "${GIT_REPO_BRANCH}" "origin/${GIT_REPO_BRANCH}" \
      || warn "could not checkout origin/${GIT_REPO_BRANCH}; using current branch"
  fi
}

render_mcp_config() {
  if [[ "${AUTO_RENDER_MCP_CONFIG,,}" != "true" ]]; then
    log "AUTO_RENDER_MCP_CONFIG=false; skipping MCP config rendering"
    return
  fi

  local source_template="/usr/local/share/devtools/mcp.servers.template.json"
  local output_dir="${HOME}/.config/devtools/mcp"
  local output_file="${output_dir}/servers.json"

  mkdir -p "${output_dir}"

  if [[ ! -f "${source_template}" ]]; then
    warn "MCP template not found at ${source_template}; skipping"
    return
  fi

  export MCP_ALLOWED_ROOT MCP_ENABLE_FILESYSTEM
  export MCP_ENABLE_GITHUB MCP_GITHUB_TOKEN MCP_GITHUB_SERVER_URL MCP_GITHUB_REPOSITORY MCP_GITHUB_BRANCH
  export MCP_ENABLE_JIRA MCP_JIRA_SERVER_URL MCP_JIRA_PROJECT_KEY MCP_JIRA_USER_EMAIL MCP_JIRA_TOKEN
  export MCP_ENABLE_CONFLUENCE MCP_CONFLUENCE_SERVER_URL MCP_CONFLUENCE_SPACE_KEY MCP_CONFLUENCE_USER_EMAIL MCP_CONFLUENCE_TOKEN

  python - <<'PY'
import json
import os
from pathlib import Path

source = Path('/usr/local/share/devtools/mcp.servers.template.json')
output = Path.home() / '.config' / 'devtools' / 'mcp' / 'servers.json'

payload = json.loads(source.read_text(encoding='utf-8'))
servers = payload.get('servers', {})

fs_enabled = os.environ.get('MCP_ENABLE_FILESYSTEM', 'true').lower() == 'true'
gh_enabled = os.environ.get('MCP_ENABLE_GITHUB', 'false').lower() == 'true'
jira_enabled = os.environ.get('MCP_ENABLE_JIRA', 'false').lower() == 'true'
confluence_enabled = os.environ.get('MCP_ENABLE_CONFLUENCE', 'false').lower() == 'true'

if 'filesystem' in servers:
    servers['filesystem']['enabled'] = fs_enabled
    args = servers['filesystem'].get('args', [])
    if args:
        args[-1] = os.environ.get('MCP_ALLOWED_ROOT', '/workspaces')

if 'github' in servers:
    servers['github']['enabled'] = gh_enabled
    env = servers['github'].setdefault('env', {})
    env['GITHUB_PERSONAL_ACCESS_TOKEN'] = os.environ.get('MCP_GITHUB_TOKEN', '')
    env['GITHUB_SERVER_URL'] = os.environ.get('MCP_GITHUB_SERVER_URL', 'https://github.com')
    env['GITHUB_REPOSITORY'] = os.environ.get('MCP_GITHUB_REPOSITORY', 'owner/repo')
    env['GITHUB_BRANCH'] = os.environ.get('MCP_GITHUB_BRANCH', 'main')

if 'jira' in servers:
    servers['jira']['enabled'] = jira_enabled
    env = servers['jira'].setdefault('env', {})
    env['JIRA_URL'] = os.environ.get('MCP_JIRA_SERVER_URL', 'https://your-org.atlassian.net')
    env['JIRA_SERVER_URL'] = os.environ.get('MCP_JIRA_SERVER_URL', 'https://your-org.atlassian.net')
    env['JIRA_PROJECT_KEY'] = os.environ.get('MCP_JIRA_PROJECT_KEY', 'TEAM')
    env['JIRA_USERNAME'] = os.environ.get('MCP_JIRA_USER_EMAIL', 'you@example.com')
    env['JIRA_API_TOKEN'] = os.environ.get('MCP_JIRA_TOKEN', '')

if 'confluence' in servers:
    servers['confluence']['enabled'] = confluence_enabled
    env = servers['confluence'].setdefault('env', {})
    env['CONFLUENCE_URL'] = os.environ.get('MCP_CONFLUENCE_SERVER_URL', 'https://your-org.atlassian.net/wiki')
    env['CONFLUENCE_SERVER_URL'] = os.environ.get('MCP_CONFLUENCE_SERVER_URL', 'https://your-org.atlassian.net/wiki')
    env['CONFLUENCE_SPACE_KEY'] = os.environ.get('MCP_CONFLUENCE_SPACE_KEY', 'ENG')
    env['CONFLUENCE_USERNAME'] = os.environ.get('MCP_CONFLUENCE_USER_EMAIL', 'you@example.com')
    env['CONFLUENCE_API_TOKEN'] = os.environ.get('MCP_CONFLUENCE_TOKEN', '')

output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(payload, indent=2) + '\n', encoding='utf-8')
print(output)
PY

  log "rendered MCP config to ${output_file}"

  if [[ -n "${CLAUDE_CODE_MCP_CONFIG_PATH}" ]]; then
    mkdir -p "$(dirname "${CLAUDE_CODE_MCP_CONFIG_PATH}")"
    cp "${output_file}" "${CLAUDE_CODE_MCP_CONFIG_PATH}"
    log "copied MCP config to CLAUDE path: ${CLAUDE_CODE_MCP_CONFIG_PATH}"
  fi

  if [[ -n "${VSCODE_MCP_CONFIG_PATH}" ]]; then
    mkdir -p "$(dirname "${VSCODE_MCP_CONFIG_PATH}")"
    cp "${output_file}" "${VSCODE_MCP_CONFIG_PATH}"
    log "copied MCP config to editor path: ${VSCODE_MCP_CONFIG_PATH}"
  fi
}

install_claude_code_cli() {
  if [[ "${ENABLE_CLAUDE_CODE_CLI,,}" != "true" ]]; then
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    warn "npm not available; cannot install Claude Code CLI automatically"
    return
  fi

  log "attempting Claude Code CLI installation"

  local npm_prefix="${HOME}/.npm-global"
  mkdir -p "${npm_prefix}"
  npm config set prefix "${npm_prefix}" >/dev/null 2>&1 || true

  case ":${PATH}:" in
    *":${npm_prefix}/bin:"*) ;;
    *)
      export PATH="${npm_prefix}/bin:${PATH}"
      ;;
  esac

  if ! grep -q "\.npm-global/bin" "${HOME}/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "${HOME}/.bashrc"
  fi
  if ! grep -q "\.npm-global/bin" "${HOME}/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "${HOME}/.zshrc"
  fi

  npm install -g @anthropic-ai/claude-code || warn "Claude Code CLI installation failed; install manually if needed"
}

log "workspace init started (size=${WORKSPACE_SIZE})"
clone_repo_if_needed
render_mcp_config
install_claude_code_cli
log "workspace init complete"
