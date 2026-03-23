# EKS Bedrock Chatbot — Connectors

Extends `eks-bedrock-chatbot-starter` with pre-wired MCP connectors for **GitHub**, **Jira**,
and **Confluence**. Each connector is toggled by workspace creation inputs in Coder, and this
template creates namespace-scoped Kubernetes `Secrets` from those inputs during provisioning.

This template is now optimized as a **solo workspace per person**: each user gets their own
workspace deployment, can supply their own connector credentials, and by default the chatbot is
restricted to the workspace owner when upstream identity headers are available.

This tier supports `bedrock`, `azure`, or `dual` provider mode. In dual mode, developers can choose
the provider per request while still using the same connector action interface.

This is a **service-style template**, not a full Linux workstation template. Users get a deployed
chatbot endpoint plus Coder metadata cards describing access and status; they do **not** get a
built-in Web Terminal, VS Code session, or remote desktop from this template.

It exposes explicit user inputs for the GitHub repository/branch plus the designated server and
PAT/API token for each external system.

For developer workflows, GitHub actions support repo scope controls so teams can run in
`any` repo mode by default, then tighten to `configured` or `allowlist` as needed.

It also includes an **embedded connector action API** so your chatbot service can execute
cross-system automation directly in-cluster (for example, create a Jira ticket from GitHub file
context or publish a Confluence page from a Jira issue).

## What this template adds

| Connector | MCP Server | Controls |
| --- | --- | --- |
| GitHub | `@modelcontextprotocol/server-github` | `MCP_ENABLE_GITHUB` |
| Jira | `mcp-atlassian` | `MCP_ENABLE_JIRA` |
| Confluence | `mcp-atlassian` | `MCP_ENABLE_CONFLUENCE` |

Connector tokens are collected at workspace creation and written to namespace-scoped Kubernetes
`Secrets` by Terraform, then injected as environment variables at pod startup.

Azure API keys are read from a separate Kubernetes Secret (`azure-openai` by default) so the key can
be saved in backend secret management and never embedded in the template source.

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
| `MODEL_PROVIDER` | `bedrock`, `azure`, or `dual` |
| `AZURE_OPENAI_ENDPOINT` | Azure Gov endpoint such as `https://<resource>.openai.azure.us/` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `AZURE_OPENAI_API_VERSION` | Azure API version |
| `BEDROCK_ALLOWED_MODEL_IDS` | Optional comma-separated allowlist of approved Bedrock model IDs |
| `AZURE_ALLOWED_DEPLOYMENTS` | Optional comma-separated allowlist of approved Azure deployment names |
| `AZURE_OPENAI_API_KEY` | Loaded from Kubernetes Secret |

| Variable | Description |
| --- | --- |
| `MCP_ENABLE_GITHUB` | `true` / `false` — controls GitHub connector |
| `GITHUB_SERVER_URL` | GitHub or GitHub Enterprise Server URL |
| `GITHUB_REPOSITORY` | Target repo in `owner/repo` form |
| `GITHUB_BRANCH` | Target branch for repo operations |
| `GITHUB_REPO_SCOPE` | `any`, `configured`, or `allowlist` repo policy for GitHub actions |
| `GITHUB_ALLOWED_REPOSITORIES` | Comma-separated allowlist used when `GITHUB_REPO_SCOPE=allowlist` |
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
| `AUTH_REQUIRED` | `true` / `false` — require authenticated identity header from upstream proxy |
| `AUTH_ALLOWED_EMAILS` | Comma-separated allow-list of user emails (empty = any authenticated user) |
| `AUTH_TRUSTED_EMAIL_HEADERS` | Comma-separated header priority list used to extract user email |

> **Note:** `IRSA_ROLE_ARN` can be left empty when pod identity/IRSA association is already managed externally.

## Solo workspace behavior (default)

- `enable_request_auth=true` by default.
- `auth_owner_only=true` by default.
- `workspace_owner` auto-derives from the active Coder workspace owner when left blank.
- `workspace_owner_email` auto-derives from the active Coder workspace owner's email when left blank.
- `jira_user_email` and `confluence_user_email` fall back to the effective workspace owner email.
- Each workspace keeps its own connector tokens in its own namespace-scoped secrets.
- Users define what each workspace can access by entering connector toggles, targets, and credentials in the Coder workspace creation form.

The template now validates key inputs at workspace creation time to prevent broken spin-ups:

- If `enable_github_connector=true`, `github_repository` must be `owner/repo` and `github_personal_access_token` must be set.
- If `enable_jira_connector=true`, `jira_pat` must be set.
- If `enable_confluence_connector=true`, `confluence_pat` must be set.
- If `model_provider` is `bedrock` or `dual`, `bedrock_model_id` must be set.
- If `model_provider` is `azure` or `dual`, `azure_openai_endpoint` and `azure_openai_deployment` must be set.
- If `bedrock_allowed_model_ids_csv` is set, `bedrock_model_id` must be in that allowlist.
- If `azure_allowed_deployments_csv` is set, `azure_openai_deployment` must be in that allowlist.
- If `auth_owner_only=true`, an effective workspace owner email must exist (either entered explicitly or auto-derived from Coder).

## Built-in workspace CLI

The chatbot image bootstrap installs a lightweight `ai` helper for operators or anyone who execs
into the running container. It is useful for debugging the deployed service, but it is **not**
presented as a standalone Coder workstation app by this template.

Examples:

- `ai health`
- `ai providers`
- `ai chat "Summarize the active connector targets"`
- `ai chat "Use Azure for this answer" --provider azure`

By default, `ai` uses `http://127.0.0.1:8080`. Override with `CHATBOT_BASE_URL` when the chatbot is exposed elsewhere.

## What users see in Coder

After workspace creation, users are presented with service-oriented access details rather than
workstation apps.

Primary user-facing entrypoints:

- `Chatbot Web UI` — browser access to the provisioned chatbot service
- `Workspace Info` — metadata such as owner, namespace, provider, and enabled connectors
- `Chatbot Access Status` — service type, access URL, and provisioning/ready status

Not included in this template:

- Web Terminal
- VS Code / code-server
- Remote desktop

The primary browser URL is surfaced in template outputs and metadata as `chatbot_access_url` once
the Kubernetes LoadBalancer has been assigned a hostname or IP.

## Minimal operator inputs (recommended)

Set these explicitly:

- `EKS_CLUSTER_NAME`
- `BEDROCK_MODEL_ID` (and Azure values if using `azure`/`dual`)
- image repository/tag
- connector server/repo/branch values when a connector is enabled
- connector PAT/API tokens (entered at workspace creation)

Can be left empty / auto-derived by template defaults:

- `irsa_role_arn` → optional when pod identity/IRSA association is already managed externally
- `workspace_name` → active Coder workspace name
- `workspace_owner` → active Coder workspace owner name/full name
- `workspace_owner_email` → active Coder workspace owner email
- `k8s_namespace` → derived from workspace name when blank
- `jira_user_email`, `confluence_user_email` → fall back to `workspace_owner_email`
- with `auth_owner_only=true`, allow-list resolves to owner email automatically
- `github_repo_scope` defaults to `any` for developer-friendly multi-repo operation

## Developer repo-scope controls (GitHub)

GitHub action handlers (`github.get_file`, `github.create_issue`, and workflows using them)
enforce a repository policy:

- `github_repo_scope=any` *(default)*: allow any `owner/repo` passed in action params.
- `github_repo_scope=configured`: only allow `github_repository`.
- `github_repo_scope=allowlist`: allow only repositories in `github_allowed_repositories_csv`
   (falls back to `github_repository` if allowlist is empty).

Example allowlist input:

- `github_allowed_repositories_csv=platform/service-a,platform/service-b,my-org/internal-tools`

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

## Optional per-user access control (Keycloak/Coder passthrough)

If your Coder ingress/auth gateway already injects user identity headers (for example from Keycloak),
you can enforce access in the chatbot itself by enabling request auth.

Template controls:

- `enable_request_auth` — turn request auth enforcement on/off.
- `auth_owner_only` + `workspace_owner_email` — restrict each chatbot to its owner email.
- `auth_allowed_emails` — custom comma-separated allow-list (used when `auth_owner_only=false`).
- `auth_trusted_email_headers_csv` — header order for identity extraction.

When enabled:

- all endpoints except `/health` require an authenticated identity header;
- if an allow-list is configured, only listed users can access the chatbot;
- if `auth_owner_only=true`, only `workspace_owner_email` can access that workspace chatbot.

## Workspace creation flow (recommended)

For field-by-field Coder UI values, use: `docs/coder-ui-field-paste-sheets.md`.

At Coder workspace creation, users enter:

1. Connector enable flags (`enable_github_connector`, `enable_jira_connector`, `enable_confluence_connector`).
2. Connector targets (GitHub repo/branch/server, Jira server/project, Confluence server/space).
3. Connector credentials (`github_personal_access_token`, `jira_pat`, `confluence_pat`).
4. Optional write enablement (`allow_connector_writes=true` only when needed).

Terraform then provisions workspace-specific secrets and wires them into the deployment.

> Azure note: for `model_provider=azure|dual`, `azure_openai_endpoint` and
> `azure_openai_deployment` are required. The Azure API key is still expected in the Kubernetes
> secret referenced by `azure_openai_api_key_secret_name`/`azure_openai_api_key_secret_key`.

## Security notes

- Connector tokens are never embedded in the image or in plaintext config files.
- Connector tokens entered during workspace creation are written to workspace-scoped Kubernetes `Secrets`.
- Review GitHub PAT scopes and enforce minimum permissions.
- Limit Jira/Confluence token permissions to read-only unless write actions are required.
- Keep `ALLOW_CONNECTOR_WRITES=false` by default in lower environments, then enable only for
   controlled automation paths in production.
