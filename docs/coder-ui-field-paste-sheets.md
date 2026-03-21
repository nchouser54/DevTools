# Coder UI Field-by-Field Paste Sheets

Use this page when creating workspaces through the **Coder web UI** (not CLI).

Goal: eliminate guesswork by showing exactly what to paste into each field.

---

## Template: `claude-code-workspace-connectors`

### Recommended EKS "works-first" values

| Coder field (parameter) | Paste this value | Why |
| --- | --- | --- |
| `container_image` | `codercom/example-universal:ubuntu` | Known-good base image |
| `workdir` | `/home/coder/project` | Standard workspace path |
| `enable_code_server` | `true` | Enables browser IDE fallback |
| `enable_bedrock` | `true` | Bedrock-first auth behavior |
| `aws_region` | `us-gov-west-1` | GovCloud default |
| `enable_mcp_filesystem` | `true` | Useful local file MCP access |
| `mcp_allowed_root` | `/home/coder/project` | Restricts filesystem MCP scope |
| `enable_mcp_github` | `true` | Enable GitHub MCP |
| `mcp_github_server_url` | `https://github.example.mil` | Enterprise GitHub URL |
| `mcp_github_repository` | `org/repo` | Default target repo |
| `mcp_github_branch` | `main` | Default branch |
| `mcp_github_token` | `<PASTE_GITHUB_TOKEN>` | Required when GitHub MCP is enabled |
| `enable_mcp_jira` | `true` | Enable Jira MCP |
| `mcp_jira_server_url` | `https://jira.example.mil/mcp` | Enterprise Jira MCP endpoint |
| `mcp_jira_project_key` | `TEAM` | Default Jira project |
| `mcp_jira_user_email` | `engineer@example.mil` | Jira actor identity |
| `mcp_jira_token` | `<PASTE_JIRA_TOKEN>` | Required when Jira MCP is enabled |
| `enable_mcp_confluence` | `true` | Enable Confluence MCP |
| `mcp_confluence_server_url` | `https://confluence.example.mil/mcp` | Enterprise Confluence MCP endpoint |
| `mcp_confluence_space_key` | `ENG` | Default Confluence space |
| `mcp_confluence_user_email` | `engineer@example.mil` | Confluence actor identity |
| `mcp_confluence_token` | `<PASTE_CONFLUENCE_TOKEN>` | Required when Confluence MCP is enabled |

### Optional network fields (only if required)

| Coder field (parameter) | Paste this value |
| --- | --- |
| `https_proxy` | `http://proxy.example.mil:8080` |
| `http_proxy` | `http://proxy.example.mil:8080` |
| `no_proxy` | `localhost,127.0.0.1,.svc,.cluster.local` |

### Keep blank unless needed

- `claude_api_key`
- `claude_code_oauth_token`
- `aws_bearer_token_bedrock`
- `mcp_remote_config_urls_csv`

> Important: do **not** set both `claude_api_key` and `claude_code_oauth_token`.

---

## Template: `eks-bedrock-chatbot-connectors`

### Recommended "works-first" values

| Coder field (parameter) | Paste this value | Why |
| --- | --- | --- |
| `aws_region` | `us-gov-west-1` | GovCloud default |
| `eks_cluster_name` | `devtools-cluster` | Target EKS cluster |
| `bedrock_model_id` | `<YOUR_SONNET_4_5_MODEL_ID>` | Required Bedrock model |
| `irsa_role_arn` | `arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-connectors-irsa` | Pod IAM access |
| `image_repository` | `ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-connectors` | Runtime image |
| `image_tag` | `latest` | Image tag |
| `enable_github_connector` | `true` | Enable GitHub connector |
| `github_server_url` | `https://github.example.mil` | Enterprise GitHub URL |
| `github_repository` | `org/repo` | Target repo |
| `github_branch` | `main` | Target branch |
| `github_personal_access_token` | `<PASTE_GITHUB_TOKEN>` | Required when GitHub is enabled |
| `enable_jira_connector` | `true` | Enable Jira connector |
| `jira_server_url` | `https://jira.example.mil` | Enterprise Jira URL |
| `jira_project_key` | `TEAM` | Default Jira project |
| `jira_user_email` | `engineer@example.mil` | Jira actor identity |
| `jira_pat` | `<PASTE_JIRA_TOKEN>` | Required when Jira is enabled |
| `enable_confluence_connector` | `true` | Enable Confluence connector |
| `confluence_server_url` | `https://confluence.example.mil/wiki` | Enterprise Confluence URL |
| `confluence_space_key` | `ENG` | Default Confluence space |
| `confluence_user_email` | `engineer@example.mil` | Confluence actor identity |
| `confluence_pat` | `<PASTE_CONFLUENCE_TOKEN>` | Required when Confluence is enabled |

### Recommended auth defaults for solo user workspaces

| Coder field (parameter) | Paste this value |
| --- | --- |
| `enable_request_auth` | `true` |
| `auth_owner_only` | `true` |
| `workspace_owner_email` | `engineer@example.mil` |

---

## UI workflow (safe sequence)

1. Pick template slug exactly.
2. Fill **required non-secret** fields first.
3. Toggle connector enables.
4. Fill each connector token right after enabling it.
5. Review once for blank token fields tied to enabled connectors.
6. Create workspace.

---

## Fast post-create checks

For Claude workspace template:

- Open terminal and run `claude --version`.
- Run `claude mcp list` and confirm enabled connectors are present.

For EKS connectors template:

- Confirm namespace and pod health with `kubectl -n <namespace> get pods`.
- Confirm effective connector config with `kubectl -n <namespace> get configmap chatbot-config -o yaml`.

---

## Related docs

- `docs/coder-copy-paste-runbook.md`
- `docs/coder-import-workflow.md`
- `templates/claude-code-workspace-connectors/README.md`
- `templates/eks-bedrock-chatbot-connectors/README.md`
