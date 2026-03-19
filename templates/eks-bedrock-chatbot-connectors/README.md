# EKS Bedrock Chatbot — Connectors

Extends `eks-bedrock-chatbot-starter` with pre-wired MCP connectors for **GitHub**, **Jira**,
and **Confluence**. Each connector is toggled by a feature flag stored in a Kubernetes `Secret`,
so you can enable them incrementally without rebuilding the image.

This tier assumes **GovCloud Sonnet 4.5** is your primary Bedrock model target and exposes
explicit user inputs for the GitHub repository/branch plus the designated server and PAT/API token
for each external system.

It also includes an **embedded connector action API** so your chatbot service can execute
cross-system automation directly in-cluster (for example, create a Jira ticket from GitHub file
context or publish a Confluence page from a Jira issue).

## What this template adds

| Connector | MCP Server | Controls |
| --- | --- | --- |
| GitHub | `@modelcontextprotocol/server-github` | `MCP_ENABLE_GITHUB` |
| Jira | `mcp-atlassian` | `MCP_ENABLE_JIRA` |
| Confluence | `mcp-atlassian` | `MCP_ENABLE_CONFLUENCE` |

Connector tokens are sourced from a single Kubernetes `Secret` (`bedrock-chatbot-connectors`)
and injected as environment variables at pod startup.

## Architecture

```text
User → Chatbot Pod
         ├─ Bedrock Converse API (IRSA auth)
         ├─ GitHub MCP server   (feature-flagged, PAT from Secret)
         ├─ Jira MCP server     (feature-flagged, API token from Secret)
         └─ Confluence MCP server (feature-flagged, API token from Secret)
```

## Prerequisites

Inherits all prerequisites from `eks-bedrock-chatbot-starter`, plus:

| Requirement | Notes |
| --- | --- |
| GitHub PAT | Scopes: `repo`, `read:org` minimum |
| Jira API token | Atlassian account → Security → API tokens |
| Confluence API token | Same Atlassian token works if on same instance |

## Required environment variables

Includes all variables from `eks-bedrock-chatbot-starter`, plus:

| Variable | Description |
| --- | --- |
| `MCP_ENABLE_GITHUB` | `true` / `false` — controls GitHub connector |
| `GITHUB_SERVER_URL` | GitHub or GitHub Enterprise Server URL |
| `GITHUB_REPOSITORY` | Target repo in `owner/repo` form |
| `GITHUB_BRANCH` | Target branch for repo operations |
| `MCP_ENABLE_JIRA` | `true` / `false` — controls Jira connector |
| `JIRA_SERVER_URL` | e.g. `https://your-org.atlassian.net` |
| `JIRA_PROJECT_KEY` | Default Jira project key |
| `MCP_ENABLE_CONFLUENCE` | `true` / `false` — controls Confluence connector |
| `ALLOW_CONNECTOR_WRITES` | `true` / `false` — enables write actions (issue/page creation) |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub PAT stored in Kubernetes Secret |
| `JIRA_API_TOKEN` | Jira API token stored in Kubernetes Secret |
| `JIRA_USER_EMAIL` | Atlassian account email |
| `CONFLUENCE_SERVER_URL` | e.g. `https://your-org.atlassian.net/wiki` |
| `CONFLUENCE_SPACE_KEY` | Default Confluence space key |
| `CONFLUENCE_API_TOKEN` | Confluence API token stored in Kubernetes Secret |
| `CONFLUENCE_USER_EMAIL` | Atlassian account email |

## Embedded action API (what is now possible)

The chatbot container exposes:

- `GET /capabilities` — active connectors, targets, and supported actions
- `POST /action` — execute connector actions directly

Supported actions:

- `github.get_file`
- `github.create_issue` *(requires `ALLOW_CONNECTOR_WRITES=true`)*
- `jira.create_issue` *(requires `ALLOW_CONNECTOR_WRITES=true`)*
- `confluence.create_page` *(requires `ALLOW_CONNECTOR_WRITES=true`)*
- `workflow.github_file_to_jira` *(reads GitHub file, opens Jira issue)*
- `workflow.jira_to_confluence` *(reads Jira issue, creates Confluence page)*

Example (`workflow.github_file_to_jira`):

```bash
curl -sS -X POST http://<service-url>/action \
   -H 'Content-Type: application/json' \
   -d '{
      "action": "workflow.github_file_to_jira",
      "params": {
         "path": "src/api.py",
         "summary": "Follow-up from API review",
         "issue_type": "Task"
      }
   }'
```

Example (`workflow.jira_to_confluence`):

```bash
curl -sS -X POST http://<service-url>/action \
   -H 'Content-Type: application/json' \
   -d '{
      "action": "workflow.jira_to_confluence",
      "params": {
         "issue_key": "OPS-123",
         "space_key": "ENG"
      }
   }'
```

## Enabling a connector

1. Create (or update) the connector secret:

   ```bash
   kubectl create secret generic bedrock-chatbot-connectors \
     -n ${K8S_NAMESPACE} \
     --from-literal=GITHUB_PERSONAL_ACCESS_TOKEN=ghp_replace-me \
     --from-literal=JIRA_API_TOKEN=replace-me \
     --from-literal=JIRA_USER_EMAIL=you@example.com \
     --from-literal=CONFLUENCE_API_TOKEN=replace-me \
     --from-literal=CONFLUENCE_USER_EMAIL=you@example.com
   ```

1. Set the target systems in `.env` or your deployment values:

   ```env
   ALLOW_CONNECTOR_WRITES=true
   GITHUB_SERVER_URL=https://github.my-company.mil
   GITHUB_REPOSITORY=platform/mission-bot
   GITHUB_BRANCH=main
   JIRA_SERVER_URL=https://issues.my-company.mil
   JIRA_PROJECT_KEY=OPS
   CONFLUENCE_SERVER_URL=https://wiki.my-company.mil
   CONFLUENCE_SPACE_KEY=ENG
   ```

1. Set the connector feature flag in `helm/values.yaml`:

   ```yaml
   connectors:
       allowWrites: true
     github:
       enabled: true
       jira:
          enabled: true
       confluence:
          enabled: true
   ```

1. Redeploy:

   ```bash
   helm upgrade --install bedrock-chatbot-connectors helm/ -n ${K8S_NAMESPACE}
   ```

## Security notes

- Connector tokens are never embedded in the image or in plaintext config files.
- All tokens must be stored in Kubernetes `Secrets` (or External Secrets Operator — see the
  `eks-bedrock-chatbot-secure-enterprise` template).
- Review GitHub PAT scopes and enforce minimum permissions.
- Limit Jira/Confluence token permissions to read-only unless write actions are required.
- Keep `ALLOW_CONNECTOR_WRITES=false` by default in lower environments, then enable only for
   controlled automation paths in production.
