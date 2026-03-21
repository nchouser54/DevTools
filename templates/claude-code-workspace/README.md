# Claude Code Workspace

This template creates a **non-premium** Coder workspace for Claude Code.

It is designed for teams that want the post-spinup UX of a polished Coder developer workspace without depending on:

- Coder AI Bridge
- Coder Tasks / Agentic AI premium workflows

Instead, it installs the Claude Code CLI directly in the workspace at startup and exposes standard Coder workspace apps.

## What users get after spin-up

After the workspace starts, users can access:

- **Claude Code** app shortcut that launches the CLI in the workspace terminal
- **Claude Auth Setup** shortcut for interactive `claude setup-token`
- **VS Code** integration from the workspace agent bar
- **Web Terminal** from the workspace agent bar
- **code-server** (optional, enabled by default)

This is the exact kind of post-spinup app surface you were aiming for.

## What this template includes

- Docker-backed Coder workspace runtime
- direct Claude Code installation via the official installer or npm fallback
- optional `code-server` module
- built-in Coder app surfaces via `display_apps`
- optional Git repository clone on startup
- optional generated MCP configuration for Claude Code
- Bedrock-first mode (`CLAUDE_CODE_USE_BEDROCK=1`) with AWS region wiring for IAM-role authentication
- optional VS Code extension preinstall via comma-separated extension IDs

## Non-premium behavior

This template intentionally avoids premium-only features:

- no `coder_ai_task` resources
- no AI Bridge dependency
- no premium task reporting integration

Claude still runs inside the workspace, but premium task reporting and AI Bridge proxying are not used.

## Authentication options

You can use either:

- `CLAUDE_API_KEY`
- `CLAUDE_CODE_OAUTH_TOKEN`

Leave both empty if you want users to authenticate interactively inside the workspace later.

> Do not set both values at the same time.

## Optional Git bootstrap

If `GIT_REPO_URL` is set, the workspace startup script clones the repository into `WORKDIR`.
If the repository already exists, it fetches updates and checks out the configured branch.

Users can still clone and work with any other repository from terminal/VS Code after startup.

## Bedrock authentication (primary path)

By default, this template enables Bedrock mode and sets:

- `CLAUDE_CODE_USE_BEDROCK=1`
- `AWS_REGION`
- `AWS_DEFAULT_REGION`

Primary authentication is expected through the standard AWS credential chain (for example: IAM role credentials available to the workspace runtime).

Optional fallback:

- `AWS_BEARER_TOKEN_BEDROCK`

If you do not have runtime IAM credentials available, you can provide `AWS_BEARER_TOKEN_BEDROCK` as a fallback.

## VS Code extension preinstall (optional)

Use `VSCODE_EXTENSIONS_CSV` to preinstall extensions inside browser editors when available (for example `code-server`):

- `ms-python.python,ms-toolsai.jupyter,amazonwebservices.aws-toolkit-vscode`

## Optional MCP support

The template can inject a generated Claude MCP config using:

- filesystem MCP
- GitHub MCP
- remote MCP config URLs

See `mcp/servers.example.json` for the shape of the generated config.

## Key variables

At minimum, operators should review:

- `CONTAINER_IMAGE`
- `WORKDIR`
- `ENABLE_CODE_SERVER`
- `CLAUDE_CODE_VERSION`
- `INSTALL_VIA_NPM`
- `CLAUDE_API_KEY`
- `CLAUDE_CODE_OAUTH_TOKEN`
- `CLAUDE_MODEL`
- `ENABLE_BEDROCK`
- `AWS_REGION`
- `AWS_BEARER_TOKEN_BEDROCK`
- `GIT_REPO_URL`
- `GIT_REPO_BRANCH`
- `VSCODE_EXTENSIONS_CSV`
- `ENABLE_MCP_FILESYSTEM`
- `ENABLE_MCP_GITHUB`
- `MCP_REMOTE_CONFIG_URLS_CSV`

## Post-spinup UX summary

| Surface | Provided by | Default |
| --- | --- | --- |
| Claude Code app | `coder_app` launching the CLI | Yes |
| Claude Auth Setup | `coder_app` launching `claude setup-token` | Yes |
| VS Code button | `coder_agent.display_apps` | Yes |
| Web Terminal | `coder_agent.display_apps` | Yes |
| code-server | `code-server` module | Yes |

## Notes

- This template is intentionally focused on **workspace UX** and Claude enablement, not premium AI workflow automation.
- The included `workspace/` assets satisfy the repository contract and can be used as a future basis for a custom built image if you want to stop relying on a prebuilt container.
- MCP helper shortcuts use `npx`, so the startup script ensures npm is present whenever MCP integrations are enabled.
