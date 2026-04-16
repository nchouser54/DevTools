# Claude Code Workspace Connectors

This template creates a **non-premium** Coder workspace for Claude Code with enterprise MCP connector auto-setup.

It keeps the same workspace UX as the base Claude template while adding optional, startup-time registration for:

- GitHub / GitHub Enterprise MCP
- Jira MCP
- Confluence MCP

## What users get after spin-up

After the workspace starts, users can access:

- **Claude Code** app shortcut that launches the CLI in the workspace terminal
- **Claude Auth Setup** shortcut for interactive `claude setup-token`
- **VS Code** integration from the workspace agent bar
- **Web Terminal** from the workspace agent bar
- **code-server** (optional, enabled by default)

## What this template includes

- Docker-backed Coder workspace runtime
- direct Claude Code installation via official installer or npm fallback
- optional `code-server` module
- optional Git repository clone on startup
- Bedrock-first mode (`CLAUDE_CODE_USE_BEDROCK=1`) with AWS region wiring for IAM-role authentication
- optional enterprise proxy environment injection (`HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`)
- optional generated MCP configuration for filesystem + GitHub + Jira + Confluence

## Coder Tasks support

This template includes `coder_ai_task` and appears in the Coder **Tasks** tab.

When a task is submitted:
1. Coder spins up a new workspace from this template.
2. The startup script runs as normal (git clone, MCP config, Claude Code install).
3. At the end of startup, if `data.coder_task.me.prompt` is non-empty, Claude Code runs the prompt non-interactively via `claude --print "<prompt>"`.
4. The Task UI shows the Claude Code app in the sidebar so you can watch or interact with the session.
5. When the workspace reaches its idle timeout it pauses; resuming restarts the workspace so you can continue the conversation.

When used as a regular workspace (not a Task), the prompt block is skipped — the workspace behaves exactly as before.

**Requirements:** Coder server v2.13+. Bedrock model access or an Anthropic API key must be configured.

## Non-premium behavior

This template uses `coder_ai_task` (Tasks tab support) but does **not** use:

- AI Bridge / AI Gateway
- AgentAPI for rich streaming status reporting
- Premium task reporting integration

Claude still runs inside the workspace and the Tasks UI works. AgentAPI status streaming (live typing indicators) requires the premium agent module — this template uses the simpler `claude --print` path.

## Authentication options

You can use either:

- `CLAUDE_API_KEY`
- `CLAUDE_CODE_OAUTH_TOKEN`

Leave both empty if you want users to authenticate interactively inside the workspace later.

> Do not set both values at the same time.

## Bedrock authentication (primary path)

By default, this template enables Bedrock mode and sets:

- `CLAUDE_CODE_USE_BEDROCK=1`
- `AWS_REGION`
- `AWS_DEFAULT_REGION`

Primary authentication is expected through the standard AWS credential chain (for example: IAM role credentials available to the workspace runtime).

Optional fallback:

- `AWS_BEARER_TOKEN_BEDROCK`

## Enterprise MCP inputs

Enable only the connectors you need:

- `ENABLE_MCP_GITHUB` (+ `MCP_GITHUB_TOKEN`)
- `ENABLE_MCP_JIRA` (+ `MCP_JIRA_SERVER_URL`, `MCP_JIRA_TOKEN`)
- `ENABLE_MCP_CONFLUENCE` (+ `MCP_CONFLUENCE_SERVER_URL`, `MCP_CONFLUENCE_TOKEN`)

Validation checks enforce required values when each connector is enabled.

For field-by-field Coder UI values, use: `docs/coder-ui-field-paste-sheets.md`.

## Operator verification checklist

After importing the template and creating a workspace:

1. Verify Claude is installed (`claude --version`)
2. Verify Bedrock env defaults (`echo $CLAUDE_CODE_USE_BEDROCK`, `echo $AWS_REGION`)
3. Verify MCP registration (`claude mcp list`)
4. Confirm enabled enterprise connectors appear in the list

## Troubleshooting

- **Connector missing in `claude mcp list`**: verify enable toggle and token variable for that connector.
- **Remote connector connection failure**: verify enterprise MCP URL is reachable from workspace network and proxy settings are correct.
- **Auth failures**: check token scope and expiration for the target connector.
- **TLS/proxy issues**: set `HTTPS_PROXY` / `NO_PROXY` values appropriate for your enterprise network.
