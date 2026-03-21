# Shared EC2 Workspace Pool

This template provides a **profile-driven Coder workspace** designed to run on **shared EC2-backed host pools**.

Instead of one dedicated EC2 per user, multiple isolated workspaces run as containers on fewer hosts. This gives users options while helping platform teams reduce EC2 count and cost.

## What this template is for

- User-selectable workspace profiles (`python`, `claude`, `devsecops`)
- User-selectable workspace sizes (`small`, `medium`, `large`)
- Optional repository bootstrap (`git clone` on startup)
- Optional MCP baseline (filesystem + GitHub)
- Coder metadata showing selected profile/size/image for governance

## Shared-host model note

“Multiple virtual AMIs on one EC2” maps in practice to **multiple containerized workspaces on shared hosts**.

This template implements that model using profile-to-image selection.

## Required operator variables

At minimum, review:

- `WORKSPACE_PROFILE`
- `WORKSPACE_SIZE`
- `IMAGE_PYTHON`
- `IMAGE_CLAUDE`
- `IMAGE_DEVSECOPS`

Optional:

- `GIT_REPO_URL`
- `GIT_REPO_BRANCH`
- `VSCODE_EXTENSIONS_CSV`
- `ENABLE_MCP_GITHUB`
- `MCP_GITHUB_TOKEN`

## Profile and size matrix

| Profile | Typical use |
| --- | --- |
| `python` | Python AI/data/dev workflows |
| `claude` | Claude Code-centered workflows |
| `devsecops` | Infra/security tooling workflows |

| Size | CPU | Memory | Disk |
| --- | --- | --- | --- |
| `small` | 2 | 4Gi | 20Gi |
| `medium` | 4 | 8Gi | 40Gi |
| `large` | 8 | 16Gi | 80Gi |

## Guardrails for EC2 consolidation

Use this template with Coder platform controls:

- idle auto-stop enabled
- max workspace age policies
- per-user workspace quotas
- approved image catalog per profile

## Validation behavior

Template checks enforce:

- valid profile and size values
- non-empty selected profile image
- GitHub repo format + token when GitHub MCP is enabled

## Related docs

- `docs/coder-copy-paste-runbook.md`
- `docs/coder-ui-field-paste-sheets.md`
- `docs/template-contract.md`
