# Python AI Workspace

This template is the reference implementation for the `DevTools` repository.

## What it includes

- a starter Coder-oriented Terraform configuration
- a Python 3.12 workspace image
- a bootstrap script for common developer tools
- an initialization script for cloning a selected Git repository and branch
- workspace size profiles (small/medium/large)
- example MCP server configuration
- optional MCP auto-rendering for client tooling configuration

## Required operator variables

See `.env.example` for the current contract.

At a minimum, operators should review:

- `WORKSPACE_NAME`
- `WORKSPACE_OWNER`
- `WORKSPACE_SIZE`
- `GIT_REPO_URL`
- `GIT_REPO_BRANCH`
- `GIT_AUTHOR_NAME`
- `GIT_AUTHOR_EMAIL`
- `MCP_GITHUB_TOKEN`
- `MCP_JIRA_TOKEN`
- `MCP_CONFLUENCE_TOKEN`
- `MCP_ALLOWED_ROOT`
- `AUTO_SETUP_ON_LOGIN`
- `AUTO_RENDER_MCP_CONFIG`
- `ENABLE_CLAUDE_CODE_CLI`

## Coder input pattern supported

This template now supports a common enterprise Coder UX pattern:

- user selects workspace size (`small`, `medium`, `large`)
- user provides repository URL and branch
- workspace init script clones/fetches repository and checks out branch
- MCP config is rendered from a template and can be copied to client-specific paths
- users can provide GitHub/Jira/Confluence credentials and targets so MCP is ready immediately
- setup runs automatically on first shell login, regardless of which repository was selected

Default init command emitted by Terraform output metadata:

- `/usr/local/bin/devtools-init-workspace`

## Layout

- `coder/` — Coder-facing assets
- `workspace/` — image and bootstrap assets
- `mcp/` — MCP example configuration

## Important notes

- The included MCP configuration is an example, not a production endorsement list.
- No secrets should be committed to this repository.
- Review and adapt the Terraform and workspace settings to your Coder environment before import.
- Claude Code CLI installation is optional and best-effort (`ENABLE_CLAUDE_CODE_CLI=true`).
- If your MCP client uses non-default config paths, set `CLAUDE_CODE_MCP_CONFIG_PATH` and/or
  `VSCODE_MCP_CONFIG_PATH` so init can copy the rendered config automatically.
- Jira and Confluence use `mcp-atlassian`; verify package and policy fit your environment before enabling.
- Set `AUTO_SETUP_ON_LOGIN=false` if you want to disable automatic first-login setup.
- Workspace images include SSH keepalive defaults and `tmux`; use `coder-resume` after reconnect to restore your shell session.
