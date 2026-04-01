# Universal MCP Workspace

A Coder workspace template that automatically installs and configures **Jira, Confluence, GitHub, Filesystem, and custom-script MCP servers** regardless of what container image or repository you choose.

## Key features

| Feature | Detail |
|---|---|
| **Any container image** | Multi-distro node/npm bootstrap (apt → apk → yum/dnf → nvm → Node binary download) installs MCP dependencies on Debian, Ubuntu, Alpine, RHEL, Rocky, and even distroless images |
| **Filesystem MCP on by default** | Gives Claude read/write access to the workdir immediately, with zero credentials required |
| **GitHub MCP** | `@modelcontextprotocol/server-github` — enable with a single PAT |
| **Jira MCP** | `mcp-remote` proxy — works with Atlassian Cloud and self-hosted instances |
| **Confluence MCP** | `mcp-remote` proxy — works with Atlassian Cloud and self-hosted instances |
| **Custom script MCP** | Register any local shell script as an MCP server via `mcp_custom_scripts_csv` |
| **Remote config URLs** | Pull additional MCP configs from HTTPS endpoints at workspace start |
| **Repo-agnostic** | MCP registration happens in the startup script, independent of which git repo is cloned |
| **Bedrock-first auth** | Defaults to IAM role / AWS credential chain; API key and OAuth token also supported |
| **code-server** | Optional browser VS Code — enabled by default |

## Quick start

### 1. Minimal — filesystem MCP only (no credentials needed)

```hcl
container_image       = "ubuntu:22.04"
workdir               = "/home/coder/project"
enable_mcp_filesystem = true
```

### 2. All four MCP servers enabled

```hcl
container_image        = "python:3.12-slim"   # ← any image works
workdir                = "/home/coder/project"

enable_mcp_filesystem  = true
mcp_allowed_root       = "/home/coder/project"

enable_mcp_github      = true
mcp_github_token       = "ghp_xxxx"
mcp_github_repository  = "myorg/myrepo"

enable_mcp_jira        = true
mcp_jira_server_url    = "https://mcp.atlassian.com/v1/sse"  # Atlassian Cloud
mcp_jira_token         = "your-jira-api-token"
mcp_jira_project_key   = "DEVOPS"

enable_mcp_confluence  = true
mcp_confluence_server_url = "https://mcp.atlassian.com/v1/sse"
mcp_confluence_token   = "your-confluence-api-token"
mcp_confluence_space_key  = "ENG"
```

### 3. Custom script MCP server

```hcl
mcp_custom_scripts_csv = "my-internal-tool:/opt/mcp/internal.sh,audit-log:/opt/mcp/audit.sh"
```

The startup script will `chmod +x` each script path and register it with Claude Code automatically.

## Variables reference

### Runtime

| Variable | Default | Description |
|---|---|---|
| `socket` | `unix:///var/run/docker.sock` | Docker daemon socket |
| `container_image` | `codercom/example-universal:ubuntu` | Any base image — bootstrap handles missing node/npm |
| `workdir` | `/home/coder/project` | Working directory inside the container |

### Claude

| Variable | Default | Description |
|---|---|---|
| `claude_api_key` | `""` | Anthropic API key (sensitive) |
| `claude_code_oauth_token` | `""` | Claude Code OAuth token (sensitive) |
| `claude_code_version` | `latest` | Version to install |
| `install_via_npm` | `false` | Use npm instead of the official installer |
| `claude_model` | `""` | Override the default Claude model |
| `permission_mode` | `plan` | `empty \| default \| acceptEdits \| plan \| bypassPermissions` |
| `enable_bedrock` | `true` | Enable AWS Bedrock mode |
| `aws_region` | `us-gov-west-1` | Bedrock AWS region |
| `aws_bearer_token_bedrock` | `""` | Bedrock bearer token fallback (sensitive) |

### MCP servers

| Variable | Default | Description |
|---|---|---|
| `enable_mcp_filesystem` | `true` | Filesystem MCP (no credentials needed) |
| `mcp_allowed_root` | `/home/coder/project` | Root path exposed to filesystem MCP |
| `enable_mcp_github` | `false` | GitHub MCP |
| `mcp_github_token` | `""` | GitHub PAT (sensitive, required when enabled) |
| `mcp_github_server_url` | `https://github.com` | GitHub or GHES base URL |
| `mcp_github_repository` | `owner/repo` | Default repo in `owner/repo` format |
| `mcp_github_branch` | `main` | Default branch |
| `enable_mcp_jira` | `false` | Jira MCP via mcp-remote |
| `mcp_jira_server_url` | `https://jira.example.com/mcp` | Jira MCP endpoint (Atlassian Cloud: `https://mcp.atlassian.com/v1/sse`) |
| `mcp_jira_token` | `""` | Jira API token (sensitive, required when enabled) |
| `mcp_jira_project_key` | `PROJ` | Default Jira project key |
| `mcp_jira_user_email` | `""` | Jira user email (defaults to workspace owner email) |
| `enable_mcp_confluence` | `false` | Confluence MCP via mcp-remote |
| `mcp_confluence_server_url` | `https://confluence.example.com/mcp` | Confluence MCP endpoint |
| `mcp_confluence_token` | `""` | Confluence API token (sensitive, required when enabled) |
| `mcp_confluence_space_key` | `ENG` | Default Confluence space key |
| `mcp_confluence_user_email` | `""` | Confluence user email (defaults to workspace owner email) |
| `mcp_custom_scripts_csv` | `""` | Comma-separated `name:/path/to/script` entries for custom MCP servers |
| `mcp_remote_config_urls_csv` | `""` | Comma-separated HTTPS URLs returning `{mcpServers:{...}}` JSON |

### IDE and repo

| Variable | Default | Description |
|---|---|---|
| `enable_code_server` | `true` | Browser VS Code |
| `vscode_extensions_csv` | `""` | Pre-install extensions (comma-separated IDs) |
| `git_repo_url` | `""` | Repo to clone — MCP setup runs regardless |
| `git_repo_branch` | `main` | Branch to clone/checkout |
| `https_proxy` | `""` | Enterprise HTTPS proxy |
| `http_proxy` | `""` | Enterprise HTTP proxy |
| `no_proxy` | `""` | NO_PROXY list |

## How the multi-distro bootstrap works

When the workspace starts, the script checks for `npx` and — if not found — tries the following install paths **in order**:

1. `apt-get install nodejs npm` (Debian / Ubuntu)
2. `apk add nodejs npm` (Alpine)
3. `dnf install nodejs npm` (Fedora / RHEL 8+)
4. `yum install nodejs npm` (CentOS / RHEL 7)
5. **nvm** — installs the LTS Node.js release
6. **Node.js binary tarball** — downloads the official `linux-x64` or `linux-arm64` tarball directly from nodejs.org

If none succeed, the script prints a warning and continues. Any MCP server that does not require `npx` (e.g., custom scripts) still registers normally.

## Custom Docker image (optional)

`workspace/Dockerfile` and `workspace/bootstrap.sh` are provided to pre-bake `nodejs`, `npm`, and common utilities. Using a pre-baked image makes workspace startup faster because the runtime bootstrap is a no-op.

```sh
docker build -t my-org/mcp-workspace:latest ./workspace
```

Then set `container_image = "my-org/mcp-workspace:latest"` in your Coder template variables.

## MCP endpoint reference

| Integration | Atlassian Cloud endpoint | Self-hosted pattern |
|---|---|---|
| Jira | `https://mcp.atlassian.com/v1/sse` | `https://jira.example.com/mcp` |
| Confluence | `https://mcp.atlassian.com/v1/sse` | `https://confluence.example.com/mcp` |
| GitHub | uses `@modelcontextprotocol/server-github` npm package | set `mcp_github_server_url` for GHES |

## Security notes

- Token variables (`mcp_github_token`, `mcp_jira_token`, `mcp_confluence_token`, `claude_api_key`) are marked `sensitive = true` in Terraform and are injected as `coder_env` resources, not embedded in the startup script.
- No credentials are written to `startup_script` or printed to workspace logs.
- The filesystem MCP server is bounded to `mcp_allowed_root`; adjust this to the minimum required scope.
- Review `mcp-remote` token scopes before granting Jira/Confluence access in production.
