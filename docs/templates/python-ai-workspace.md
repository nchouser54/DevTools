# Python AI Workspace

## Intent

The Python AI workspace is the reference template for this repository. It is designed to demonstrate the baseline structure for an AI-ready development environment that can be adapted for Coder deployments.

## Included assets

- template metadata via `manifest.json`
- starter Coder Terraform configuration
- workspace Docker build context
- bootstrap script for package and environment setup
- example MCP server configuration
- documented environment variables

## Operator checklist

1. Review `.env.example` and map each variable to your secret or workspace configuration system.
2. Review `mcp/servers.example.json` and enable only the MCP servers appropriate for your environment.
3. Adapt `coder/main.tf` to your Coder provider conventions and infrastructure.
4. Build and test the `workspace/Dockerfile` in your target environment.
5. Run `scripts/validate_templates.py` before publishing changes.

## Notes

This template is intentionally conservative. It is meant to be a clear reference implementation, not a maximal workspace image.
