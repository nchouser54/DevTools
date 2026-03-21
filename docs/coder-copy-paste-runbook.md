# Coder Template Copy/Paste Runbook

Use this runbook when you want the **lowest-risk, copy/paste-safe** path for importing templates and creating workspaces in Coder.

It is intentionally prescriptive so operators can avoid common mistakes.

---

## 1) Preflight (copy/paste as-is)

```bash
coder version
terraform version
python3 scripts/validate_templates.py
```

If validation does not return `[OK]` for the template you want, stop and fix that first.

---

## 2) Log in once per shell

```bash
coder login https://coder.your-org.internal
coder whoami
```

---

## 3) Pick template slug + directory (do not improvise names)

| Template | Slug | Directory |
| --- | --- | --- |
| Claude Code Workspace | `claude-code-workspace` | `templates/claude-code-workspace/coder` |
| Claude Code Workspace Connectors | `claude-code-workspace-connectors` | `templates/claude-code-workspace-connectors/coder` |
| EKS Bedrock Chatbot Connectors | `eks-bedrock-chatbot-connectors` | `templates/eks-bedrock-chatbot-connectors/coder` |

---

## 4) Push template to Coder (copy/paste-safe)

Set only these two variables, then push:

```bash
TEMPLATE_SLUG="claude-code-workspace-connectors"
TEMPLATE_DIR="templates/claude-code-workspace-connectors/coder"

coder templates push "$TEMPLATE_SLUG" \
  --directory "$TEMPLATE_DIR" \
  --name "$TEMPLATE_SLUG"
```

> Tip: always keep `--name` equal to `TEMPLATE_SLUG`.

---

## 5) Create workspace — Claude connectors template (recommended starter)

This example enables GitHub + Jira + Confluence MCP and keeps Bedrock as the primary auth path.

```bash
coder create claude-connectors-demo \
  --template claude-code-workspace-connectors \
  -p container_image=codercom/example-universal:ubuntu \
  -p workdir=/home/coder/project \
  -p enable_code_server=true \
  -p enable_bedrock=true \
  -p aws_region=us-gov-west-1 \
  -p enable_mcp_filesystem=true \
  -p mcp_allowed_root=/home/coder/project \
  -p enable_mcp_github=true \
  -p mcp_github_server_url=https://github.example.mil \
  -p mcp_github_repository=org/repo \
  -p mcp_github_branch=main \
  -p mcp_github_token='<PASTE_GITHUB_TOKEN>' \
  -p enable_mcp_jira=true \
  -p mcp_jira_server_url=https://jira.example.mil/mcp \
  -p mcp_jira_project_key=TEAM \
  -p mcp_jira_user_email=engineer@example.mil \
  -p mcp_jira_token='<PASTE_JIRA_TOKEN>' \
  -p enable_mcp_confluence=true \
  -p mcp_confluence_server_url=https://confluence.example.mil/mcp \
  -p mcp_confluence_space_key=ENG \
  -p mcp_confluence_user_email=engineer@example.mil \
  -p mcp_confluence_token='<PASTE_CONFLUENCE_TOKEN>'
```

### Enterprise proxy variant (optional)

If your network requires an outbound proxy, add these parameters:

```bash
-p https_proxy=http://proxy.example.mil:8080 \
-p http_proxy=http://proxy.example.mil:8080 \
-p no_proxy=localhost,127.0.0.1,.svc,.cluster.local
```

---

## 6) Create workspace — EKS connectors template (chatbot deployment)

```bash
coder create eks-connectors-demo \
  --template eks-bedrock-chatbot-connectors \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p bedrock_model_id=<your-sonnet-4.5-model-id> \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-connectors-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-connectors \
  -p image_tag=latest \
  -p enable_github_connector=true \
  -p github_server_url=https://github.example.mil \
  -p github_repository=org/repo \
  -p github_branch=main \
  -p github_personal_access_token='<PASTE_GITHUB_TOKEN>' \
  -p enable_jira_connector=true \
  -p jira_server_url=https://jira.example.mil \
  -p jira_project_key=TEAM \
  -p jira_user_email=engineer@example.mil \
  -p jira_pat='<PASTE_JIRA_TOKEN>' \
  -p enable_confluence_connector=true \
  -p confluence_server_url=https://confluence.example.mil/wiki \
  -p confluence_space_key=ENG \
  -p confluence_user_email=engineer@example.mil \
  -p confluence_pat='<PASTE_CONFLUENCE_TOKEN>'
```

---

## 7) 60-second verification checklist

After workspace creation:

```bash
coder show claude-connectors-demo
```

Inside workspace terminal:

```bash
claude --version
echo "$CLAUDE_CODE_USE_BEDROCK" "$AWS_REGION"
claude mcp list
```

For EKS chatbot templates:

```bash
kubectl -n <namespace> get pods
kubectl -n <namespace> get configmap chatbot-config -o yaml
```

---

## 8) Common copy/paste mistakes (and how to avoid them)

1. **Wrong template slug**
   - Always copy the exact slug from the table above.
2. **Forgetting required token when connector is enabled**
   - If `enable_*` is `true`, set its token in the same command.
3. **Unquoted secrets with special characters**
   - Wrap token values in single quotes.
4. **Directory mismatch on `coder templates push`**
   - Keep `--directory` pinned to the exact template `coder/` folder.
5. **Trying to set both Claude API key and OAuth token at once**
   - Use one auth mode at a time.

---

## Related docs

- `docs/coder-ui-field-paste-sheets.md`
- `docs/coder-import-workflow.md`
- `docs/template-contract.md`
- `templates/claude-code-workspace-connectors/README.md`
- `templates/eks-bedrock-chatbot-connectors/README.md`
