# Coder Software Engineering / Developer Catalog (EKS + GovCloud)

This catalog helps platform teams pick the **right template quickly** and import it with low failure risk.

Use this as the front door for developer onboarding and template selection.

---

## Recommended fast-path stack (start here)

If your goal is “working quickly with minimal surprises,” standardize on this 3-template baseline first:

1. `eks-kubectl-workspace` — cluster operations (`kubectl`, optional `helm`)
2. `eks-ec2-existing-workspace` — attach Coder to existing Linux/Windows EC2 (SSM)
3. `eks-ec2-ami-workspace` — launch fresh EC2 from AMI with persistent home EBS

Then add `mcp-universal-workspace` for AI connector workflows.

---

## Template decision matrix

| Template slug | Best for | Access mode | Persistence model | GovCloud fit | Complexity |
|---|---|---|---|---|---|
| `eks-kubectl-workspace` | Platform/SRE cluster ops | Terminal/CLI | N/A | Excellent | Low |
| `eks-ec2-existing-workspace` | Reusing existing fleet | Linux SSH, Windows RDP, optional Linux XRDP | Existing instance lifecycle unchanged | Excellent | Medium |
| `eks-ec2-ami-workspace` | Clean, reproducible developer hosts | Linux SSH, Windows RDP, optional Linux XRDP | Ephemeral EC2 + persistent home EBS | Excellent | Medium |
| `mcp-universal-workspace` | MCP-first developer workflows | VS Code/terminal + MCP | Standard workspace persistence | Excellent | Medium |
| `claude-code-workspace` | Claude-only baseline | VS Code/terminal | Standard workspace persistence | Good | Low |
| `claude-code-workspace-connectors` | Claude + GitHub/Jira/Confluence | VS Code/terminal + connectors | Standard workspace persistence | Good | Medium |
| `shared-ec2-workspace-pool` | Cost-efficient pooled runtime profiles | VS Code/terminal | Shared pool model | Good | Medium |
| `govcloud-template-starter` | Building new GovCloud templates quickly | N/A starter scaffold | N/A | Excellent | Low |

Complexity scoring is operational complexity for import + first successful start.

---

## Persona-based recommendations

### Platform/SRE team

- Primary: `eks-kubectl-workspace`
- Add-on: `eks-ec2-existing-workspace` (for break-glass access to existing instances)
- Optional: `mcp-universal-workspace` for runbook/search connectors

### Software engineering team

- Primary: `eks-ec2-ami-workspace` (clean AMI-based environment + persistent home)
- Add-on: `mcp-universal-workspace` or `claude-code-workspace-connectors`
- Optional: `eks-kubectl-workspace` for release/debug operations

### AI / solution engineering team

- Primary: `mcp-universal-workspace`
- Add-on: `claude-code-workspace-connectors`
- Optional: `eks-bedrock-chatbot-*` tiers for app deployment scenarios

---

## Import profiles (copy/paste-safe defaults)

### Profile A — EKS operations baseline

- Template: `eks-kubectl-workspace`
- Suggested parameters:
  - `aws_region=us-gov-west-1`
  - `eks_cluster_name=<cluster>`
  - `default_kube_namespace=default`
  - `auto_configure_kubeconfig=true`
  - `enable_helm=true` (optional)

### Profile B — Existing EC2 attach

- Template: `eks-ec2-existing-workspace`
- Suggested parameters:
  - `aws_region=us-gov-west-1`
  - `ec2_instance_id=i-...`
  - `os_type=linux|windows`
  - `enable_xrdp=true` (Linux desktop optional)

### Profile C — New EC2 from AMI

- Template: `eks-ec2-ami-workspace`
- Suggested parameters:
  - `aws_region=us-gov-west-1`
  - `ami_id=ami-...`
  - `subnet_id=subnet-...`
  - `instance_type=t3.medium` (or org default)
  - `home_volume_size_gb=50`
  - `enable_xrdp=true` (Linux desktop optional)

### Profile D — MCP-first developer flow

- Template: `mcp-universal-workspace`
- Suggested parameters:
  - `container_image=codercom/example-universal:ubuntu`
  - `workdir=/home/coder/project`
  - `enable_mcp_filesystem=true`
  - `enable_mcp_github=true` + `mcp_github_token=<token>`
  - `enable_mcp_jira=true` + `mcp_jira_token=<token>` (optional)
  - `enable_mcp_confluence=true` + `mcp_confluence_token=<token>` (optional)

---

## Common variable contract (recommended across templates)

Adopt these as your platform standard to reduce import friction:

- `AWS_REGION` (default `us-gov-west-1`)
- `WORKSPACE_OWNER`
- `DEFAULT_KUBE_NAMESPACE`
- `AUTO_CONFIGURE_KUBECONFIG`
- `ENABLE_HELM`, `HELM_VERSION`
- `ENABLE_XRDP`, `XRDP_PORT`
- `ENABLE_MCP_*` toggles and token placeholders
- `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`

---

## Preflight checklist before import

1. Run `python3 scripts/validate_templates.py`
2. Confirm IAM/IRSA permissions for the target template
3. Confirm network path (Coder URL, AWS endpoints, proxy/VPC endpoints)
4. Confirm no live secrets in `.env.example` or committed files
5. Start with one baseline template, then expand to others

---

## Build-your-own option

For new templates, use:

- `templates/govcloud-template-starter/` (copy-and-adapt)
- `python3 scripts/scaffold_template.py --profile govcloud --name <NAME> --slug <SLUG> --description <DESC>`

This keeps your new templates import-ready and contract-compliant from day one.
