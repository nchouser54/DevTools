# Workspace Assets

This directory contains the Docker build context and bootstrap logic for the Python AI workspace.

## Files

- `Dockerfile` — base image and package installation
- `bootstrap.sh` — lightweight Python package bootstrap script
- `init-workspace.sh` — startup routine for repo clone/branch checkout and MCP config rendering
- `auto-init.sh` — one-time first-login wrapper that triggers workspace initialization automatically
- `mcp.servers.template.json` — MCP server template consumed by `init-workspace.sh`

Adapt these files to your internal base image, package mirrors, and security policies as needed.
