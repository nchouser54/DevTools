# MCP Server Definitions
# Coder automatically registers these servers with Claude Code during workspace startup.
# See the README.md for variable substitution details.

## Filesystem MCP (optional)
- **Enabled by**: `enable_mcp_filesystem=true`
- **Command**: `npx -y @modelcontextprotocol/server-filesystem /home/coder/project`
- **Purpose**: Gives Claude Code access to files in your project directory

## GitHub MCP (optional)
- **Enabled by**: `enable_mcp_github=true` + `mcp_github_token=<PAT>`
- **Command**: `npx -y @modelcontextprotocol/server-github`
- **Environment variables**:
  - `GITHUB_PERSONAL_ACCESS_TOKEN`: Your GitHub Personal Access Token
  - `GITHUB_SERVER_URL`: GitHub API endpoint (default: `https://github.com`)
  - `GITHUB_REPOSITORY`: Default repository (`owner/repo`)
  - `GITHUB_BRANCH`: Default branch (`main`)
- **Purpose**: Gives Claude Code access to GitHub issues, PRs, and code search

For details, see [Coder MCP documentation](https://coder.com/docs/v2/latest/dev/mcp-servers).
