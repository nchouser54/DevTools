terraform {
  required_version = ">= 1.5.0"
}

variable "workspace_name" {
  type        = string
  description = "Workspace name shown in Coder."
  default     = "python-ai-workspace"
}

variable "workspace_owner" {
  type        = string
  description = "Workspace owner or team."
  default     = "platform-team"
}

variable "workspace_size" {
  type        = string
  description = "Workspace size profile exposed to users in Coder."
  default     = "medium"

  validation {
    condition     = contains(["small", "medium", "large"], var.workspace_size)
    error_message = "workspace_size must be one of: small, medium, large."
  }
}

variable "git_repo_url" {
  type        = string
  description = "Optional Git repository URL to clone when the workspace initializes."
  default     = ""
}

variable "git_repo_branch" {
  type        = string
  description = "Git branch checked out during workspace initialization."
  default     = "main"
}

variable "mcp_allowed_root" {
  type        = string
  description = "Allowed root path for filesystem MCP server."
  default     = "/workspaces"
}

variable "enable_mcp_filesystem" {
  type        = bool
  description = "Enable filesystem MCP configuration in the generated servers.json."
  default     = true
}

variable "enable_mcp_github" {
  type        = bool
  description = "Enable GitHub MCP configuration in the generated servers.json."
  default     = false
}

variable "mcp_github_server_url" {
  type        = string
  description = "GitHub or GitHub Enterprise Server URL used by MCP GitHub server."
  default     = "https://github.com"
}

variable "mcp_github_repository" {
  type        = string
  description = "Default GitHub repository target in owner/repo format for MCP tooling."
  default     = "owner/repo"
}

variable "mcp_github_branch" {
  type        = string
  description = "Default Git branch target for MCP GitHub server operations."
  default     = "main"
}

variable "mcp_github_token" {
  type        = string
  description = "GitHub token used by the MCP GitHub server when enabled."
  default     = ""
  sensitive   = true
}

variable "enable_mcp_jira" {
  type        = bool
  description = "Enable Jira MCP configuration in the generated servers.json."
  default     = false
}

variable "mcp_jira_server_url" {
  type        = string
  description = "Jira server URL used by MCP Atlassian server."
  default     = "https://your-org.atlassian.net"
}

variable "mcp_jira_project_key" {
  type        = string
  description = "Default Jira project key used by MCP tooling."
  default     = "TEAM"
}

variable "mcp_jira_user_email" {
  type        = string
  description = "Jira user email associated with API token."
  default     = "you@example.com"
}

variable "mcp_jira_token" {
  type        = string
  description = "Jira API token used by MCP Atlassian server."
  default     = ""
  sensitive   = true
}

variable "enable_mcp_confluence" {
  type        = bool
  description = "Enable Confluence MCP configuration in the generated servers.json."
  default     = false
}

variable "mcp_confluence_server_url" {
  type        = string
  description = "Confluence server URL used by MCP Atlassian server."
  default     = "https://your-org.atlassian.net/wiki"
}

variable "mcp_confluence_space_key" {
  type        = string
  description = "Default Confluence space key used by MCP tooling."
  default     = "ENG"
}

variable "mcp_confluence_user_email" {
  type        = string
  description = "Confluence user email associated with API token."
  default     = "you@example.com"
}

variable "mcp_confluence_token" {
  type        = string
  description = "Confluence API token used by MCP Atlassian server."
  default     = ""
  sensitive   = true
}

variable "auto_render_mcp_config" {
  type        = bool
  description = "Render an MCP configuration file automatically when workspace init runs."
  default     = true
}

variable "enable_claude_code_cli" {
  type        = bool
  description = "Attempt installation of Claude Code CLI during workspace initialization."
  default     = false
}

variable "claude_code_mcp_config_path" {
  type        = string
  description = "Optional path where rendered MCP config should be copied for Claude Code CLI."
  default     = ""
}

variable "vscode_mcp_config_path" {
  type        = string
  description = "Optional path where rendered MCP config should be copied for editor tooling."
  default     = ""
}

locals {
  template_name = var.workspace_name
  template_tags = ["python", "ai", "mcp", "git", "bootstrap"]

  workspace_size_profiles = {
    small = {
      cpu    = "2"
      memory = "4Gi"
      disk   = "20Gi"
    }
    medium = {
      cpu    = "4"
      memory = "8Gi"
      disk   = "40Gi"
    }
    large = {
      cpu    = "8"
      memory = "16Gi"
      disk   = "80Gi"
    }
  }

  selected_profile = local.workspace_size_profiles[var.workspace_size]
}

output "template_summary" {
  value = {
    name           = local.template_name
    owner          = var.workspace_owner
    tags           = local.template_tags
    workspace_size = var.workspace_size
    resources      = local.selected_profile
    git = {
      repository = var.git_repo_url
      branch     = var.git_repo_branch
    }
    mcp = {
      auto_rendered            = var.auto_render_mcp_config
      allowed_root             = var.mcp_allowed_root
      filesystem_enabled       = var.enable_mcp_filesystem
      github_enabled           = var.enable_mcp_github
      jira_enabled             = var.enable_mcp_jira
      confluence_enabled       = var.enable_mcp_confluence
      claude_code_cli_enabled  = var.enable_claude_code_cli
      claude_config_path       = var.claude_code_mcp_config_path
      vscode_config_path       = var.vscode_mcp_config_path
    }
    startup_env = {
      WORKSPACE_SIZE                 = var.workspace_size
      GIT_REPO_URL                   = var.git_repo_url
      GIT_REPO_BRANCH                = var.git_repo_branch
      MCP_ALLOWED_ROOT               = var.mcp_allowed_root
      MCP_ENABLE_FILESYSTEM          = tostring(var.enable_mcp_filesystem)
      MCP_ENABLE_GITHUB              = tostring(var.enable_mcp_github)
      MCP_GITHUB_SERVER_URL          = var.mcp_github_server_url
      MCP_GITHUB_REPOSITORY          = var.mcp_github_repository
      MCP_GITHUB_BRANCH              = var.mcp_github_branch
      MCP_GITHUB_TOKEN               = var.mcp_github_token != "" ? "<provided>" : "<empty>"
      MCP_ENABLE_JIRA                = tostring(var.enable_mcp_jira)
      MCP_JIRA_SERVER_URL            = var.mcp_jira_server_url
      MCP_JIRA_PROJECT_KEY           = var.mcp_jira_project_key
      MCP_JIRA_USER_EMAIL            = var.mcp_jira_user_email
      MCP_JIRA_TOKEN                 = var.mcp_jira_token != "" ? "<provided>" : "<empty>"
      MCP_ENABLE_CONFLUENCE          = tostring(var.enable_mcp_confluence)
      MCP_CONFLUENCE_SERVER_URL      = var.mcp_confluence_server_url
      MCP_CONFLUENCE_SPACE_KEY       = var.mcp_confluence_space_key
      MCP_CONFLUENCE_USER_EMAIL      = var.mcp_confluence_user_email
      MCP_CONFLUENCE_TOKEN           = var.mcp_confluence_token != "" ? "<provided>" : "<empty>"
      AUTO_RENDER_MCP_CONFIG         = tostring(var.auto_render_mcp_config)
      ENABLE_CLAUDE_CODE_CLI         = tostring(var.enable_claude_code_cli)
      CLAUDE_CODE_MCP_CONFIG_PATH    = var.claude_code_mcp_config_path
      VSCODE_MCP_CONFIG_PATH         = var.vscode_mcp_config_path
    }
    init_command = "/usr/local/bin/devtools-init-workspace"
  }
  description = "Workspace metadata and initialization contract for Coder operators."
}
