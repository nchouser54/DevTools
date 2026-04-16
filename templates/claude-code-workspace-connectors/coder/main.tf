terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace to deploy the workspace pod into."
  default     = "coder"
}

variable "storage_size" {
  type        = string
  description = "Size of the persistent home directory volume."
  default     = "10Gi"
}

variable "cpu_request" {
  type        = string
  description = "CPU request for the workspace pod."
  default     = "500m"
}

variable "memory_request" {
  type        = string
  description = "Memory request for the workspace pod."
  default     = "1Gi"
}

variable "cpu_limit" {
  type        = string
  description = "CPU limit for the workspace pod."
  default     = "2"
}

variable "memory_limit" {
  type        = string
  description = "Memory limit for the workspace pod."
  default     = "4Gi"
}

variable "service_account_name" {
  type        = string
  description = "Kubernetes service account name to attach to the workspace pod (used for IRSA/Bedrock IAM access)."
  default     = ""
}

variable "container_image" {
  type        = string
  description = "Container image used for the Claude workspace runtime."
  default     = "codercom/example-universal:ubuntu"
}

variable "workdir" {
  type        = string
  description = "Working directory where Claude Code runs."
  default     = "/home/coder/project"
}

variable "enable_code_server" {
  type        = bool
  description = "Expose code-server as a post-spinup workspace app."
  default     = true
}

variable "git_repo_url" {
  type        = string
  description = "Optional Git repository URL to clone into the workspace on start."
  default     = ""
}

variable "git_repo_branch" {
  type        = string
  description = "Git branch used when cloning or updating the repository."
  default     = "main"
}

variable "vscode_extensions_csv" {
  type        = string
  description = "Optional comma-separated VS Code extension IDs to preinstall (e.g. ms-python.python,amazonwebservices.aws-toolkit-vscode)."
  default     = ""
}

variable "claude_api_key" {
  type        = string
  description = "Anthropic API key for Claude Code. Leave empty to authenticate later or use OAuth token instead."
  default     = ""
  sensitive   = true
}

variable "claude_code_oauth_token" {
  type        = string
  description = "Claude Code OAuth/session token generated from `claude setup-token`. Leave empty when using API key or manual login."
  default     = ""
  sensitive   = true
}

variable "claude_code_version" {
  type        = string
  description = "Claude Code version to install. Use latest or pin to a tested release."
  default     = "latest"
}

variable "install_via_npm" {
  type        = bool
  description = "Install Claude Code via npm instead of the official installer. Useful as a compatibility fallback."
  default     = false
}

variable "claude_model" {
  type        = string
  description = "Optional default Claude model. Leave empty to use Claude defaults."
  default     = ""
}

variable "enable_bedrock" {
  type        = bool
  description = "Enable AWS Bedrock mode for Claude Code. Recommended when authenticating with IAM role credentials."
  default     = true
}

variable "aws_region" {
  type        = string
  description = "AWS region for Bedrock requests (used when enable_bedrock=true)."
  default     = "us-gov-west-1"
}

variable "aws_bearer_token_bedrock" {
  type        = string
  description = "Optional AWS Bedrock bearer token fallback when IAM role credentials are not available in runtime."
  default     = ""
  sensitive   = true
}

variable "permission_mode" {
  type        = string
  description = "Claude permission mode. One of: empty/default/acceptEdits/plan/bypassPermissions."
  default     = "plan"

  validation {
    condition     = contains(["", "default", "acceptEdits", "plan", "bypassPermissions"], var.permission_mode)
    error_message = "permission_mode must be one of: empty, default, acceptEdits, plan, bypassPermissions."
  }
}

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Enable filesystem MCP configuration for Claude Code."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Allowed filesystem root for the filesystem MCP server."
  default     = "/home/coder/project"
}

variable "enable_mcp_github" {
  type        = bool
  description = "Enable GitHub MCP configuration for Claude Code."
  default     = false
}

variable "mcp_github_token" {
  type        = string
  description = "GitHub PAT used by the GitHub MCP server when enabled."
  default     = ""
  sensitive   = true
}

variable "mcp_github_server_url" {
  type        = string
  description = "GitHub or GitHub Enterprise Server URL used by GitHub MCP."
  default     = "https://github.com"
}

variable "mcp_github_repository" {
  type        = string
  description = "Default GitHub repository for GitHub MCP in owner/repo format."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default GitHub branch for GitHub MCP."
  default     = "main"
}

variable "enable_mcp_jira" {
  type        = bool
  description = "Enable Jira MCP configuration for Claude Code."
  default     = false
}

variable "mcp_jira_server_url" {
  type        = string
  description = "Jira MCP endpoint URL for your enterprise deployment."
  default     = "https://jira.example.mil/mcp"
}

variable "mcp_jira_project_key" {
  type        = string
  description = "Default Jira project key used by the Jira MCP server."
  default     = "TEAM"
}

variable "mcp_jira_user_email" {
  type        = string
  description = "Jira user email used by Jira MCP. Leave empty to use workspace owner email when available."
  default     = ""
}

variable "mcp_jira_token" {
  type        = string
  description = "Jira token used by Jira MCP when enabled."
  default     = ""
  sensitive   = true
}

variable "enable_mcp_confluence" {
  type        = bool
  description = "Enable Confluence MCP configuration for Claude Code."
  default     = false
}

variable "mcp_confluence_server_url" {
  type        = string
  description = "Confluence MCP endpoint URL for your enterprise deployment."
  default     = "https://confluence.example.mil/mcp"
}

variable "mcp_confluence_space_key" {
  type        = string
  description = "Default Confluence space key used by the Confluence MCP server."
  default     = "ENG"
}

variable "mcp_confluence_user_email" {
  type        = string
  description = "Confluence user email used by Confluence MCP. Leave empty to use workspace owner email when available."
  default     = ""
}

variable "mcp_confluence_token" {
  type        = string
  description = "Confluence token used by Confluence MCP when enabled."
  default     = ""
  sensitive   = true
}

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
  description = "Optional comma-separated NO_PROXY value for enterprise networks."
  default     = ""
}

variable "mcp_remote_config_urls_csv" {
  type        = string
  description = "Optional comma-separated list of remote URLs returning Claude MCP JSON configuration."
  default     = ""
}

provider "coder" {}

provider "kubernetes" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

data "coder_provisioner" "me" {}

# coder_task is populated when this workspace is launched as a Coder Task.
# When accessed outside a Task context the prompt field is an empty string.
data "coder_task" "me" {}

# coder_task is populated when this workspace is launched as a Coder Task.
# In a normal session, prompt is an empty string and the task block is skipped.
# coder_ai_task wires this template into the Coder Tasks tab.
resource "coder_ai_task" "task" {
  count  = data.coder_workspace.me.start_count
  app_id = coder_app.claude_code_cli.id
}

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

locals {
  workspace_owner_effective  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  workspace_owner_email      = try(data.coder_workspace_owner.me.email, "")
  jira_user_email_effective  = length(trimspace(var.mcp_jira_user_email)) > 0 ? trimspace(var.mcp_jira_user_email) : local.workspace_owner_email
  confluence_user_email_effective = length(trimspace(var.mcp_confluence_user_email)) > 0 ? trimspace(var.mcp_confluence_user_email) : local.workspace_owner_email
  claude_permission_arg      = trimspace(var.permission_mode) != "" ? " --permission-mode ${var.permission_mode}" : ""
  remote_mcp_config_urls = compact([
    for item in split(",", var.mcp_remote_config_urls_csv) : trimspace(item)
  ])
  vscode_extensions = compact([
    for item in split(",", var.vscode_extensions_csv) : trimspace(item)
  ])

  post_spinup_apps = compact([
    "Claude Code",
    "Claude Auth Setup",
    "VS Code",
    "Web Terminal",
    var.enable_code_server ? "code-server" : ""
  ])

  enabled_enterprise_connectors = compact([
    var.enable_mcp_github ? "github" : "",
    var.enable_mcp_jira ? "jira" : "",
    var.enable_mcp_confluence ? "confluence" : "",
  ])

  # MCP server config built in Terraform so the registry module receives a
  # static JSON string — no bash jq required at boot.
  mcp_servers_json = jsonencode({
    mcpServers = merge(
      var.enable_mcp_filesystem ? {
        filesystem = {
          command = "npx"
          args    = ["-y", "@modelcontextprotocol/server-filesystem", var.mcp_allowed_root]
        }
      } : {},
      var.enable_mcp_github ? {
        github = {
          command = "npx"
          args    = ["-y", "@modelcontextprotocol/server-github"]
          env = {
            GITHUB_PERSONAL_ACCESS_TOKEN = var.mcp_github_token
            GITHUB_SERVER_URL            = var.mcp_github_server_url
            GITHUB_REPOSITORY            = var.mcp_github_repository
            GITHUB_BRANCH                = var.mcp_github_branch
          }
        }
      } : {},
      var.enable_mcp_jira ? {
        jira = {
          command = "npx"
          args    = ["-y", "mcp-remote", var.mcp_jira_server_url]
          env = {
            AUTHORIZATION    = "Bearer ${var.mcp_jira_token}"
            JIRA_PROJECT_KEY = var.mcp_jira_project_key
            JIRA_USER_EMAIL  = local.jira_user_email_effective
          }
        }
      } : {},
      var.enable_mcp_confluence ? {
        confluence = {
          command = "npx"
          args    = ["-y", "mcp-remote", var.mcp_confluence_server_url]
          env = {
            AUTHORIZATION         = "Bearer ${var.mcp_confluence_token}"
            CONFLUENCE_SPACE_KEY  = var.mcp_confluence_space_key
            CONFLUENCE_USER_EMAIL = local.confluence_user_email_effective
          }
        }
      } : {}
    )
  })
}

check "claude_auth_inputs" {
  assert {
    condition     = !(length(trimspace(var.claude_api_key)) > 0 && length(trimspace(var.claude_code_oauth_token)) > 0)
    error_message = "Provide either claude_api_key or claude_code_oauth_token, not both."
  }
}

check "enterprise_mcp_inputs" {
  assert {
    condition     = !var.enable_mcp_github || can(regex("^[^/\\s]+/[^/\\s]+$", trimspace(var.mcp_github_repository)))
    error_message = "mcp_github_repository must be in owner/repo format when enable_mcp_github is true."
  }

  assert {
    condition     = !var.enable_mcp_github || length(trimspace(var.mcp_github_token)) > 0
    error_message = "mcp_github_token must be set when enable_mcp_github is true."
  }

  assert {
    condition     = !var.enable_mcp_jira || length(trimspace(var.mcp_jira_server_url)) > 0
    error_message = "mcp_jira_server_url must be set when enable_mcp_jira is true."
  }

  assert {
    condition     = !var.enable_mcp_jira || length(trimspace(var.mcp_jira_token)) > 0
    error_message = "mcp_jira_token must be set when enable_mcp_jira is true."
  }

  assert {
    condition     = !var.enable_mcp_confluence || length(trimspace(var.mcp_confluence_server_url)) > 0
    error_message = "mcp_confluence_server_url must be set when enable_mcp_confluence is true."
  }

  assert {
    condition     = !var.enable_mcp_confluence || length(trimspace(var.mcp_confluence_token)) > 0
    error_message = "mcp_confluence_token must be set when enable_mcp_confluence is true."
  }
}

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
    GIT_AUTHOR_NAME         = local.workspace_owner_effective
    GIT_AUTHOR_EMAIL        = local.workspace_owner_email
    GIT_COMMITTER_NAME      = local.workspace_owner_effective
    GIT_COMMITTER_EMAIL     = local.workspace_owner_email
    ENABLE_MCP_FILESYSTEM   = tostring(var.enable_mcp_filesystem)
    ENABLE_MCP_GITHUB       = tostring(var.enable_mcp_github)
    ENABLE_MCP_JIRA         = tostring(var.enable_mcp_jira)
    ENABLE_MCP_CONFLUENCE   = tostring(var.enable_mcp_confluence)
    MCP_ALLOWED_ROOT        = var.mcp_allowed_root
    MCP_GITHUB_SERVER_URL   = var.mcp_github_server_url
    MCP_GITHUB_REPOSITORY   = var.mcp_github_repository
    MCP_GITHUB_BRANCH       = var.mcp_github_branch
    MCP_JIRA_SERVER_URL     = var.mcp_jira_server_url
    MCP_JIRA_PROJECT_KEY    = var.mcp_jira_project_key
    MCP_JIRA_USER_EMAIL     = local.jira_user_email_effective
    MCP_CONFLUENCE_SERVER_URL = var.mcp_confluence_server_url
    MCP_CONFLUENCE_SPACE_KEY  = var.mcp_confluence_space_key
    MCP_CONFLUENCE_USER_EMAIL = local.confluence_user_email_effective
    MCP_REMOTE_CONFIG_URLS  = var.mcp_remote_config_urls_csv
    ENABLE_BEDROCK          = tostring(var.enable_bedrock)
    AWS_REGION              = var.aws_region
    AWS_DEFAULT_REGION      = var.aws_region
    HTTPS_PROXY             = var.https_proxy
    HTTP_PROXY              = var.http_proxy
    NO_PROXY                = var.no_proxy
    https_proxy             = var.https_proxy
    http_proxy              = var.http_proxy
    no_proxy                = var.no_proxy
  }

  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    export PATH="$HOME/.local/bin:$PATH"
    need_npm="false"

    if [[ "${var.install_via_npm}" == "true" || "${tostring(var.enable_mcp_filesystem)}" == "true" || "${tostring(var.enable_mcp_github)}" == "true" || "${tostring(var.enable_mcp_jira)}" == "true" || "${tostring(var.enable_mcp_confluence)}" == "true" ]]; then
      need_npm="true"
    fi

    if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y --no-install-recommends git curl jq tmux ca-certificates >/dev/null
      if [[ "$need_npm" == "true" ]] && ! command -v npx >/dev/null 2>&1; then
        sudo apt-get install -y --no-install-recommends npm >/dev/null
      fi
    fi

    if [[ -n "${var.vscode_extensions_csv}" ]]; then
      IFS=',' read -r -a vscode_extensions <<< "${var.vscode_extensions_csv}"
      for raw_ext in "$${vscode_extensions[@]}"; do
        ext="$(echo "$raw_ext" | xargs)"
        [[ -z "$ext" ]] && continue
        if command -v code-server >/dev/null 2>&1; then
          code-server --install-extension "$ext" >/dev/null 2>&1 || true
        fi
        if command -v openvscode-server >/dev/null 2>&1; then
          openvscode-server --install-extension "$ext" >/dev/null 2>&1 || true
        fi
      done
    fi

    mkdir -p "$(dirname '${var.workdir}')"

    if [[ -n "${var.git_repo_url}" ]]; then
      if [[ ! -d "${var.workdir}/.git" ]]; then
        rm -rf "${var.workdir}"
        git clone --branch "${var.git_repo_branch}" --single-branch "${var.git_repo_url}" "${var.workdir}"
      else
        cd "${var.workdir}"
        git fetch origin "${var.git_repo_branch}" || true
        git checkout "${var.git_repo_branch}" || true
      fi
    else
      mkdir -p "${var.workdir}"
    fi

    if ! command -v claude >/dev/null 2>&1; then
      if [[ "${var.install_via_npm}" == "true" ]]; then
        if ! command -v npm >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
          sudo apt-get install -y --no-install-recommends npm >/dev/null
        fi
        npm install -g "@anthropic-ai/claude-code@${var.claude_code_version}"
      else
        curl -fsSL claude.ai/install.sh | bash -s -- "${var.claude_code_version}"
      fi
    fi

    export PATH="$HOME/.local/bin:$PATH"

    add_mcp_servers() {
      local mcp_json="$1"
      while IFS= read -r server_name && IFS= read -r server_json; do
        echo "[mcp] registering $server_name"
        claude mcp add-json "$server_name" "$server_json" || true
      done < <(echo "$mcp_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
    }

    if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      if [[ -n "$${CLAUDE_API_KEY:-}" ]]; then
        claude_config="$HOME/.claude.json"
        if [[ -f "$claude_config" ]]; then
          jq --arg workdir "${var.workdir}" --arg apikey "$CLAUDE_API_KEY" '.autoUpdaterStatus = "disabled" |
            .bypassPermissionsModeAccepted = true |
            .hasAcknowledgedCostThreshold = true |
            .hasCompletedOnboarding = true |
            .primaryApiKey = $apikey |
            .projects[$workdir].hasCompletedProjectOnboarding = true |
            .projects[$workdir].hasTrustDialogAccepted = true' "$claude_config" > "$${claude_config}.tmp" && mv "$${claude_config}.tmp" "$claude_config"
        else
          cat > "$claude_config" <<EOF
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
EOF
        fi
      fi

      local_mcp_json=$(jq -n \
        --arg root "${var.mcp_allowed_root}" \
        --arg ghToken "$${MCP_GITHUB_TOKEN:-}" \
        --arg ghServer "${var.mcp_github_server_url}" \
        --arg ghRepo "${var.mcp_github_repository}" \
        --arg ghBranch "${var.mcp_github_branch}" \
        --arg jiraServer "${var.mcp_jira_server_url}" \
        --arg jiraProject "${var.mcp_jira_project_key}" \
        --arg jiraEmail "${local.jira_user_email_effective}" \
        --arg jiraToken "$${MCP_JIRA_TOKEN:-}" \
        --arg confServer "${var.mcp_confluence_server_url}" \
        --arg confSpace "${var.mcp_confluence_space_key}" \
        --arg confEmail "${local.confluence_user_email_effective}" \
        --arg confToken "$${MCP_CONFLUENCE_TOKEN:-}" \
        --arg enableFs "${tostring(var.enable_mcp_filesystem)}" \
        --arg enableGh "${tostring(var.enable_mcp_github)}" \
        --arg enableJira "${tostring(var.enable_mcp_jira)}" \
        --arg enableConfluence "${tostring(var.enable_mcp_confluence)}" \
        '{
          mcpServers: (
            ($enableFs == "true" ? {
              filesystem: {
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-filesystem", $root]
              }
            } : {}) +
            ($enableGh == "true" ? {
              github: {
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: {
                  GITHUB_PERSONAL_ACCESS_TOKEN: $ghToken,
                  GITHUB_SERVER_URL: $ghServer,
                  GITHUB_REPOSITORY: $ghRepo,
                  GITHUB_BRANCH: $ghBranch
                }
              }
            } : {}) +
            ($enableJira == "true" ? {
              jira: {
                command: "npx",
                args: ["-y", "mcp-remote", $jiraServer],
                env: {
                  AUTHORIZATION: ("Bearer " + $jiraToken),
                  JIRA_PROJECT_KEY: $jiraProject,
                  JIRA_USER_EMAIL: $jiraEmail
                }
              }
            } : {}) +
            ($enableConfluence == "true" ? {
              confluence: {
                command: "npx",
                args: ["-y", "mcp-remote", $confServer],
                env: {
                  AUTHORIZATION: ("Bearer " + $confToken),
                  CONFLUENCE_SPACE_KEY: $confSpace,
                  CONFLUENCE_USER_EMAIL: $confEmail
                }
              }
            } : {})
          )
        }')

      if [[ "$(echo "$local_mcp_json" | jq '.mcpServers | length')" -gt 0 ]]; then
        cd "${var.workdir}"
        add_mcp_servers "$local_mcp_json"
      fi

      if [[ -n "${var.mcp_remote_config_urls_csv}" ]]; then
        IFS=',' read -r -a remote_urls <<< "${var.mcp_remote_config_urls_csv}"
        cd "${var.workdir}"
        for raw_url in "$${remote_urls[@]}"; do
          url="$(echo "$raw_url" | xargs)"
          [[ -z "$url" ]] && continue
          echo "[mcp] fetching remote config from $url"
          mcp_json=$(curl -fsSL "$url") || { echo "[mcp] failed to fetch $url"; continue; }
          echo "$mcp_json" | jq -e '.mcpServers' >/dev/null 2>&1 || { echo "[mcp] invalid schema from $url"; continue; }
          add_mcp_servers "$mcp_json"
        done
      fi

      claude mcp list || true
    fi

    # ── Coder Tasks: run the task prompt non-interactively when one is supplied ──
    TASK_PROMPT="${data.coder_task.me.prompt}"
    if [[ -n "$TASK_PROMPT" ]]; then
      echo "[task] Running Task prompt via Claude Code..."
      cd "${var.workdir}"
      claude --print "$TASK_PROMPT"${local.claude_permission_arg} || true
    fi
  EOT
}

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

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.storage_size
      }
    }
  }
}

resource "kubernetes_deployment_v1" "workspace" {
  count = data.coder_workspace.me.start_count

  metadata {
    name      = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/instance" = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
      }
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"     = "coder-workspace"
          "app.kubernetes.io/instance" = "${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
        }
      }

      spec {
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }

        service_account_name = length(trimspace(var.service_account_name)) > 0 ? var.service_account_name : null

        container {
          name    = "workspace"
          image   = var.container_image
          command = ["sh", "-c", coder_agent.main.init_script]

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }

          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }

          volume_mount {
            mount_path = "/home/coder"
            name       = "home-directory"
            read_only  = false
          }
        }

        volume {
          name = "home-directory"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_persistent_volume_claim_v1.home]
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = kubernetes_deployment_v1.workspace[0].id
  icon        = "${data.coder_workspace.me.access_url}/icon/claude.svg"
  hide        = false

  item {
    key   = "namespace"
    value = var.namespace
  }

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
    value = var.git_repo_url != "" ? var.git_repo_url : "none"
  }

  item {
    key   = "code_server"
    value = tostring(var.enable_code_server)
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
    key   = "aws_region"
    value = var.aws_region
  }

  item {
    key   = "enterprise_connectors"
    value = length(local.enabled_enterprise_connectors) > 0 ? join(", ", local.enabled_enterprise_connectors) : "none"
  }
}

output "template_summary" {
  sensitive = true
  value = {
    owner            = local.workspace_owner_effective
    owner_email      = local.workspace_owner_email
    namespace        = var.namespace
    container_image  = var.container_image
    workdir          = var.workdir
    git_repository   = var.git_repo_url
    git_branch       = var.git_repo_branch
    claude_model     = var.claude_model
    bedrock = {
      enabled                   = var.enable_bedrock
      aws_region                = var.aws_region
      using_bearer_token        = length(trimspace(var.aws_bearer_token_bedrock)) > 0
      expected_authn_precedence = "iam-role-or-default-aws-credentials-chain"
    }
    code_server       = var.enable_code_server
    vscode_extensions = local.vscode_extensions
    install_via_npm   = var.install_via_npm
    post_spinup_apps  = local.post_spinup_apps
    mcp = {
      filesystem_enabled  = var.enable_mcp_filesystem
      github_enabled      = var.enable_mcp_github
      jira_enabled        = var.enable_mcp_jira
      confluence_enabled  = var.enable_mcp_confluence
      enabled_connectors  = local.enabled_enterprise_connectors
      github_server       = var.mcp_github_server_url
      jira_server         = var.mcp_jira_server_url
      confluence_server   = var.mcp_confluence_server_url
      allowed_root        = var.mcp_allowed_root
      remote_urls         = local.remote_mcp_config_urls
    }
    network = {
      https_proxy_set = length(trimspace(var.https_proxy)) > 0
      http_proxy_set  = length(trimspace(var.http_proxy)) > 0
      no_proxy_set    = length(trimspace(var.no_proxy)) > 0
    }
    auth_mode = length(trimspace(var.claude_api_key)) > 0 ? "api-key" : length(trimspace(var.claude_code_oauth_token)) > 0 ? "oauth-token" : "interactive-login"
  }
  description = "Summary of the enterprise Claude Code workspace configuration with MCP connectors."
}
