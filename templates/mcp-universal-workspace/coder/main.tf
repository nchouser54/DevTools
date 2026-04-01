terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0.2"
    }
  }
}

# ── Runtime ──────────────────────────────────────────────────────────────────

variable "socket" {
  type        = string
  description = "Docker daemon socket used by the workspace template runtime."
  default     = "unix:///var/run/docker.sock"
}

variable "container_image" {
  type        = string
  description = "Container image for the workspace. Any base image works — the startup script installs node/npm automatically via multi-distro bootstrap."
  default     = "codercom/example-universal:ubuntu"
}

variable "workdir" {
  type        = string
  description = "Working directory inside the container where Claude Code launches."
  default     = "/home/coder/project"
}

# ── IDE / App ─────────────────────────────────────────────────────────────────

variable "enable_code_server" {
  type        = bool
  description = "Expose code-server (browser VS Code) as a workspace app."
  default     = true
}

variable "vscode_extensions_csv" {
  type        = string
  description = "Comma-separated VS Code extension IDs to pre-install (e.g. ms-python.python,hashicorp.terraform)."
  default     = ""
}

# ── Repository Bootstrap ──────────────────────────────────────────────────────

variable "git_repo_url" {
  type        = string
  description = "Optional Git repository URL to clone into the workspace on start. MCP runs regardless of whether this is set."
  default     = ""
}

variable "git_repo_branch" {
  type        = string
  description = "Git branch to clone or check out."
  default     = "main"
}

# ── Claude Auth ───────────────────────────────────────────────────────────────

variable "claude_api_key" {
  type        = string
  description = "Anthropic API key. Leave empty to authenticate later via 'Claude Auth Setup' app or the oauth token."
  default     = ""
  sensitive   = true
}

variable "claude_code_oauth_token" {
  type        = string
  description = "Claude Code OAuth/session token from `claude setup-token`. Leave empty when using API key or interactive login."
  default     = ""
  sensitive   = true
}

variable "claude_code_version" {
  type        = string
  description = "Claude Code version to install. Use 'latest' or pin to a tested release tag."
  default     = "latest"
}

variable "install_via_npm" {
  type        = bool
  description = "Install Claude Code via npm rather than the official installer. Use in restricted network environments."
  default     = false
}

variable "claude_model" {
  type        = string
  description = "Optional default Claude model override. Leave empty to use the Claude defaults."
  default     = ""
}

variable "permission_mode" {
  type        = string
  description = "Claude permission mode: empty | default | acceptEdits | plan | bypassPermissions."
  default     = "plan"

  validation {
    condition     = contains(["", "default", "acceptEdits", "plan", "bypassPermissions"], var.permission_mode)
    error_message = "permission_mode must be one of: empty, default, acceptEdits, plan, bypassPermissions."
  }
}

# ── AWS / Bedrock ─────────────────────────────────────────────────────────────

variable "enable_bedrock" {
  type        = bool
  description = "Enable AWS Bedrock mode for Claude Code. Recommended when authenticating with an IAM role."
  default     = true
}

variable "aws_region" {
  type        = string
  description = "AWS region for Bedrock requests."
  default     = "us-gov-west-1"
}

variable "aws_bearer_token_bedrock" {
  type        = string
  description = "Optional AWS Bedrock bearer token fallback when IAM role credentials are unavailable at runtime."
  default     = ""
  sensitive   = true
}

# ── MCP: Filesystem ───────────────────────────────────────────────────────────

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Enable the filesystem MCP server. Grants Claude read/write access to mcp_allowed_root. Requires no credentials."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Filesystem root exposed to the filesystem MCP server."
  default     = "/home/coder/project"
}

# ── MCP: GitHub ───────────────────────────────────────────────────────────────

variable "enable_mcp_github" {
  type        = bool
  description = "Enable GitHub MCP server (@modelcontextprotocol/server-github). Requires mcp_github_token."
  default     = false
}

variable "mcp_github_token" {
  type        = string
  description = "GitHub Personal Access Token for the GitHub MCP server."
  default     = ""
  sensitive   = true
}

variable "mcp_github_server_url" {
  type        = string
  description = "GitHub or GitHub Enterprise Server base URL."
  default     = "https://github.com"
}

variable "mcp_github_repository" {
  type        = string
  description = "Default GitHub repository in owner/repo format. Used to scope GitHub MCP context."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default GitHub branch for GitHub MCP."
  default     = "main"
}

# ── MCP: Jira ─────────────────────────────────────────────────────────────────

variable "enable_mcp_jira" {
  type        = bool
  description = "Enable Jira MCP server via mcp-remote proxy. Requires mcp_jira_server_url and mcp_jira_token."
  default     = false
}

variable "mcp_jira_server_url" {
  type        = string
  description = "Jira MCP endpoint URL. For Atlassian Cloud: https://mcp.atlassian.com/v1/sse. For self-hosted: https://jira.example.com/mcp."
  default     = "https://jira.example.com/mcp"
}

variable "mcp_jira_project_key" {
  type        = string
  description = "Default Jira project key scoped to this workspace (e.g. PROJ, DEVOPS)."
  default     = "PROJ"
}

variable "mcp_jira_user_email" {
  type        = string
  description = "Jira user email. Leave empty to inherit the workspace owner email."
  default     = ""
}

variable "mcp_jira_token" {
  type        = string
  description = "Jira API token or personal access token for the Jira MCP server."
  default     = ""
  sensitive   = true
}

# ── MCP: Confluence ───────────────────────────────────────────────────────────

variable "enable_mcp_confluence" {
  type        = bool
  description = "Enable Confluence MCP server via mcp-remote proxy. Requires mcp_confluence_server_url and mcp_confluence_token."
  default     = false
}

variable "mcp_confluence_server_url" {
  type        = string
  description = "Confluence MCP endpoint URL. For Atlassian Cloud: https://mcp.atlassian.com/v1/sse. For self-hosted: https://confluence.example.com/mcp."
  default     = "https://confluence.example.com/mcp"
}

variable "mcp_confluence_space_key" {
  type        = string
  description = "Default Confluence space key for this workspace (e.g. ENG, DOCS)."
  default     = "ENG"
}

variable "mcp_confluence_user_email" {
  type        = string
  description = "Confluence user email. Leave empty to inherit the workspace owner email."
  default     = ""
}

variable "mcp_confluence_token" {
  type        = string
  description = "Confluence API token or personal access token for the Confluence MCP server."
  default     = ""
  sensitive   = true
}

# ── MCP: Custom Scripts ───────────────────────────────────────────────────────

variable "mcp_custom_scripts_csv" {
  type        = string
  description = "Comma-separated custom MCP server entries in 'server-name:/absolute/path/to/executable' format. Each executable is registered as a local MCP server. Example: my-tool:/opt/mcp/my-tool.sh,audit-log:/opt/mcp/audit.sh"
  default     = ""
}

# ── MCP: Remote Config URLs ───────────────────────────────────────────────────

variable "mcp_remote_config_urls_csv" {
  type        = string
  description = "Comma-separated HTTPS URLs that each return a Claude MCP JSON config payload ({ mcpServers: {...} }) to merge at startup."
  default     = ""
}

# ── Enterprise Network ────────────────────────────────────────────────────────

variable "https_proxy" {
  type        = string
  description = "Optional HTTPS proxy URL for enterprise outbound connectivity."
  default     = ""
}

variable "http_proxy" {
  type        = string
  description = "Optional HTTP proxy URL for enterprise outbound connectivity."
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated NO_PROXY hosts/CIDRs to bypass the proxy."
  default     = ""
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "docker" {
  host = var.socket
}

provider "coder" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  workspace_owner_effective       = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  workspace_owner_email           = try(data.coder_workspace_owner.me.email, "")
  jira_user_email_effective       = length(trimspace(var.mcp_jira_user_email)) > 0 ? trimspace(var.mcp_jira_user_email) : local.workspace_owner_email
  confluence_user_email_effective = length(trimspace(var.mcp_confluence_user_email)) > 0 ? trimspace(var.mcp_confluence_user_email) : local.workspace_owner_email
  claude_permission_arg           = trimspace(var.permission_mode) != "" ? " --permission-mode ${var.permission_mode}" : ""

  remote_mcp_config_urls = compact([
    for item in split(",", var.mcp_remote_config_urls_csv) : trimspace(item)
  ])

  vscode_extensions = compact([
    for item in split(",", var.vscode_extensions_csv) : trimspace(item)
  ])

  enabled_connectors = compact([
    var.enable_mcp_filesystem                                  ? "filesystem"     : "",
    var.enable_mcp_github                                      ? "github"         : "",
    var.enable_mcp_jira                                        ? "jira"           : "",
    var.enable_mcp_confluence                                  ? "confluence"     : "",
    length(trimspace(var.mcp_custom_scripts_csv)) > 0          ? "custom-scripts" : "",
    length(trimspace(var.mcp_remote_config_urls_csv)) > 0      ? "remote-config"  : "",
  ])
}

# ── Input Validation ──────────────────────────────────────────────────────────

check "claude_auth_inputs" {
  assert {
    condition     = !(length(trimspace(var.claude_api_key)) > 0 && length(trimspace(var.claude_code_oauth_token)) > 0)
    error_message = "Provide either claude_api_key or claude_code_oauth_token, not both."
  }
}

check "mcp_github_inputs" {
  assert {
    condition     = !var.enable_mcp_github || length(trimspace(var.mcp_github_token)) > 0
    error_message = "mcp_github_token must be set when enable_mcp_github is true."
  }

  assert {
    condition     = !var.enable_mcp_github || can(regex("^[^/\\s]+/[^/\\s]+$", trimspace(var.mcp_github_repository)))
    error_message = "mcp_github_repository must be in owner/repo format when enable_mcp_github is true."
  }
}

check "mcp_jira_inputs" {
  assert {
    condition     = !var.enable_mcp_jira || length(trimspace(var.mcp_jira_token)) > 0
    error_message = "mcp_jira_token must be set when enable_mcp_jira is true."
  }

  assert {
    condition     = !var.enable_mcp_jira || length(trimspace(var.mcp_jira_server_url)) > 0
    error_message = "mcp_jira_server_url must be set when enable_mcp_jira is true."
  }
}

check "mcp_confluence_inputs" {
  assert {
    condition     = !var.enable_mcp_confluence || length(trimspace(var.mcp_confluence_token)) > 0
    error_message = "mcp_confluence_token must be set when enable_mcp_confluence is true."
  }

  assert {
    condition     = !var.enable_mcp_confluence || length(trimspace(var.mcp_confluence_server_url)) > 0
    error_message = "mcp_confluence_server_url must be set when enable_mcp_confluence is true."
  }
}

# ── Coder Agent ───────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = "linux"
  arch = data.coder_provisioner.me.arch
  dir  = var.workdir

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    ssh_helper             = false
    port_forwarding_helper = true
    web_terminal           = true
  }

  startup_script_behavior = "blocking"
  connection_timeout      = 300

  env = {
    GIT_AUTHOR_NAME           = local.workspace_owner_effective
    GIT_AUTHOR_EMAIL          = local.workspace_owner_email
    GIT_COMMITTER_NAME        = local.workspace_owner_effective
    GIT_COMMITTER_EMAIL       = local.workspace_owner_email
    ENABLE_MCP_FILESYSTEM     = tostring(var.enable_mcp_filesystem)
    ENABLE_MCP_GITHUB         = tostring(var.enable_mcp_github)
    ENABLE_MCP_JIRA           = tostring(var.enable_mcp_jira)
    ENABLE_MCP_CONFLUENCE     = tostring(var.enable_mcp_confluence)
    MCP_ALLOWED_ROOT          = var.mcp_allowed_root
    MCP_GITHUB_SERVER_URL     = var.mcp_github_server_url
    MCP_GITHUB_REPOSITORY     = var.mcp_github_repository
    MCP_GITHUB_BRANCH         = var.mcp_github_branch
    MCP_JIRA_SERVER_URL       = var.mcp_jira_server_url
    MCP_JIRA_PROJECT_KEY      = var.mcp_jira_project_key
    MCP_JIRA_USER_EMAIL       = local.jira_user_email_effective
    MCP_CONFLUENCE_SERVER_URL = var.mcp_confluence_server_url
    MCP_CONFLUENCE_SPACE_KEY  = var.mcp_confluence_space_key
    MCP_CONFLUENCE_USER_EMAIL = local.confluence_user_email_effective
    MCP_REMOTE_CONFIG_URLS    = var.mcp_remote_config_urls_csv
    ENABLE_BEDROCK            = tostring(var.enable_bedrock)
    AWS_REGION                = var.aws_region
    AWS_DEFAULT_REGION        = var.aws_region
    HTTPS_PROXY               = var.https_proxy
    HTTP_PROXY                = var.http_proxy
    NO_PROXY                  = var.no_proxy
    https_proxy               = var.https_proxy
    http_proxy                = var.http_proxy
    no_proxy                  = var.no_proxy
  }

  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    export PATH="$HOME/.local/bin:$PATH"

    # ── Log helpers ────────────────────────────────────────────────────────────
    _log()  { echo "[coder] $*"; }
    _warn() { echo "[coder][WARN] $*" >&2; }

    # ── Multi-distro Node/npm bootstrap ───────────────────────────────────────
    # Detects the correct Node.js binary arch string for tarball downloads.
    _node_arch() {
      case "$(uname -m)" in
        x86_64)  echo "x64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7l" ;;
        *)       echo "x64" ;;
      esac
    }

    # Ensures npx is on PATH, trying every available install path in order.
    # Fails gracefully — print a warning and return 1 if nothing works.
    _ensure_npx() {
      command -v npx >/dev/null 2>&1 && { _log "npx already on PATH"; return 0; }
      _log "npx not found — running multi-distro bootstrap..."

      # Debian / Ubuntu
      if command -v apt-get >/dev/null 2>&1; then
        _log "Trying apt-get install nodejs npm..."
        (
          command -v sudo >/dev/null 2>&1 \
            && sudo apt-get update -qq >/dev/null 2>&1 \
            && sudo apt-get install -y --no-install-recommends nodejs npm ca-certificates curl >/dev/null 2>&1
        ) || (
          apt-get update -qq >/dev/null 2>&1 \
            && apt-get install -y --no-install-recommends nodejs npm ca-certificates curl >/dev/null 2>&1
        ) || true
        command -v npx >/dev/null 2>&1 && { _log "npm installed via apt-get"; return 0; }
      fi

      # Alpine Linux
      if command -v apk >/dev/null 2>&1; then
        _log "Trying apk add nodejs npm..."
        (
          command -v sudo >/dev/null 2>&1 \
            && sudo apk add --no-cache nodejs npm ca-certificates curl >/dev/null 2>&1
        ) || apk add --no-cache nodejs npm ca-certificates curl >/dev/null 2>&1 || true
        command -v npx >/dev/null 2>&1 && { _log "npm installed via apk"; return 0; }
      fi

      # RHEL / Rocky / Fedora — prefer dnf, fall back to yum
      if command -v dnf >/dev/null 2>&1; then
        _log "Trying dnf install nodejs npm..."
        (
          command -v sudo >/dev/null 2>&1 \
            && sudo dnf install -y nodejs npm ca-certificates curl >/dev/null 2>&1
        ) || dnf install -y nodejs npm ca-certificates curl >/dev/null 2>&1 || true
        command -v npx >/dev/null 2>&1 && { _log "npm installed via dnf"; return 0; }
      elif command -v yum >/dev/null 2>&1; then
        _log "Trying yum install nodejs npm..."
        (
          command -v sudo >/dev/null 2>&1 \
            && sudo yum install -y nodejs npm ca-certificates curl >/dev/null 2>&1
        ) || yum install -y nodejs npm ca-certificates curl >/dev/null 2>&1 || true
        command -v npx >/dev/null 2>&1 && { _log "npm installed via yum"; return 0; }
      fi

      # nvm — works in images without any system package manager
      export NVM_DIR="$HOME/.nvm"
      if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        _log "Trying nvm install..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash >/dev/null 2>&1 || true
      fi
      if [[ -s "$NVM_DIR/nvm.sh" ]]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh"
        nvm install --lts >/dev/null 2>&1 && nvm use --lts >/dev/null 2>&1 || true
        _nvm_ver="$(nvm current 2>/dev/null || echo NONE)"
        export PATH="$NVM_DIR/versions/node/$_nvm_ver/bin:$PATH"
        command -v npx >/dev/null 2>&1 && { _log "npm installed via nvm (node $_nvm_ver)"; return 0; }
      fi

      # Binary fallback — download the official Node.js tarball directly
      _arch="$(_node_arch)"
      _nver="v20.17.0"
      _ndir="node-$_nver-linux-$_arch"
      _log "Trying Node binary download ($_ndir)..."
      mkdir -p "$HOME/.local/bin"
      curl -fsSL "https://nodejs.org/dist/$_nver/$_ndir.tar.gz" \
        | tar -xz -C "$HOME/.local" >/dev/null 2>&1 || true
      if [[ -x "$HOME/.local/$_ndir/bin/npx" ]]; then
        ln -sf "$HOME/.local/$_ndir/bin/node" "$HOME/.local/bin/node" 2>/dev/null || true
        ln -sf "$HOME/.local/$_ndir/bin/npm"  "$HOME/.local/bin/npm"  2>/dev/null || true
        ln -sf "$HOME/.local/$_ndir/bin/npx"  "$HOME/.local/bin/npx"  2>/dev/null || true
        export PATH="$HOME/.local/bin:$PATH"
        command -v npx >/dev/null 2>&1 && { _log "npm installed via Node binary download"; return 0; }
      fi

      _warn "All node/npm install methods failed. npx-based MCP servers will be skipped."
      return 1
    }

    # ── Base system dependencies ───────────────────────────────────────────────
    _log "Installing base system dependencies..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -qq >/dev/null 2>&1 || true
      sudo apt-get install -y --no-install-recommends git curl jq tmux ca-certificates >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
      (command -v sudo >/dev/null 2>&1 && sudo apk add --no-cache git curl jq tmux ca-certificates >/dev/null 2>&1) \
        || apk add --no-cache git curl jq tmux ca-certificates >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
      (command -v sudo >/dev/null 2>&1 && sudo dnf install -y git curl jq tmux ca-certificates >/dev/null 2>&1) \
        || dnf install -y git curl jq tmux ca-certificates >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
      (command -v sudo >/dev/null 2>&1 && sudo yum install -y git curl jq tmux ca-certificates >/dev/null 2>&1) \
        || yum install -y git curl jq tmux ca-certificates >/dev/null 2>&1 || true
    fi

    # ── Ensure node/npx before MCP registration ───────────────────────────────
    mcp_wants_npx="${tostring(var.enable_mcp_filesystem || var.enable_mcp_github || var.enable_mcp_jira || var.enable_mcp_confluence)}"
    if [[ "$mcp_wants_npx" == "true" || "${var.install_via_npm}" == "true" ]]; then
      _ensure_npx || true
    fi

    # ── VS Code extensions ────────────────────────────────────────────────────
    if [[ -n "${var.vscode_extensions_csv}" ]]; then
      IFS=',' read -r -a _vsc_exts <<< "${var.vscode_extensions_csv}"
      for _raw_ext in "$${_vsc_exts[@]}"; do
        _ext="$(echo "$_raw_ext" | xargs)"
        [[ -z "$_ext" ]] && continue
        command -v code-server       >/dev/null 2>&1 && code-server       --install-extension "$_ext" >/dev/null 2>&1 || true
        command -v openvscode-server >/dev/null 2>&1 && openvscode-server --install-extension "$_ext" >/dev/null 2>&1 || true
      done
    fi

    # ── Workdir and Git repo ──────────────────────────────────────────────────
    mkdir -p "$(dirname '${var.workdir}')"

    if [[ -n "${var.git_repo_url}" ]]; then
      if command -v git >/dev/null 2>&1; then
        if [[ ! -d "${var.workdir}/.git" ]]; then
          rm -rf "${var.workdir}"
          git clone --branch "${var.git_repo_branch}" --single-branch \
            "${var.git_repo_url}" "${var.workdir}" \
            || { _warn "git clone failed; creating empty workdir"; mkdir -p "${var.workdir}"; }
        else
          cd "${var.workdir}"
          git fetch origin "${var.git_repo_branch}" || true
          git checkout "${var.git_repo_branch}" || true
        fi
      else
        _warn "git not found; skipping repo bootstrap for ${var.git_repo_url}"
        mkdir -p "${var.workdir}"
      fi
    else
      mkdir -p "${var.workdir}"
    fi

    # ── Install Claude Code ───────────────────────────────────────────────────
    if ! command -v claude >/dev/null 2>&1; then
      _log "Installing Claude Code (version: ${var.claude_code_version})..."
      if [[ "${var.install_via_npm}" == "true" ]]; then
        npm install -g "@anthropic-ai/claude-code@${var.claude_code_version}" \
          || { _warn "npm install failed; trying official installer"; \
               curl -fsSL claude.ai/install.sh | bash -s -- "${var.claude_code_version}" || true; }
      else
        curl -fsSL claude.ai/install.sh | bash -s -- "${var.claude_code_version}" \
          || { _warn "Official installer failed; falling back to npm"; \
               npm install -g "@anthropic-ai/claude-code@${var.claude_code_version}" || true; }
      fi
    else
      _log "Claude Code already present: $(claude --version 2>/dev/null || echo unknown)"
    fi

    export PATH="$HOME/.local/bin:$PATH"

    # ── MCP registration helpers ──────────────────────────────────────────────
    # Reads pairs of (server-name, server-json) from stdin and registers each.
    _add_mcp_servers() {
      local _mcp_json="$1"
      while IFS= read -r _sname && IFS= read -r _sjson; do
        _log "Registering MCP server: $_sname"
        claude mcp add-json "$_sname" "$_sjson" \
          || _warn "Failed to register MCP server: $_sname"
      done < <(echo "$_mcp_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
    }

    # ── Claude config and MCP registration ───────────────────────────────────
    if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then

      # Write initial ~/.claude.json when an API key is supplied
      if [[ -n "$${CLAUDE_API_KEY:-}" ]]; then
        _log "Writing Claude config with API key..."
        _ccfg="$HOME/.claude.json"
        if [[ -f "$_ccfg" ]]; then
          jq --arg workdir "${var.workdir}" --arg apikey "$${CLAUDE_API_KEY}" \
            '.autoUpdaterStatus = "disabled" |
             .bypassPermissionsModeAccepted = true |
             .hasAcknowledgedCostThreshold = true |
             .hasCompletedOnboarding = true |
             .primaryApiKey = $apikey |
             .projects[$workdir].hasCompletedProjectOnboarding = true |
             .projects[$workdir].hasTrustDialogAccepted = true' \
            "$_ccfg" > "$_ccfg.tmp" && mv "$_ccfg.tmp" "$_ccfg"
        else
          cat > "$_ccfg" <<CLAUDECFG
{
  "autoUpdaterStatus": "disabled",
  "bypassPermissionsModeAccepted": true,
  "hasAcknowledgedCostThreshold": true,
  "hasCompletedOnboarding": true,
  "primaryApiKey": "$${CLAUDE_API_KEY:-}",
  "projects": {
    "${var.workdir}": {
      "hasCompletedProjectOnboarding": true,
      "hasTrustDialogAccepted": true
    }
  }
}
CLAUDECFG
        fi
      fi

      # ── Build built-in MCP server config from Terraform variables ──────────
      _local_mcp=$(jq -n \
        --arg root    "${var.mcp_allowed_root}" \
        --arg ghTok   "$${MCP_GITHUB_TOKEN:-}" \
        --arg ghSrv   "${var.mcp_github_server_url}" \
        --arg ghRepo  "${var.mcp_github_repository}" \
        --arg ghBr    "${var.mcp_github_branch}" \
        --arg jSrv    "${var.mcp_jira_server_url}" \
        --arg jProj   "${var.mcp_jira_project_key}" \
        --arg jEmail  "${local.jira_user_email_effective}" \
        --arg jTok    "$${MCP_JIRA_TOKEN:-}" \
        --arg cSrv    "${var.mcp_confluence_server_url}" \
        --arg cSpace  "${var.mcp_confluence_space_key}" \
        --arg cEmail  "${local.confluence_user_email_effective}" \
        --arg cTok    "$${MCP_CONFLUENCE_TOKEN:-}" \
        --arg enFs    "${tostring(var.enable_mcp_filesystem)}" \
        --arg enGh    "${tostring(var.enable_mcp_github)}" \
        --arg enJira  "${tostring(var.enable_mcp_jira)}" \
        --arg enConf  "${tostring(var.enable_mcp_confluence)}" \
        '{
          mcpServers: (
            ($enFs == "true" ? {
              filesystem: {
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", $root]
              }
            } : {}) +
            ($enGh == "true" ? {
              github: {
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: {
                  GITHUB_PERSONAL_ACCESS_TOKEN: $ghTok,
                  GITHUB_SERVER_URL: $ghSrv,
                  GITHUB_REPOSITORY: $ghRepo,
                  GITHUB_BRANCH: $ghBr
                }
              }
            } : {}) +
            ($enJira == "true" ? {
              jira: {
                command: "npx",
                args: ["-y", "mcp-remote", $jSrv],
                env: {
                  AUTHORIZATION: ("Bearer " + $jTok),
                  JIRA_PROJECT_KEY: $jProj,
                  JIRA_USER_EMAIL: $jEmail
                }
              }
            } : {}) +
            ($enConf == "true" ? {
              confluence: {
                command: "npx",
                args: ["-y", "mcp-remote", $cSrv],
                env: {
                  AUTHORIZATION: ("Bearer " + $cTok),
                  CONFLUENCE_SPACE_KEY: $cSpace,
                  CONFLUENCE_USER_EMAIL: $cEmail
                }
              }
            } : {})
          )
        }')

      if [[ "$(echo "$_local_mcp" | jq '.mcpServers | length')" -gt 0 ]]; then
        cd "${var.workdir}"
        _add_mcp_servers "$_local_mcp"
      fi

      # ── Remote MCP config URLs ─────────────────────────────────────────────
      if [[ -n "${var.mcp_remote_config_urls_csv}" ]]; then
        IFS=',' read -r -a _remote_urls <<< "${var.mcp_remote_config_urls_csv}"
        cd "${var.workdir}"
        for _raw_url in "$${_remote_urls[@]}"; do
          _url="$(echo "$_raw_url" | xargs)"
          [[ -z "$_url" ]] && continue
          _log "Fetching remote MCP config: $_url"
          _rmcp="$(curl -fsSL "$_url")" || { _warn "Failed to fetch $_url; skipping"; continue; }
          echo "$_rmcp" | jq -e '.mcpServers' >/dev/null 2>&1 \
            || { _warn "Invalid MCP schema from $_url; skipping"; continue; }
          _add_mcp_servers "$_rmcp"
        done
      fi

      # ── Custom script MCP servers ──────────────────────────────────────────
      # Format: server-name:/absolute/path/to/executable
      if [[ -n "${var.mcp_custom_scripts_csv}" ]]; then
        IFS=',' read -r -a _cscripts <<< "${var.mcp_custom_scripts_csv}"
        cd "${var.workdir}"
        for _raw_entry in "$${_cscripts[@]}"; do
          _entry="$(echo "$_raw_entry" | xargs)"
          [[ -z "$_entry" ]] && continue
          _csname="$${_entry%%:*}"
          _cspath="$${_entry#*:}"
          if [[ -f "$_cspath" ]]; then
            chmod +x "$_cspath"
            _csjson="$(jq -n --arg cmd "$_cspath" '{"command": $cmd, "args": []}')"
            _log "Registering custom MCP script: $_csname → $_cspath"
            claude mcp add-json "$_csname" "$_csjson" \
              || _warn "Failed to register custom MCP: $_csname"
          else
            _warn "Custom MCP script not found: '$_cspath' (skipping server '$_csname')"
          fi
        done
      fi

      _log "Registered MCP servers:"
      claude mcp list 2>/dev/null || true

    else
      command -v claude >/dev/null 2>&1 || _warn "claude binary not found; skipping MCP registration."
      command -v jq    >/dev/null 2>&1 || _warn "jq not found; skipping MCP registration."
    fi

    _log "Bootstrap complete. Active MCP connectors: ${join(", ", local.enabled_connectors) == "" ? "none" : join(", ", local.enabled_connectors)}"
  EOT
}

# ── Secrets injected as environment variables ─────────────────────────────────

resource "coder_env" "claude_api_key" {
  count    = length(trimspace(var.claude_api_key)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "CLAUDE_API_KEY"
  value    = var.claude_api_key
}

resource "coder_env" "claude_code_oauth_token" {
  count    = length(trimspace(var.claude_code_oauth_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "anthropic_model" {
  count    = length(trimspace(var.claude_model)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_MODEL"
  value    = var.claude_model
}

resource "coder_env" "claude_code_use_bedrock" {
  count    = var.enable_bedrock ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "CLAUDE_CODE_USE_BEDROCK"
  value    = "1"
}

resource "coder_env" "aws_region" {
  count    = var.enable_bedrock ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "AWS_REGION"
  value    = var.aws_region
}

resource "coder_env" "aws_default_region" {
  count    = var.enable_bedrock ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "AWS_DEFAULT_REGION"
  value    = var.aws_region
}

resource "coder_env" "aws_bearer_token_bedrock" {
  count    = length(trimspace(var.aws_bearer_token_bedrock)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "AWS_BEARER_TOKEN_BEDROCK"
  value    = var.aws_bearer_token_bedrock
}

resource "coder_env" "mcp_github_token" {
  count    = length(trimspace(var.mcp_github_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_GITHUB_TOKEN"
  value    = var.mcp_github_token
}

resource "coder_env" "mcp_jira_token" {
  count    = length(trimspace(var.mcp_jira_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_JIRA_TOKEN"
  value    = var.mcp_jira_token
}

resource "coder_env" "mcp_confluence_token" {
  count    = length(trimspace(var.mcp_confluence_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_CONFLUENCE_TOKEN"
  value    = var.mcp_confluence_token
}

# ── Workspace Apps ────────────────────────────────────────────────────────────

resource "coder_app" "claude_code_cli" {
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "${data.coder_workspace.me.access_url}/icon/claude.svg"
  command      = "bash -lc 'cd \"${var.workdir}\" && claude${local.claude_permission_arg}'"
  share        = "owner"
  order        = 1
  tooltip      = "Launch Claude Code in the workspace terminal."
}

resource "coder_app" "claude_auth_setup" {
  agent_id     = coder_agent.main.id
  slug         = "claude-auth"
  display_name = "Claude Auth Setup"
  icon         = "${data.coder_workspace.me.access_url}/icon/lock.svg"
  command      = "bash -lc 'cd \"${var.workdir}\" && claude setup-token'"
  share        = "owner"
  order        = 2
  tooltip      = "Run Claude interactive auth/token setup inside the workspace."
}

resource "coder_app" "code_server" {
  count        = var.enable_code_server ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=${var.workdir}"
  icon         = "${data.coder_workspace.me.access_url}/icon/code.svg"
  share        = "owner"
  order        = 3
  subdomain    = false

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

# ── Docker Container ──────────────────────────────────────────────────────────

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image    = var.container_image
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)
  dns      = ["1.1.1.1"]

  command = [
    "sh",
    "-c",
    <<-EOT
      trap '[ $? -ne 0 ] && echo === Agent exit non-zero. Sleeping to preserve logs... && sleep infinity' EXIT
      ${replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")}
    EOT
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
}

# ── Metadata ──────────────────────────────────────────────────────────────────

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "${data.coder_workspace.me.access_url}/icon/claude.svg"
  hide        = false

  item {
    key   = "workspace_owner"
    value = local.workspace_owner_effective
  }

  item {
    key   = "container_image"
    value = var.container_image
  }

  item {
    key   = "workdir"
    value = var.workdir
  }

  item {
    key   = "git_repo"
    value = length(trimspace(var.git_repo_url)) > 0 ? var.git_repo_url : "none"
  }

  item {
    key   = "claude_auth_mode"
    value = length(trimspace(var.claude_api_key)) > 0 ? "api-key" : length(trimspace(var.claude_code_oauth_token)) > 0 ? "oauth-token" : "interactive-login"
  }

  item {
    key   = "bedrock_enabled"
    value = tostring(var.enable_bedrock)
  }

  item {
    key   = "mcp_connectors"
    value = length(local.enabled_connectors) > 0 ? join(", ", local.enabled_connectors) : "none"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "template_summary" {
  description = "Summary of the universal MCP workspace configuration."
  value = {
    owner          = local.workspace_owner_effective
    owner_email    = local.workspace_owner_email
    container_image = var.container_image
    workdir        = var.workdir
    git = {
      repository = var.git_repo_url
      branch     = var.git_repo_branch
    }
    claude = {
      model        = var.claude_model
      version      = var.claude_code_version
      install_mode = var.install_via_npm ? "npm" : "installer"
      permission   = var.permission_mode
      auth_mode    = length(trimspace(var.claude_api_key)) > 0 ? "api-key" : length(trimspace(var.claude_code_oauth_token)) > 0 ? "oauth-token" : "interactive-login"
    }
    bedrock = {
      enabled    = var.enable_bedrock
      aws_region = var.aws_region
    }
    mcp = {
      filesystem_enabled   = var.enable_mcp_filesystem
      github_enabled       = var.enable_mcp_github
      jira_enabled         = var.enable_mcp_jira
      confluence_enabled   = var.enable_mcp_confluence
      custom_scripts_set   = length(trimspace(var.mcp_custom_scripts_csv)) > 0
      remote_urls_set      = length(trimspace(var.mcp_remote_config_urls_csv)) > 0
      enabled_connectors   = local.enabled_connectors
      allowed_root         = var.mcp_allowed_root
      github_server        = var.mcp_github_server_url
      jira_server          = var.mcp_jira_server_url
      confluence_server    = var.mcp_confluence_server_url
    }
    ide = {
      code_server = var.enable_code_server
      extensions  = local.vscode_extensions
    }
    network = {
      https_proxy_set = length(trimspace(var.https_proxy)) > 0
      http_proxy_set  = length(trimspace(var.http_proxy)) > 0
      no_proxy_set    = length(trimspace(var.no_proxy)) > 0
    }
  }
}
