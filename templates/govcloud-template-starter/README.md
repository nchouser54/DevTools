# GovCloud Template Starter

This is a copy-ready starter template for easy **AWS GovCloud** Coder imports.

Use it when you want a predictable baseline for new templates with a consistent variable contract and import shape.

## What it includes

- Contract-compliant required files for this repository
- GovCloud-oriented input contract (`AWS_REGION`, `WORKSPACE_OWNER`, proxy fields)
- Optional tooling toggles (`enable_helm`, `enable_xrdp`)
- MCP example placeholders (`filesystem`, optional `github`)

## Suggested workflow

1. Copy this directory to a new slug under `templates/<your-slug>/`.
2. Update `manifest.json` (`name`, `slug`, `description`, tags).
3. Adapt `coder/main.tf` to your target pattern (EKS ops, EC2 existing, EC2 AMI, etc.).
4. Add runtime tools and bootstrap logic in `workspace/bootstrap.sh`.
5. Update `.env.example` with only placeholders (no secrets).
6. Validate: `python scripts/validate_templates.py`.

## Variable contract starter

- `WORKSPACE_NAME`
- `WORKSPACE_OWNER`
- `AWS_REGION` (default `us-gov-west-1`)
- `DEFAULT_KUBE_NAMESPACE`
- `AUTO_CONFIGURE_KUBECONFIG`
- `ENABLE_HELM` / `HELM_VERSION`
- `ENABLE_XRDP` / `XRDP_PORT`
- `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`
- `MCP_ALLOWED_ROOT`, `MCP_GITHUB_*`

## Security notes

- Do not commit live credentials.
- Keep tokens and keys as operator-supplied environment variables.
- Restrict IAM and RBAC to least privilege for each template persona.
- Prefer outbound-only connectivity patterns when possible.
