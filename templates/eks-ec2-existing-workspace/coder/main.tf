terraform {
  required_version = ">= 1.5.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region where the target EC2 instance resides."
  default     = "us-gov-west-1"
}

variable "ec2_instance_id" {
  type        = string
  description = "Instance ID of the existing EC2 to attach as a Coder workspace (e.g. i-0123456789abcdef0). The instance must have the SSM agent installed and an instance profile that allows SSM."
}

variable "os_type" {
  type        = string
  description = "Operating system of the target instance: linux or windows."
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], lower(var.os_type))
    error_message = "os_type must be 'linux' or 'windows'."
  }
}

variable "arch" {
  type        = string
  description = "CPU architecture of the target EC2 instance: amd64 or arm64. Determines which Coder agent binary is downloaded."
  default     = "amd64"

  validation {
    condition     = contains(["amd64", "arm64"], lower(var.arch))
    error_message = "arch must be 'amd64' or 'arm64'."
  }
}

variable "coder_workdir" {
  type        = string
  description = "Working directory for the Coder agent on the target instance. Linux default: /home/coder. Windows default: C:\\Users\\coder."
  default     = ""
}

variable "coder_user" {
  type        = string
  description = "OS-level user the Coder agent runs as on a Linux instance. Leave empty to run as the SSM document execution user (ssm-user or root). Has no effect on Windows."
  default     = ""
}

variable "ssm_execution_timeout_seconds" {
  type        = number
  description = "Seconds to allow the SSM Run Command to complete agent bootstrap before SSM marks the execution as timed out."
  default     = 3600
}

variable "enable_xrdp" {
  type        = bool
  description = "Enable XRDP on Linux instances so users can connect to a Linux desktop via RDP tunneled through Coder. Ignored for Windows."
  default     = false
}

variable "xrdp_port" {
  type        = number
  description = "XRDP listen port on Linux instances when enable_xrdp is true."
  default     = 3389
}

# ── MCP variables ─────────────────────────────────────────────────────────────

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Register the filesystem MCP server for Claude Code on the target instance."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Filesystem root exposed to the filesystem MCP server."
  default     = "/home/coder/project"
}

variable "enable_mcp_github" {
  type        = bool
  description = "Register the GitHub MCP server for Claude Code. Requires mcp_github_token."
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
  description = "Default GitHub repository in owner/repo format."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default GitHub branch for GitHub MCP."
  default     = "main"
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
}

provider "coder" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# ── Validate the target instance is reachable ─────────────────────────────────

data "aws_instance" "target" {
  instance_id = var.ec2_instance_id
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  workspace_owner = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  os_lower        = lower(var.os_type)
  is_windows      = local.os_lower == "windows"

  workdir_effective = trimspace(var.coder_workdir) != "" ? trimspace(var.coder_workdir) : (
    local.is_windows ? "C:\\Users\\coder" : "/home/coder"
  )

  # Workspace slug used to keep SSM document names unique per workspace
  workspace_slug = "${data.coder_workspace.me.id}"

  # Target instance AZ (needed for metadata only)
  instance_az = data.aws_instance.target.availability_zone

  # Wrap the Coder init_script to handle Linux coder-user switching if requested.
  # On Windows the init_script is already PowerShell-ready.
  linux_bootstrap = trimspace(var.coder_user) != "" ? <<-BASH
    #!/usr/bin/env bash
    set -euo pipefail
    id '${var.coder_user}' >/dev/null 2>&1 || useradd -m -s /bin/bash '${var.coder_user}'
    su '${var.coder_user}' -lc '${coder_agent.main.init_script}'
  BASH
  : coder_agent.main.init_script

  # Use the raw init_script for both paths (su wrapper only if coder_user is set for Linux)
  linux_init_script   = trimspace(var.coder_user) != "" ? local.linux_bootstrap : coder_agent.main.init_script
  windows_init_script = coder_agent.main.init_script
}

# ── Coder Agent ───────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = local.is_windows ? "windows" : "linux"
  arch = lower(var.arch)
  dir  = local.workdir_effective

  display_apps {
    vscode                 = !local.is_windows
    vscode_insiders        = false
    ssh_helper             = !local.is_windows
    port_forwarding_helper = true
    web_terminal           = !local.is_windows
  }

  startup_script_behavior = "non-blocking"
  connection_timeout      = 600

  env = {
    GIT_AUTHOR_NAME     = local.workspace_owner
    GIT_AUTHOR_EMAIL    = try(data.coder_workspace_owner.me.email, "")
    GIT_COMMITTER_NAME  = local.workspace_owner
    GIT_COMMITTER_EMAIL = try(data.coder_workspace_owner.me.email, "")
    CODER_WORKDIR       = local.workdir_effective
    ENABLE_XRDP         = tostring(var.enable_xrdp)
    XRDP_PORT           = tostring(var.xrdp_port)
  }

  # For Linux: optionally install and configure MCP servers after agent connects.
  # For Windows: stub (MCP Claude Code on Windows uses the same mechanism but
  # operators should adapt the script to a PowerShell equivalent).
  startup_script = local.is_windows ? "" : <<-EOT
    #!/usr/bin/env bash
    export PATH="$HOME/.local/bin:$PATH"

    _log()  { echo "[coder-mcp] $*"; }
    _warn() { echo "[coder-mcp][WARN] $*" >&2; }

    # Install npx if missing (multi-distro)
    if ! command -v npx >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq >/dev/null 2>&1 && sudo apt-get install -y --no-install-recommends nodejs npm >/dev/null 2>&1 || true
      elif command -v apk >/dev/null 2>&1; then
        (command -v sudo >/dev/null 2>&1 && sudo apk add --no-cache nodejs npm >/dev/null 2>&1) || apk add --no-cache nodejs npm >/dev/null 2>&1 || true
      elif command -v dnf >/dev/null 2>&1; then
        (command -v sudo >/dev/null 2>&1 && sudo dnf install -y nodejs npm >/dev/null 2>&1) || dnf install -y nodejs npm >/dev/null 2>&1 || true
      elif command -v yum >/dev/null 2>&1; then
        (command -v sudo >/dev/null 2>&1 && sudo yum install -y nodejs npm >/dev/null 2>&1) || yum install -y nodejs npm >/dev/null 2>&1 || true
      fi
    fi

    # Install jq if missing
    if ! command -v jq >/dev/null 2>&1; then
      command -v apt-get >/dev/null 2>&1 && sudo apt-get install -y --no-install-recommends jq >/dev/null 2>&1 || true
      command -v apk     >/dev/null 2>&1 && (sudo apk add --no-cache jq >/dev/null 2>&1 || apk add --no-cache jq >/dev/null 2>&1) || true
      command -v dnf     >/dev/null 2>&1 && (sudo dnf install -y jq >/dev/null 2>&1 || dnf install -y jq >/dev/null 2>&1) || true
    fi

    if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      _add_mcp_servers() {
        local _json="$1"
        while IFS= read -r _n && IFS= read -r _j; do
          _log "Registering MCP server: $_n"
          claude mcp add-json "$_n" "$_j" || _warn "Failed: $_n"
        done < <(echo "$_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
      }

      _mcp=$(jq -n \
        --arg root   "${var.mcp_allowed_root}" \
        --arg ghTok  "$${MCP_GITHUB_TOKEN:-}" \
        --arg ghSrv  "${var.mcp_github_server_url}" \
        --arg ghRepo "${var.mcp_github_repository}" \
        --arg ghBr   "${var.mcp_github_branch}" \
        --arg enFs   "${tostring(var.enable_mcp_filesystem)}" \
        --arg enGh   "${tostring(var.enable_mcp_github)}" \
        '{
          mcpServers: (
            ($enFs == "true" ? {
              filesystem: {command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", $root]}
            } : {}) +
            ($enGh == "true" ? {
              github: {
                command: "npx",
                args: ["-y", "@modelcontextprotocol/server-github"],
                env: {GITHUB_PERSONAL_ACCESS_TOKEN: $ghTok, GITHUB_SERVER_URL: $ghSrv, GITHUB_REPOSITORY: $ghRepo, GITHUB_BRANCH: $ghBr}
              }
            } : {})
          )
        }')

      [[ "$(echo "$_mcp" | jq '.mcpServers | length')" -gt 0 ]] && \
        mkdir -p "${var.mcp_allowed_root}" && cd "${var.mcp_allowed_root}" && \
        _add_mcp_servers "$_mcp"
    fi

    # Optional Linux desktop via XRDP
    if [[ "${tostring(var.enable_xrdp)}" == "true" ]]; then
      _log "Configuring XRDP on Linux instance"

      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq >/dev/null 2>&1 || true
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xrdp xorgxrdp xfce4 dbus-x11 >/dev/null 2>&1 || true
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y xrdp xorgxrdp xfce4-session dbus-x11 xorg-x11-server-Xorg >/dev/null 2>&1 || true
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y xrdp xorgxrdp dbus-x11 xorg-x11-server-Xorg >/dev/null 2>&1 || true
      elif command -v apk >/dev/null 2>&1; then
        (sudo apk add --no-cache xrdp xorgxrdp xfce4 dbus >/dev/null 2>&1 || apk add --no-cache xrdp xorgxrdp xfce4 dbus >/dev/null 2>&1) || true
      fi

      echo "startxfce4" > "$HOME/.xsession"

      if [[ -f /etc/xrdp/xrdp.ini ]]; then
        sudo sed -i "s/^port=.*/port=${var.xrdp_port}/" /etc/xrdp/xrdp.ini || true
      fi

      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl enable xrdp >/dev/null 2>&1 || true
        sudo systemctl restart xrdp >/dev/null 2>&1 || true
      else
        sudo service xrdp restart >/dev/null 2>&1 || true
      fi

      _log "XRDP enabled. Use: coder port-forward ${data.coder_workspace.me.name} --tcp ${var.xrdp_port}:${var.xrdp_port}"
    fi
  EOT
}

# ── MCP token env var ─────────────────────────────────────────────────────────

resource "coder_env" "mcp_github_token" {
  count    = length(trimspace(var.mcp_github_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_GITHUB_TOKEN"
  value    = var.mcp_github_token
}

# ── SSM Document — delivers the Coder agent init script to the EC2 ────────────
#
# Created outside of start_count so content is always up to date.
# The SSM Association (below) is gated by start_count and triggers execution.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_document" "coder_agent_init" {
  name            = "CoderAgentInit-${local.workspace_slug}"
  document_type   = "Command"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Bootstrap Coder workspace agent — workspace ${data.coder_workspace.me.name}"
    mainSteps = [
      local.is_windows
      ? {
        action = "aws:runPowerShellScript"
        name   = "runCoderAgentWindows"
        inputs = {
          runCommand       = split("\n", local.windows_init_script)
          timeoutSeconds   = tostring(var.ssm_execution_timeout_seconds)
          workingDirectory = local.workdir_effective
        }
      }
      : {
        action = "aws:runShellScript"
        name   = "runCoderAgentLinux"
        inputs = {
          runCommand       = split("\n", local.linux_init_script)
          timeoutSeconds   = tostring(var.ssm_execution_timeout_seconds)
          workingDirectory = "/tmp"
        }
      }
    ]
  })

  tags = {
    "coder:workspace" = data.coder_workspace.me.name
    "coder:owner"     = local.workspace_owner
    "managed-by"      = "coder-terraform"
  }
}

# ── SSM Association — triggers the document on the target instance ────────────
#
# Created only when workspace is running (start_count == 1).
# Deletion (workspace stop) does NOT stop the agent process on the EC2 —
# the agent detects workspace state via the Coder server and exits on its own.
# On the next workspace start a new association re-triggers the document.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_association" "coder_agent" {
  count = data.coder_workspace.me.start_count

  name             = aws_ssm_document.coder_agent_init.name
  association_name = "coder-agent-${substr(local.workspace_slug, 0, 47)}"

  targets {
    key    = "InstanceIds"
    values = [var.ec2_instance_id]
  }

  # Run immediately on creation, not on a schedule
  apply_only_at_cron_interval = false
  compliance_severity         = "UNSPECIFIED"
  max_concurrency             = "1"
  max_errors                  = "0"

  depends_on = [aws_ssm_document.coder_agent_init]
}

# ── Coder Apps ────────────────────────────────────────────────────────────────

resource "coder_app" "web_terminal" {
  count        = local.is_windows ? 0 : 1
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Web Terminal"
  icon         = "${data.coder_workspace.me.access_url}/icon/terminal.svg"
  command      = "bash -l"
  share        = "owner"
  order        = 1
  tooltip      = "Open a terminal in the workspace."
}

resource "coder_app" "linux_xrdp" {
  count        = !local.is_windows && var.enable_xrdp ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "xrdp"
  display_name = "Linux XRDP"
  icon         = "${data.coder_workspace.me.access_url}/icon/desktop.svg"
  command      = "bash -lc 'echo XRDP: run coder port-forward ${data.coder_workspace.me.name} --tcp ${var.xrdp_port}:${var.xrdp_port} and connect your RDP client to localhost:${var.xrdp_port}'"
  share        = "owner"
  order        = 2
  tooltip      = "Tunnel XRDP through Coder and connect your RDP client to localhost."
}

resource "coder_app" "rdp_info" {
  count        = local.is_windows ? 1 : 0
  agent_id     = coder_agent.main.id
  slug         = "rdp"
  display_name = "Windows RDP"
  icon         = "${data.coder_workspace.me.access_url}/icon/desktop.svg"
  command      = "powershell -Command \"echo 'RDP: run  coder port-forward ${data.coder_workspace.me.name} --tcp 3389:3389  then connect to localhost:3389'\""
  share        = "owner"
  order        = 1
  tooltip      = "To RDP: run 'coder port-forward <workspace> --tcp 3389:3389' then open your RDP client to localhost:3389."
}

# ── Metadata ──────────────────────────────────────────────────────────────────

resource "coder_metadata" "instance_info" {
  resource_id = aws_ssm_document.coder_agent_init.id
  icon        = "${data.coder_workspace.me.access_url}/icon/aws.svg"
  hide        = false

  item {
    key   = "ec2_instance_id"
    value = var.ec2_instance_id
  }

  item {
    key   = "instance_state"
    value = data.aws_instance.target.instance_state
  }

  item {
    key   = "instance_type"
    value = data.aws_instance.target.instance_type
  }

  item {
    key   = "availability_zone"
    value = local.instance_az
  }

  item {
    key   = "os_type"
    value = var.os_type
  }

  item {
    key   = "arch"
    value = var.arch
  }

  item {
    key   = "agent_delivery"
    value = "ssm-run-command"
  }

  item {
    key   = "xrdp_enabled"
    value = tostring(!local.is_windows && var.enable_xrdp)
  }

  item {
    key   = "mcp_connectors"
    value = join(", ", compact([
      var.enable_mcp_filesystem ? "filesystem" : "",
      var.enable_mcp_github ? "github" : "",
    ]))
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "template_summary" {
  description = "Summary of the existing-EC2 workspace configuration."
  value = {
    workspace_owner  = local.workspace_owner
    ec2_instance_id  = var.ec2_instance_id
    instance_type    = data.aws_instance.target.instance_type
    instance_state   = data.aws_instance.target.instance_state
    instance_az      = local.instance_az
    os_type          = var.os_type
    arch             = var.arch
    workdir          = local.workdir_effective
    aws_region       = var.aws_region
    agent_delivery   = "ssm-run-command"
    ssm_document     = aws_ssm_document.coder_agent_init.name
    mcp = {
      filesystem_enabled = var.enable_mcp_filesystem
      github_enabled     = var.enable_mcp_github
    }
    xrdp = {
      enabled = !local.is_windows && var.enable_xrdp
      port    = var.xrdp_port
      howto   = !local.is_windows && var.enable_xrdp ? "coder port-forward ${data.coder_workspace.me.name} --tcp ${var.xrdp_port}:${var.xrdp_port} then connect RDP client to localhost:${var.xrdp_port}" : "disabled"
    }
    rdp_howto = local.is_windows ? "coder port-forward ${data.coder_workspace.me.name} --tcp 3389:3389 -- then connect RDP client to localhost:3389" : "n/a"
  }
}
