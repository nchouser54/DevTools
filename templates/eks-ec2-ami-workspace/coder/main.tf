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
  description = "AWS GovCloud region where the EC2 instance will be launched."
  default     = "us-gov-west-1"
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use for the workspace EC2 instance (e.g. ami-0123456789abcdef0). Must exist in the target region."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type (e.g. t3.medium, m5.xlarge, c5.2xlarge)."
  default     = "t3.medium"
}

variable "os_type" {
  type        = string
  description = "Operating system family of the AMI: linux or windows. Determines how user-data and apps are configured."
  default     = "linux"

  validation {
    condition     = contains(["linux", "windows"], lower(var.os_type))
    error_message = "os_type must be 'linux' or 'windows'."
  }
}

variable "subnet_id" {
  type        = string
  description = "VPC subnet ID where the EC2 instance will be placed. Must have outbound HTTPS access to the Coder server."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the security group. Must be the VPC that contains subnet_id."
  default     = ""
}

variable "key_name" {
  type        = string
  description = "Optional EC2 key pair name for out-of-band SSH access (in addition to the Coder agent). Leave empty to omit the key pair."
  default     = ""
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name to attach to the EC2 instance. Should allow SSM (optional but recommended) and any application-level permissions."
  default     = ""
}

variable "associate_public_ip" {
  type        = bool
  description = "Associate a public IP address with the instance. Required when the subnet has no NAT Gateway or private routing to the Coder server."
  default     = false
}

variable "root_volume_size_gb" {
  type        = number
  description = "Root EBS volume size in GiB."
  default     = 30
}

variable "root_volume_type" {
  type        = string
  description = "Root EBS volume type."
  default     = "gp3"
}

variable "home_volume_size_gb" {
  type        = number
  description = "Size of the persistent home EBS volume in GiB. This volume survives workspace stop/start cycles."
  default     = 50
}

variable "home_volume_type" {
  type        = string
  description = "EBS volume type for the persistent home volume."
  default     = "gp3"
}

variable "home_volume_iops" {
  type        = number
  description = "IOPS for gp3 home volume (minimum 3000, maximum 16000)."
  default     = 3000
}

variable "home_device_name" {
  type        = string
  description = "Device name for the persistent home EBS volume as seen by the Linux kernel. Change to xvdf/xvdg etc. if xvdh conflicts."
  default     = "/dev/xvdh"
}

variable "additional_tags" {
  type        = map(string)
  description = "Additional AWS resource tags to apply to the EC2 instance and EBS volumes."
  default     = {}
}

# ── MCP variables ─────────────────────────────────────────────────────────────

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Register the filesystem MCP server for Claude Code on the workspace."
  default     = true
}

variable "mcp_allowed_root" {
  type        = string
  description = "Filesystem root exposed to the filesystem MCP server."
  default     = "/home/coder/project"
}

variable "enable_mcp_github" {
  type        = bool
  description = "Register the GitHub MCP server. Requires mcp_github_token."
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

# ── Enterprise Network Proxy ──────────────────────────────────────────────────

variable "https_proxy" {
  type        = string
  description = "Optional HTTPS proxy URL for instances in isolated VPCs."
  default     = ""
}

variable "http_proxy" {
  type        = string
  description = "Optional HTTP proxy URL."
  default     = ""
}

variable "no_proxy" {
  type        = string
  description = "Comma-separated NO_PROXY hosts / CIDRs to bypass the proxy."
  default     = "169.254.169.254,169.254.170.2,localhost,127.0.0.1"
}

variable "user_data_extra" {
  type        = string
  description = "Optional extra shell commands to append to the Linux user-data bootstrap (before the Coder agent starts). Use for custom package installs or environment setup."
  default     = ""
}

variable "enable_xrdp" {
  type        = bool
  description = "Enable XRDP on Linux AMIs so users can connect to a Linux desktop via RDP tunneled through Coder. Ignored for Windows."
  default     = false
}

variable "xrdp_port" {
  type        = number
  description = "XRDP listen port on Linux instances when enable_xrdp is true."
  default     = 3389
}

# ── Providers ─────────────────────────────────────────────────────────────────

provider "aws" {
  region = var.aws_region
}

provider "coder" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

# ── Validate and look up the AMI ──────────────────────────────────────────────

data "aws_ami" "workspace" {
  filter {
    name   = "image-id"
    values = [var.ami_id]
  }
  owners = ["self", "amazon", "aws-marketplace"]

  most_recent = true
}

# Derive the subnet's VPC when vpc_id is not supplied
data "aws_subnet" "target" {
  id = var.subnet_id
}

# ── Locals ────────────────────────────────────────────────────────────────────

locals {
  workspace_owner = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  workspace_email = try(data.coder_workspace_owner.me.email, "")
  is_windows      = lower(var.os_type) == "windows"

  # Map AMI architecture to Coder agent arch
  ami_arch   = data.aws_ami.workspace.architecture
  coder_arch = local.ami_arch == "arm64" ? "arm64" : "amd64"

  # VPC: prefer explicit var; fall back to subnet's VPC
  vpc_id_effective = length(trimspace(var.vpc_id)) > 0 ? trimspace(var.vpc_id) : data.aws_subnet.target.vpc_id

  # Workspace-unique name slug for AWS resource naming
  ws_slug = "${lower(replace(local.workspace_owner, "/[^a-z0-9]/", "-"))}-${substr(data.coder_workspace.me.id, 0, 8)}"

  # EC2 availability zone matches the subnet
  availability_zone = data.aws_subnet.target.availability_zone

  # Tags applied to all managed resources
  common_tags = merge(var.additional_tags, {
    "coder:workspace"   = data.coder_workspace.me.name
    "coder:owner"       = local.workspace_owner
    "coder:template"    = "eks-ec2-ami-workspace"
    "managed-by"        = "coder-terraform"
  })

  # ── Linux user-data ────────────────────────────────────────────────────────
  # Mounts the persistent home EBS volume, creates the coder user, runs
  # any operator-supplied extra commands, then starts the Coder agent.
  # The init_script is base64-encoded to avoid shell quoting issues.
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
    # Resolve NVMe name mapping (e.g. /dev/nvme1n1) on Nitro instances
    if [[ ! -b "$HOME_DEVICE" ]]; then
      for nvme_dev in /dev/nvme?n1; do
        [[ -b "$nvme_dev" ]] || continue
        if nvme id-ns "$nvme_dev" 2>/dev/null | grep -q "$(echo "$HOME_DEVICE" | sed 's|/dev/||')"; then
          HOME_DEVICE="$nvme_dev"
          break
        fi
      done
      # Fallback: attempt common NVMe mapping heuristic
      [[ ! -b "$HOME_DEVICE" && -b "/dev/nvme1n1" ]] && HOME_DEVICE="/dev/nvme1n1"
    fi

    if [[ -b "$HOME_DEVICE" ]]; then
      echo "==> coder: home device found: $HOME_DEVICE"
      # Only format on first attach (unformatted / no filesystem signature)
      if ! blkid "$HOME_DEVICE" >/dev/null 2>&1; then
        echo "==> coder: formatting $HOME_DEVICE as ext4 (first use)"
        mkfs.ext4 -L coder-home "$HOME_DEVICE"
      fi
      mkdir -p /home/coder
      mount "$HOME_DEVICE" /home/coder
      echo "$HOME_DEVICE /home/coder ext4 defaults,nofail 0 2" >> /etc/fstab
      echo "==> coder: home volume mounted at /home/coder"
    else
      echo "==> coder: [WARN] home device ${var.home_device_name} not found; using ephemeral storage"
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

    # ── Decode and run Coder agent init script as coder user ──────────────────
    echo "==> coder: starting Coder agent"
    CODER_INIT_SCRIPT=$(echo '${base64encode(coder_agent.main.init_script)}' | base64 -d)
    export CODER_AGENT_TOKEN="${coder_agent.main.token}"
    echo "==> coder: bootstrap complete"
    su coder -lc "$CODER_INIT_SCRIPT" &
  USERDATA
  )

  # ── Windows user-data (PowerShell wrapped in EC2 tags) ────────────────────
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

    # Create coder local user if not present
    if (-not (Get-LocalUser -Name "coder" -ErrorAction SilentlyContinue)) {
      $pw = [System.GUID]::NewGuid().ToString() + "Aa1!"
      New-LocalUser -Name "coder" -Password (ConvertTo-SecureString $pw -AsPlainText -Force) `
        -FullName "Coder Workspace" -Description "Coder workspace agent user"
      Add-LocalGroupMember -Group "Administrators" -Member "coder"
    }

    # Ensure RDP is enabled
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
      -Name "fDenyTSConnections" -Value 0 -ErrorAction SilentlyContinue
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

    # Set agent token env var
    [System.Environment]::SetEnvironmentVariable("CODER_AGENT_TOKEN", "${coder_agent.main.token}", "Machine")

    # Run Coder agent init script
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

  # For Linux: install MCP servers after the agent connects and the home dir
  # is available. For Windows: stub (adapt to PowerShell as needed).
  startup_script = local.is_windows ? "" : <<-EOT
    #!/usr/bin/env bash
    export PATH="$HOME/.local/bin:$PATH"

    _log()  { echo "[coder-mcp] $*"; }
    _warn() { echo "[coder-mcp][WARN] $*" >&2; }

    # Install node/npx using multi-distro bootstrap
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
# Deny all inbound, allow all outbound. The Coder agent connects outbound
# to the Coder server. SSH and RDP are tunneled through the agent — no
# open inbound ports are needed.

resource "aws_security_group" "workspace" {
  name        = "coder-workspace-${local.ws_slug}"
  description = "Coder workspace security group — outbound only. SSH/RDP tunneled via Coder agent."
  vpc_id      = local.vpc_id_effective

  egress {
    description = "Allow all outbound traffic (Coder agent needs HTTPS to reach Coder server)"
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
# NOT gated by start_count — survives workspace stop/start cycles.

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

# ── EC2 Instance ──────────────────────────────────────────────────────────────
# Gated by start_count — terminated on stop, recreated on start.
# Home data persists in aws_ebs_volume.home.

resource "aws_instance" "workspace" {
  count = data.coder_workspace.me.start_count

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.workspace.id]
  associate_public_ip_address = var.associate_public_ip
  key_name                    = length(trimspace(var.key_name)) > 0 ? trimspace(var.key_name) : null
  iam_instance_profile        = length(trimspace(var.instance_profile_name)) > 0 ? trimspace(var.instance_profile_name) : null

  user_data_base64 = local.is_windows ? local.windows_userdata : local.linux_userdata

  # Ensure IMDSv2 only (security best practice for GovCloud workloads)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_size           = var.root_volume_size_gb
    volume_type           = var.root_volume_type
    encrypted             = true
    delete_on_termination = true
  }

  # Terminate rather than stop on workspace stop (home data is on separate EBS)
  instance_initiated_shutdown_behavior = "terminate"

  tags = merge(local.common_tags, {
    Name = "coder-workspace-${local.ws_slug}"
  })

  volume_tags = local.common_tags

  lifecycle {
    # Prevent root block device recreation when Terraform diffs are triggered
    # by workspace start_count changes
    ignore_changes = [user_data_base64]
  }
}

# ── Persistent Home Volume Attachment ─────────────────────────────────────────

resource "aws_volume_attachment" "home" {
  count = data.coder_workspace.me.start_count

  device_name  = var.home_device_name
  volume_id    = aws_ebs_volume.home.id
  instance_id  = aws_instance.workspace[0].id
  force_detach = true

  # Detach before the instance terminates
  skip_destroy = false
}

# ── Metadata ──────────────────────────────────────────────────────────────────

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = aws_instance.workspace[0].id
  icon        = "${data.coder_workspace.me.access_url}/icon/aws.svg"
  hide        = false

  item {
    key   = "instance_id"
    value = aws_instance.workspace[0].id
  }

  item {
    key   = "instance_type"
    value = var.instance_type
  }

  item {
    key   = "ami_id"
    value = var.ami_id
  }

  item {
    key   = "ami_name"
    value = data.aws_ami.workspace.name
  }

  item {
    key   = "architecture"
    value = data.aws_ami.workspace.architecture
  }

  item {
    key   = "availability_zone"
    value = local.availability_zone
  }

  item {
    key   = "os_type"
    value = var.os_type
  }

  item {
    key   = "home_volume_id"
    value = aws_ebs_volume.home.id
  }

  item {
    key   = "home_volume_size_gb"
    value = tostring(var.home_volume_size_gb)
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

resource "coder_metadata" "home_volume" {
  resource_id = aws_ebs_volume.home.id
  icon        = "${data.coder_workspace.me.access_url}/icon/aws.svg"
  hide        = false

  item {
    key   = "volume_id"
    value = aws_ebs_volume.home.id
  }

  item {
    key   = "size_gb"
    value = tostring(var.home_volume_size_gb)
  }

  item {
    key   = "type"
    value = var.home_volume_type
  }

  item {
    key   = "encrypted"
    value = "true"
  }

  item {
    key   = "lifecycle"
    value = "persistent — survives workspace stop/start"
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "template_summary" {
  description = "Summary of the EC2 AMI workspace configuration."
  value = {
    workspace_owner = local.workspace_owner
    aws_region      = var.aws_region
    ami = {
      id           = var.ami_id
      name         = data.aws_ami.workspace.name
      architecture = data.aws_ami.workspace.architecture
      os_type      = var.os_type
    }
    instance = {
      type              = var.instance_type
      subnet_id         = var.subnet_id
      availability_zone = local.availability_zone
      public_ip         = var.associate_public_ip
    }
    storage = {
      root_volume_gb = var.root_volume_size_gb
      home_volume_id = aws_ebs_volume.home.id
      home_volume_gb = var.home_volume_size_gb
      home_encrypted = true
      persistence    = "home EBS volume persists across workspace stop/start"
    }
    agent = {
      arch            = local.coder_arch
      delivery        = "ec2-user-data"
    }
    mcp = {
      filesystem_enabled = var.enable_mcp_filesystem
      github_enabled     = var.enable_mcp_github
    }
    xrdp = {
      enabled = !local.is_windows && var.enable_xrdp
      port    = var.xrdp_port
      howto   = !local.is_windows && var.enable_xrdp ? "coder port-forward ${data.coder_workspace.me.name} --tcp ${var.xrdp_port}:${var.xrdp_port} then connect RDP client to localhost:${var.xrdp_port}" : "disabled"
    }
    rdp_howto = local.is_windows ? "coder port-forward ${data.coder_workspace.me.name} --tcp 3389:3389 then RDP to localhost:3389" : "n/a"
  }
}
