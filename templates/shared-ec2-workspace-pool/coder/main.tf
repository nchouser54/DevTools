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

variable "socket" {
  type        = string
  description = "Docker daemon socket used by the workspace runtime. In shared EC2 pools this points to the host-level Docker daemon."
  default     = "unix:///var/run/docker.sock"
}

variable "workspace_name" {
  type        = string
  description = "Workspace display name override. Leave empty to use active Coder workspace name."
  default     = ""
}

variable "workspace_owner" {
  type        = string
  description = "Team or person that owns the workspace. Leave empty to use active Coder workspace owner."
  default     = ""
}

variable "workspace_profile" {
  type        = string
  description = "Environment profile for toolchain and image selection."
  default     = "python"

  validation {
    condition     = contains(["python", "claude", "devsecops"], lower(var.workspace_profile))
    error_message = "workspace_profile must be one of: python, claude, devsecops."
  }
}

variable "workspace_size" {
  type        = string
  description = "Workspace size profile exposed to users in Coder."
  default     = "medium"

  validation {
    condition     = contains(["small", "medium", "large"], lower(var.workspace_size))
    error_message = "workspace_size must be one of: small, medium, large."
  }
}

variable "image_python" {
  type        = string
  description = "Container image used when workspace_profile=python."
  default     = "mcr.microsoft.com/devcontainers/python:1-3.12-bookworm"
}

variable "image_claude" {
  type        = string
  description = "Container image used when workspace_profile=claude."
  default     = "codercom/example-universal:ubuntu"
}

variable "image_devsecops" {
  type        = string
  description = "Container image used when workspace_profile=devsecops."
  default     = "codercom/example-universal:ubuntu"
}

variable "workdir" {
  type        = string
  description = "Working directory inside the workspace."
  default     = "/home/coder/project"
}

variable "enable_code_server" {
  type        = bool
  description = "Expose code-server app in the workspace."
  default     = true
}

variable "git_repo_url" {
  type        = string
  description = "Optional Git repository URL to clone during startup."
  default     = ""
}

variable "git_repo_branch" {
  type        = string
  description = "Git branch checked out when cloning or updating repository."
  default     = "main"
}

variable "vscode_extensions_csv" {
  type        = string
  description = "Optional comma-separated VS Code extension IDs to preinstall."
  default     = ""
}

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Enable filesystem MCP config generation."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Allowed root path for filesystem MCP server."
  default     = "/home/coder/project"
}

variable "enable_mcp_github" {
  type        = bool
  description = "Enable GitHub MCP config generation."
  default     = false
}

variable "mcp_github_token" {
  type        = string
  description = "GitHub token used by GitHub MCP server when enabled."
  default     = ""
  sensitive   = true
}

variable "mcp_github_server_url" {
  type        = string
  description = "GitHub or GHES URL for MCP GitHub server."
  default     = "https://github.com"
}

variable "mcp_github_repository" {
  type        = string
  description = "Default repository in owner/repo format for GitHub MCP operations."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default branch for GitHub MCP operations."
  default     = "main"
}

provider "docker" {
  host = var.socket
}

provider "coder" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

data "coder_provisioner" "me" {}

locals {
  template_name = length(trimspace(var.workspace_name)) > 0 ? trimspace(var.workspace_name) : try(data.coder_workspace.me.name, "shared-ec2-workspace-pool")
  workspace_owner_effective = length(trimspace(var.workspace_owner)) > 0 ? trimspace(var.workspace_owner) : trimspace(try(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name, "workspace-owner"))
  workspace_profile_effective = lower(var.workspace_profile)
  workspace_size_effective    = lower(var.workspace_size)

  profile_images = {
    python   = var.image_python
    claude   = var.image_claude
    devsecops = var.image_devsecops
  }

  size_profiles = {
    small = {
      cpu      = "2"
      memory   = "4Gi"
      disk     = "20Gi"
      memoryMB = 4096
    }
    medium = {
      cpu      = "4"
      memory   = "8Gi"
      disk     = "40Gi"
      memoryMB = 8192
    }
    large = {
      cpu      = "8"
      memory   = "16Gi"
      disk     = "80Gi"
      memoryMB = 16384
    }
  }

  selected_image = local.profile_images[local.workspace_profile_effective]
  selected_size  = local.size_profiles[local.workspace_size_effective]

  vscode_extensions = compact([
    for item in split(",", var.vscode_extensions_csv) : trimspace(item)
  ])

  post_spinup_apps = compact([
    "VS Code",
    "Web Terminal",
    var.enable_code_server ? "code-server" : ""
  ])
}

check "profile_input_requirements" {
  assert {
    condition     = length(trimspace(local.selected_image)) > 0
    error_message = "Selected workspace profile image is empty. Set image_python/image_claude/image_devsecops appropriately."
  }

  assert {
    condition     = !var.enable_mcp_github || can(regex("^[^/\\s]+/[^/\\s]+$", trimspace(var.mcp_github_repository)))
    error_message = "mcp_github_repository must be in owner/repo format when enable_mcp_github is true."
  }

  assert {
    condition     = !var.enable_mcp_github || length(trimspace(var.mcp_github_token)) > 0
    error_message = "mcp_github_token must be set when enable_mcp_github is true."
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
    WORKSPACE_PROFILE       = local.workspace_profile_effective
    WORKSPACE_SIZE          = local.workspace_size_effective
    GIT_REPO_URL            = var.git_repo_url
    GIT_REPO_BRANCH         = var.git_repo_branch
    ENABLE_MCP_FILESYSTEM   = tostring(var.enable_mcp_filesystem)
    MCP_ALLOWED_ROOT        = var.mcp_allowed_root
    ENABLE_MCP_GITHUB       = tostring(var.enable_mcp_github)
    MCP_GITHUB_SERVER_URL   = var.mcp_github_server_url
    MCP_GITHUB_REPOSITORY   = var.mcp_github_repository
    MCP_GITHUB_BRANCH       = var.mcp_github_branch
  }

  startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    export PATH="$HOME/.local/bin:$PATH"
    need_npm="false"

    if [[ "${tostring(var.enable_mcp_filesystem)}" == "true" || "${tostring(var.enable_mcp_github)}" == "true" || "${local.workspace_profile_effective}" == "claude" ]]; then
      need_npm="true"
    fi

    if command -v sudo >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y --no-install-recommends git curl jq tmux ca-certificates >/dev/null
      if [[ "$need_npm" == "true" ]] && ! command -v npx >/dev/null 2>&1; then
        sudo apt-get install -y --no-install-recommends npm >/dev/null
      fi

      if [[ "${local.workspace_profile_effective}" == "python" ]]; then
        sudo apt-get install -y --no-install-recommends python3-pip python3-venv >/dev/null || true
      fi

      if [[ "${local.workspace_profile_effective}" == "devsecops" ]]; then
        sudo apt-get install -y --no-install-recommends ripgrep unzip >/dev/null || true
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

    if [[ "${local.workspace_profile_effective}" == "claude" ]] && ! command -v claude >/dev/null 2>&1; then
      curl -fsSL claude.ai/install.sh | bash -s -- latest || true
    fi

    add_mcp_servers() {
      local mcp_json="$1"
      while IFS= read -r server_name && IFS= read -r server_json; do
        claude mcp add-json "$server_name" "$server_json" || true
      done < <(echo "$mcp_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
    }

    if command -v jq >/dev/null 2>&1; then
      local_mcp_json=$(jq -n \
        --arg root "${var.mcp_allowed_root}" \
        --arg ghToken "$${MCP_GITHUB_TOKEN:-}" \
        --arg ghServer "${var.mcp_github_server_url}" \
        --arg ghRepo "${var.mcp_github_repository}" \
        --arg ghBranch "${var.mcp_github_branch}" \
        --arg enableFs "${tostring(var.enable_mcp_filesystem)}" \
        --arg enableGh "${tostring(var.enable_mcp_github)}" \
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
            } : {})
          )
        }')

      if command -v claude >/dev/null 2>&1 && [[ "$(echo "$local_mcp_json" | jq '.mcpServers | length')" -gt 0 ]]; then
        cd "${var.workdir}"
        add_mcp_servers "$local_mcp_json"
      fi
    fi
  EOT
}

resource "coder_env" "mcp_github_token" {
  count    = length(trimspace(var.mcp_github_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_GITHUB_TOKEN"
  value    = var.mcp_github_token
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image    = local.selected_image
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)
  dns      = ["1.1.1.1"]
  memory   = local.selected_size.memoryMB

  command = [
    "sh",
    "-c",
    <<-EOT
      trap '[ $? -ne 0 ] && echo === Agent script exited with non-zero code. Sleeping infinitely to preserve logs... && sleep infinity' EXIT
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

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  icon        = "${data.coder_workspace.me.access_url}/icon/server.svg"
  hide        = false

  item {
    key   = "workspace_owner"
    value = local.workspace_owner_effective
  }

  item {
    key   = "workspace_profile"
    value = local.workspace_profile_effective
  }

  item {
    key   = "workspace_size"
    value = local.workspace_size_effective
  }

  item {
    key   = "selected_image"
    value = local.selected_image
  }

  item {
    key   = "resource_class"
    value = "cpu=${local.selected_size.cpu}, memory=${local.selected_size.memory}, disk=${local.selected_size.disk}"
  }

  item {
    key   = "shared_host_model"
    value = "true"
  }
}

output "template_summary" {
  value = {
    name             = local.template_name
    owner            = local.workspace_owner_effective
    workspace_profile = local.workspace_profile_effective
    workspace_size    = local.workspace_size_effective
    selected_image    = local.selected_image
    resources         = local.selected_size
    workdir           = var.workdir
    git = {
      repository = var.git_repo_url
      branch     = var.git_repo_branch
    }
    mcp = {
      filesystem_enabled = var.enable_mcp_filesystem
      github_enabled     = var.enable_mcp_github
      allowed_root       = var.mcp_allowed_root
      github_repository  = var.mcp_github_repository
      github_branch      = var.mcp_github_branch
    }
    cost_model = {
      shared_ec2_host_pool = true
      note                 = "Use Coder auto-stop and workspace quotas to maximize EC2 consolidation."
    }
    post_spinup_apps = local.post_spinup_apps
  }
  description = "Summary of shared-EC2 workspace pool template settings."
}
