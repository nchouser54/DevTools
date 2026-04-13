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
  description = "AWS GovCloud region where the ASG and instances will be deployed."
  default     = "us-gov-west-1"
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use for workspace instances (e.g. ami-0123456789abcdef0). Must exist in the target region."
}

variable "instance_type" {
  type        = string
  description = "Primary EC2 instance type for Spot allocation (e.g. t3.medium, m5.xlarge)."
  default     = "t3.medium"
}

variable "instance_type_fallbacks" {
  type        = list(string)
  description = "Additional instance types for Spot pool diversification. Increases Spot availability if primary type is unavailable."
  default     = []
}

variable "os_type" {
  type        = string
  description = "Operating system family of the AMI: linux or windows."
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], lower(var.os_type))
    error_message = "os_type must be 'linux' or 'windows'."
  }
}

variable "subnet_id" {
  type        = string
  description = "VPC subnet ID where instances will be placed. Must have outbound HTTPS access to Coder server."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the security group. Auto-detected from subnet_id if omitted."
  default     = ""
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair name for out-of-band SSH access."
  default     = ""
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name to attach to instances. Grants instance-level AWS permissions."
  default     = ""
}

variable "associate_public_ip" {
  type        = bool
  description = "Associate a public IP with the instance. Required if subnet has no NAT or private routing."
  default     = false
}

# ── EBS & Storage ─────────────────────────────────────────────────────────────

variable "root_volume_size_gb" {
  type        = number
  description = "Root EBS volume size in GiB."
  default     = 30
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS volume type (gp3, gp2, io1, etc.)."
  default     = "gp3"
}

variable "home_volume_size_gb" {
  type        = number
  description = "Persistent home EBS volume size in GiB. Survives instance replacement."
  default     = 50
}

variable "home_volume_type" {
  type        = string
  description = "EBS volume type for persistent home (gp3 recommended)."
  default     = "gp3"
}

variable "home_volume_iops" {
  type        = number
  description = "IOPS for gp3 home volume (min 3000, max 16000)."
  default     = 3000
}

variable "home_device_name" {
  type        = string
  description = "Device name for persistent home EBS on Linux (e.g. /dev/xvdh). NVMe remapping handled automatically."
  default     = "/dev/xvdh"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional AWS resource tags."
  default     = {}
}

# ── Auto Scaling Group Configuration ──────────────────────────────────────────

variable "asg_min_size" {
  type        = number
  description = "Minimum instances in ASG. Typically 1 for single workspace."
  default     = 1
}

variable "asg_max_size" {
  type        = number
  description = "Maximum instances in ASG. Set to 1 for single workspace; increase for shared pools."
  default     = 1
}

variable "asg_desired_capacity" {
  type        = number
  description = "Desired instance count. Coder will set this to 1 on start, 0 on stop."
  default     = 1
}

variable "spot_instance_pools" {
  type        = number
  description = "Number of Spot capacity pools for diversification. Higher = more resilient to interruption."
  default     = 2
}

variable "spot_allocation_strategy" {
  type        = string
  description = "Spot allocation strategy: capacity-optimized (recommended), lowest-price, or diversified."
  default     = "capacity-optimized"

  validation {
    condition     = contains(["capacity-optimized", "lowest-price", "diversified"], var.spot_allocation_strategy)
    error_message = "Must be capacity-optimized, lowest-price, or diversified."
  }
}

variable "spot_max_price" {
  type        = string
  description = "Maximum Spot bid price per hour. Leave empty to use current Spot price (on-demand price cap)."
  default     = ""
}

variable "on_demand_percentage" {
  type        = number
  description = "Percentage of capacity reserved for on-demand instances (0-100). 0 = 100% Spot (max savings). Higher values reduce interruption risk at higher cost."
  default     = 0

  validation {
    condition     = var.on_demand_percentage >= 0 && var.on_demand_percentage <= 100
    error_message = "on_demand_percentage must be between 0 and 100."
  }
}

# ── User Data & Proxy ─────────────────────────────────────────────────────────

variable "https_proxy" {
  type        = string
  description = "Optional HTTPS proxy URL for isolated VPCs."
  default     = ""
}

variable "http_proxy" {
  type        = string
  description = "Optional HTTP proxy URL."
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated NO_PROXY hosts/CIDRs to bypass proxy."
  default     = "169.254.169.254,169.254.170.2,localhost,127.0.0.1"
}

variable "user_data_extra" {
  type        = string
  description = "Extra shell commands (Linux) or PowerShell (Windows) to run before agent starts."
  default     = ""
}

variable "enable_xrdp" {
  type        = bool
  description = "Enable XRDP on Linux for graphical desktop access. Ignored on Windows."
  default     = false
}

variable "xrdp_port" {
  type        = number
  description = "XRDP listen port on Linux when enabled."
  default     = 3389
}

# ── MCP Configuration ─────────────────────────────────────────────────────────

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Register filesystem MCP server for Claude Code."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Root path exposed to filesystem MCP server."
  default     = "/home/coder/project"
}

variable "enable_mcp_github" {
  type        = bool
  description = "Register GitHub MCP server. Requires mcp_github_token."
  default     = false
}

variable "mcp_github_token" {
  type        = string
  description = "GitHub Personal Access Token for GitHub MCP."
  default     = ""
  sensitive   = true
}

variable "mcp_github_server_url" {
  type        = string
  description = "GitHub API server URL (GitHub or GitHub Enterprise)."
  default     = "https://github.com"
}

variable "mcp_github_repository" {
  type        = string
  description = "Default GitHub repository in owner/repo format."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default GitHub branch."
  default     = "main"
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
}

provider "coder" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# ── Validate and lookup the AMI ───────────────────────────────────────────────

data "aws_ami" "workspace" {
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
  owners = ["self", "amazon", "aws-marketplace"]

  most_recent = true
}

# Derive VPC from subnet when not explicitly provided
data "aws_subnet" "target" {
  id = var.subnet_id
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  workspace_owner = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  workspace_email = try(data.coder_workspace_owner.me.email, "")
  is_windows      = lower(var.os_type) == "windows"

  # Map AMI architecture to Coder agent architecture
  ami_arch   = data.aws_ami.workspace.architecture
  coder_arch = local.ami_arch == "arm64" ? "arm64" : "amd64"

  # VPC ID: explicit var or derive from subnet
  vpc_id_effective = length(trimspace(var.vpc_id)) > 0 ? trimspace(var.vpc_id) : data.aws_subnet.target.vpc_id

  # Workspace-unique slug for AWS resource naming
  ws_slug = "${lower(replace(local.workspace_owner, "/[^a-z0-9]/", "-"))}-${substr(data.coder_workspace.me.id, 0, 8)}"

  # Availability zone from subnet
  availability_zone = data.aws_subnet.target.availability_zone

  # Common tags for all AWS resources
  common_tags = merge(var.additional_tags, {
    "coder:workspace"   = data.coder_workspace.me.name
    "coder:owner"       = local.workspace_owner
    "coder:template"    = "eks-ec2-asg-spot-workspace"
    "managed-by"        = "coder-terraform"
  })

  # Instance types for mixed-instance policy
  instance_types = concat([var.instance_type], var.instance_type_fallbacks)

  # ── Linux user-data bootstrap script ───────────────────────────────────────
  linux_userdata = base64encode(<<-USERDATA
    #!/usr/bin/env bash
    set -euo pipefail
    exec > >(tee /var/log/coder-userdata.log | logger -t coder-userdata) 2>&1

    echo "==> coder: user-data bootstrap starting"

    # ── Proxy settings ────────────────────────────────────────────────────────
    %{if length(trimspace(var.https_proxy)) > 0}
    export HTTPS_PROXY="${var.https_proxy}"
    export https_proxy="${var.https_proxy}"
    %{endif}
    %{if length(trimspace(var.http_proxy)) > 0}
    export HTTP_PROXY="${var.http_proxy}"
    export http_proxy="${var.http_proxy}"
    %{endif}
    %{if length(trimspace(var.no_proxy)) > 0}
    export NO_PROXY="${var.no_proxy}"
    export no_proxy="${var.no_proxy}"
    %{endif}

    # ── Base dependencies ─────────────────────────────────────────────────────
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y --no-install-recommends \
        curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
      yum install -y curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache curl jq git tmux ca-certificates util-linux >/dev/null 2>&1
    fi

    # ── Mount persistent home EBS volume ───────────────────────────────────────
    HOME_DEVICE="${var.home_device_name}"
    # Resolve NVMe name mapping on Nitro instances
    if [[ ! -b "$HOME_DEVICE" ]]; then
      for nvme_dev in /dev/nvme?n1; do
        [[ -b "$nvme_dev" ]] || continue
        if nvme id-ns "$nvme_dev" 2>/dev/null | grep -q "$(echo "$HOME_DEVICE" | sed 's|/dev/||')"; then
          HOME_DEVICE="$nvme_dev"
          break
        fi
      done
      # Fallback heuristic for NVMe mapping
      [[ ! -b "$HOME_DEVICE" && -b "/dev/nvme1n1" ]] && HOME_DEVICE="/dev/nvme1n1"
    fi

    if [[ -b "$HOME_DEVICE" ]]; then
      echo "==> coder: home device found: $HOME_DEVICE"
      # Format if unformatted (first attach)
      if ! blkid "$HOME_DEVICE" >/dev/null 2>&1; then
        echo "==> coder: formatting $HOME_DEVICE as ext4"
        mkfs.ext4 -L coder-home "$HOME_DEVICE"
      fi
      mkdir -p /home/coder
      mount "$HOME_DEVICE" /home/coder
      echo "$HOME_DEVICE /home/coder ext4 defaults,nofail 0 2" >> /etc/fstab
      echo "==> coder: home volume mounted at /home/coder"
    else
      echo "==> coder: [WARN] home device ${var.home_device_name} not found; using ephemeral root"
    fi

    # ── Create coder user ─────────────────────────────────────────────────────
    id coder >/dev/null 2>&1 || useradd -m -s /bin/bash coder
    chown -R coder:coder /home/coder 2>/dev/null || true
    mkdir -p /home/coder/project
    chown coder:coder /home/coder/project

    # ── Optional Linux desktop via XRDP ───────────────────────────────────────
    %{if var.enable_xrdp}
    echo "==> coder: enabling XRDP"
    if command -v apt-get >/dev/null 2>&1; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xrdp xorgxrdp xfce4 dbus-x11 >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y xrdp xorgxrdp xfce4-session dbus-x11 xorg-x11-server-Xorg >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
      yum install -y xrdp xorgxrdp dbus-x11 xorg-x11-server-Xorg >/dev/null 2>&1 || true
    elif command -v apk >/dev/null 2>&1; then
      apk add --no-cache xrdp xorgxrdp xfce4 dbus >/dev/null 2>&1 || true
    fi

    echo "startxfce4" > /home/coder/.xsession
    chown coder:coder /home/coder/.xsession

    if [[ -f /etc/xrdp/xrdp.ini ]]; then
      sed -i "s/^port=.*/port=${var.xrdp_port}/" /etc/xrdp/xrdp.ini || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
      systemctl enable xrdp >/dev/null 2>&1 || true
      systemctl restart xrdp >/dev/null 2>&1 || true
    else
      service xrdp restart >/dev/null 2>&1 || true
    fi
    %{endif}

    # ── Operator-supplied extra bootstrap ─────────────────────────────────────
    ${var.user_data_extra}

    # ── Start Coder agent ─────────────────────────────────────────────────────
    echo "==> coder: starting Coder agent"
    CODER_INIT_SCRIPT=$(echo '${base64encode(coder_agent.main.init_script)}' | base64 -d)
    export CODER_AGENT_TOKEN="${coder_agent.main.token}"
    su coder -lc "$CODER_INIT_SCRIPT" &
    echo "==> coder: bootstrap complete"
  USERDATA
  )

  # ── Windows user-data bootstrap (PowerShell) ──────────────────────────────
  windows_userdata = base64encode(<<-WINUD
    <powershell>
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $ErrorActionPreference = "Continue"

    # Proxy settings
    %{if length(trimspace(var.https_proxy)) > 0}
    [System.Environment]::SetEnvironmentVariable("HTTPS_PROXY", "${var.https_proxy}", "Machine")
    %{endif}
    %{if length(trimspace(var.http_proxy)) > 0}
    [System.Environment]::SetEnvironmentVariable("HTTP_PROXY", "${var.http_proxy}", "Machine")
    %{endif}
    %{if length(trimspace(var.no_proxy)) > 0}
    [System.Environment]::SetEnvironmentVariable("NO_PROXY", "${var.no_proxy}", "Machine")
    %{endif}

    # Create coder local user
    if (-not (Get-LocalUser -Name "coder" -ErrorAction SilentlyContinue)) {
      $pw = [System.GUID]::NewGuid().ToString() + "Aa1!"
      New-LocalUser -Name "coder" -Password (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -FullName "Coder Workspace" -Description "Coder workspace agent user"
      Add-LocalGroupMember -Group "Administrators" -Member "coder"
    }

    # Enable RDP
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
      -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    # Agent token
    [System.Environment]::SetEnvironmentVariable("CODER_AGENT_TOKEN", "${coder_agent.main.token}", "Machine")

    # Run agent init script
    ${coder_agent.main.init_script}
    </powershell>
    <persist>true</persist>
  WINUD
  )
}

# ── Coder Agent ───────────────────────────────────────────────────────────────

resource "coder_agent" "main" {
  os   = local.is_windows ? "windows" : "linux"
  arch = local.coder_arch
  dir  = local.is_windows ? "C:\\Users\\coder" : "/home/coder"

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
    GIT_AUTHOR_EMAIL    = local.workspace_email
    GIT_COMMITTER_NAME  = local.workspace_owner
    GIT_COMMITTER_EMAIL = local.workspace_email
    HTTPS_PROXY         = var.https_proxy
    HTTP_PROXY          = var.http_proxy
    NO_PROXY            = var.no_proxy
    https_proxy         = var.https_proxy
    http_proxy          = var.http_proxy
    no_proxy            = var.no_proxy
    ENABLE_XRDP         = tostring(var.enable_xrdp)
    XRDP_PORT           = tostring(var.xrdp_port)
  }

  # MCP server installation (Linux only)
  startup_script = local.is_windows ? "" : <<-EOT
    #!/usr/bin/env bash
    export PATH="$HOME/.local/bin:$PATH"

    _log()  { echo "[coder-mcp] $*"; }
    _warn() { echo "[coder-mcp][WARN] $*" >&2; }

    # Install node/npm for MCP servers
    if ! command -v npx >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y --no-install-recommends nodejs npm >/dev/null 2>&1 || true
      elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y nodejs npm >/dev/null 2>&1 || true
      elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y nodejs npm >/dev/null 2>&1 || true
      elif command -v apk >/dev/null 2>&1; then
        sudo apk add --no-cache nodejs npm >/dev/null 2>&1 || apk add --no-cache nodejs npm >/dev/null 2>&1 || true
      fi
    fi

    command -v jq >/dev/null 2>&1 || {
      command -v apt-get >/dev/null 2>&1 && sudo apt-get install -y --no-install-recommends jq >/dev/null 2>&1 || true
      command -v dnf     >/dev/null 2>&1 && sudo dnf install -y jq >/dev/null 2>&1 || true
      command -v yum     >/dev/null 2>&1 && sudo yum install -y jq >/dev/null 2>&1 || true
      command -v apk     >/dev/null 2>&1 && (sudo apk add --no-cache jq >/dev/null 2>&1 || apk add --no-cache jq >/dev/null 2>&1) || true
    }

    if command -v claude >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      _add_mcp() {
        local _j="$1"
        while IFS= read -r _n && IFS= read -r _s; do
          _log "Registering MCP: $_n"
          claude mcp add-json "$_n" "$_s" || _warn "Failed: $_n"
        done < <(echo "$_j" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
      }

      _mcp=$(jq -n \
        --arg root  "${var.mcp_allowed_root}" \
        --arg ghTok "$${MCP_GITHUB_TOKEN:-}" \
        --arg ghSrv "${var.mcp_github_server_url}" \
        --arg ghRep "${var.mcp_github_repository}" \
        --arg ghBr  "${var.mcp_github_branch}" \
        --arg enFs  "${tostring(var.enable_mcp_filesystem)}" \
        --arg enGh  "${tostring(var.enable_mcp_github)}" \
        '{
          mcpServers: (
            ($enFs == "true" ? {filesystem: {command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", $root]}} : {}) +
            ($enGh == "true" ? {github: {command: "npx", args: ["-y", "@modelcontextprotocol/server-github"],
              env: {GITHUB_PERSONAL_ACCESS_TOKEN: $ghTok, GITHUB_SERVER_URL: $ghSrv, GITHUB_REPOSITORY: $ghRep, GITHUB_BRANCH: $ghBr}}} : {})
          )
        }')

      [[ "$(echo "$_mcp" | jq '.mcpServers | length')" -gt 0 ]] && \
        mkdir -p "${var.mcp_allowed_root}" && cd "${var.mcp_allowed_root}" && \
        _add_mcp "$_mcp"
    fi
  EOT
}

resource "coder_env" "mcp_github_token" {
  count    = length(trimspace(var.mcp_github_token)) > 0 ? 1 : 0
  agent_id = coder_agent.main.id
  name     = "MCP_GITHUB_TOKEN"
  value    = var.mcp_github_token
}

# ── Workspace Apps ────────────────────────────────────────────────────────────

resource "coder_app" "web_terminal" {
  count        = local.is_windows ? 0 : 1
  agent_id     = coder_agent.main.id
  slug         = "terminal"
  display_name = "Web Terminal"
  icon         = "${data.coder_workspace.me.access_url}/icon/terminal.svg"
  command      = "bash -l"
  share        = "owner"
  order        = 1
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
  command      = "powershell -Command \"Write-Host 'RDP: run  coder port-forward ${data.coder_workspace.me.name} --tcp 3389:3389  then connect to localhost:3389'\""
  share        = "owner"
  order        = 1
  tooltip      = "Run: coder port-forward <workspace> --tcp 3389:3389 then RDP to localhost:3389"
}

# ── Security Group ────────────────────────────────────────────────────────────
# Outbound-only: Coder agent connects outbound; inbound tunneled via relay.

resource "aws_security_group" "workspace" {
  name        = "coder-workspace-${local.ws_slug}"
  description = "Coder workspace security group — outbound-only. SSH/RDP tunneled via agent."
  vpc_id      = local.vpc_id_effective

  egress {
    description = "Allow all outbound traffic for Coder agent connectivity"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "coder-workspace-${local.ws_slug}"
  })
}

# ── Persistent Home EBS Volume ────────────────────────────────────────────────
# NOT gated by workspace start count; survives ASG churn.

resource "aws_ebs_volume" "home" {
  availability_zone = local.availability_zone
  size              = var.home_volume_size_gb
  type              = var.home_volume_type
  iops              = var.home_volume_type == "gp3" ? var.home_volume_iops : null
  encrypted         = true

  tags = merge(local.common_tags, {
    Name = "coder-home-${local.ws_slug}"
  })
}

# ── Launch Template ───────────────────────────────────────────────────────────
# Defines instance configuration (image, type, user-data, metadata, etc.)
# for the Auto Scaling Group.

resource "aws_launch_template" "developer_ami" {
  name_prefix   = "coder-spot-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.workspace.id]

  # CPU credits for t-series burstable instances
  credit_specification {
    cpu_credits = "unlimited"
  }

  # Root volume
  block_device_mappings {
    device_name = data.aws_ami.workspace.root_device_name

    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = var.root_volume_type
      delete_on_termination = true
      encrypted             = true
      iops                  = var.root_volume_type == "gp3" ? 3000 : null
    }
  }

  # Additional EBS for persistent home (attached via aws_volume_attachment)
  # Listed here for clarity, but attachment is managed separately to allow
  # the volume to survive ASG instance termination.

  # IMDSv2 enforcement (security best practice)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = local.is_windows ? local.windows_userdata : local.linux_userdata

  tag_specifications {
    resource_type = "instance"
    tags          = local.common_tags
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.common_tags
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Data source: Find running instances in the ASG ──────────────────────────

data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:aws:autoscaling:groupName"
    values = [aws_autoscaling_group.developer_workspace.name]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }

  depends_on = [aws_autoscaling_group.developer_workspace]
}

# Workspace is RUNNING if the ASG has a running instance
locals {
  instance_id = length(data.aws_instances.asg_instances.ids) > 0 ? data.aws_instances.asg_instances.ids[0] : ""
}

# ── Auto Scaling Group (Spot Instances) ───────────────────────────────────────
# Manages instance lifecycle. When desired_capacity=0, terminates. When =1, launches.

resource "aws_autoscaling_group" "developer_workspace" {
  name              = "coder-workspace-asg-${local.ws_slug}"
  vpc_zone_identifier = [var.subnet_id]

  # Coder will set these via terraform apply when starting/stopping
  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Mixed instances policy: allows Spot + optional on-demand fallback
  mixed_instances_policy {
    instances_distribution {
      # On-demand fallback percentage (0 = 100% Spot, max cost savings)
      on_demand_percentage_above_base_capacity = var.on_demand_percentage
      # Number of Spot capacity pools to diversify
      spot_instance_pools = var.spot_instance_pools
      # Spot allocation strategy
      spot_allocation_strategy = var.spot_allocation_strategy
      # Spot max price (empty = use current Spot price, capped at on-demand)
      spot_max_price = length(trimspace(var.spot_max_price)) > 0 ? var.spot_max_price : ""
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.developer_ami.id
        version            = "$Latest"
      }

      # Primary instance type + fallbacks for pool diversification
      dynamic "overrides" {
        for_each = local.instance_types
        content {
          instance_type = overrides.value
        }
      }
    }
  }

  # Replace instances gracefully on ASG updates
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 0
    }
  }

  termination_policies = ["OldestInstance"]

  tag {
    key                 = "Name"
    value               = "coder-workspace-${local.ws_slug}"
    propagate_to_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_to_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_launch_template.developer_ami]
}

# ── Volume Attachment: Persistent Home to Instance ───────────────────────────
# Only attach if an instance is running (count gates this).
# On Spot interruption, ASG replaces the instance and user-data re-mounts.

resource "aws_volume_attachment" "home" {
  device_name = var.home_device_name
  volume_id   = aws_ebs_volume.home.id
  instance_id = local.instance_id

  # Only attempt attachment if instance exists
  count = length(local.instance_id) > 0 ? 1 : 0

  # Allow re-attachment on instance replacement (ASG churn)
  skip_destroy = false
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "agent_id" {
  description = "ID of the Coder agent"
  value       = coder_agent.main.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.developer_workspace.name
}

output "instance_id" {
  description = "EC2 instance ID (if running)"
  value       = local.instance_id
  sensitive   = false
}

output "instance_type" {
  description = "EC2 instance type"
  value       = var.instance_type
}

output "ami_id" {
  description = "AMI ID in use"
  value       = var.ami_id
}

output "home_volume_id" {
  description = "Persistent home EBS volume ID"
  value       = aws_ebs_volume.home.id
}

output "security_group_id" {
  description = "Security group ID for the workspace"
  value       = aws_security_group.workspace.id
}
