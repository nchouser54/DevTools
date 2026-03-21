# EKS kubectl Workspace

This template provides an operator-focused Coder workspace for day-2 Kubernetes operations on Amazon EKS clusters.

## What it includes

- `kubectl` and AWS CLI preinstalled in the workspace image
- helper scripts for EKS kubeconfig setup and quick cluster checks
- contract-compliant Coder template metadata (`coder/main.tf`)
- example MCP config and environment placeholders (no live secrets)

## Intended use

Use this workspace when platform engineers need to:

- inspect cluster state (`get`, `describe`, `logs`, `events`)
- run namespace-level triage and operational checks
- verify service endpoints and rollout status
- perform controlled maintenance actions under RBAC policy

## Required operator variables

See `.env.example`. At minimum, review:

- `WORKSPACE_NAME`
- `WORKSPACE_OWNER`
- `AWS_REGION`
- `EKS_CLUSTER_NAME`
- `DEFAULT_KUBE_NAMESPACE`
- `AUTO_CONFIGURE_KUBECONFIG`

## Authentication and authorization model

This workspace assumes standard EKS auth:

1. Workspace identity (IRSA/pod identity or other AWS credentials) can call EKS APIs.
2. `aws eks update-kubeconfig` writes kubeconfig for the target cluster.
3. Kubernetes RBAC controls what `kubectl` actions are permitted.

Being in the cluster does **not** automatically grant broad Kubernetes privileges.

## Quick start inside workspace

1. Run `eks-login` to configure kubeconfig for the selected cluster.
2. Run `kctx-check` to confirm auth and API access.
3. Use standard `kubectl` commands for namespace-scoped or cluster-scoped operations.

## Included helper commands

- `eks-login` — configures kubeconfig for `${EKS_CLUSTER_NAME}` in `${AWS_REGION}`
- `kctx-check` — shows current context, nodes, and namespace health snapshot

## RBAC starter profiles

This template includes namespace-scoped RBAC starters under `k8s/`:

- `k8s/rbac-readonly.yaml` — read-only operational access (`get/list/watch`)
- `k8s/rbac-ops-maintainer.yaml` — operational maintenance access (read + rollout/scale/patch + limited pod/job recovery actions)
- `k8s/rbac-admin.yaml` — namespace admin access (full verbs/resources in one namespace)

Recommended rollout flow:

1. Copy one profile and set the target `metadata.namespace`.
2. Update `subjects` to match your EKS auth mapping (IAM-mapped group/user or service account).
3. Apply the manifest and verify with `kubectl auth can-i` checks.

Use read-only by default; grant admin profile only for elevated operator workflows.

Suggested profile selection:

- **readonly**: incident visibility and diagnostics only
- **ops-maintainer**: day-2 service operations without full namespace admin
- **admin**: break-glass or platform-owner workflows

## Security notes

- No static cloud credentials are committed in this template.
- Scope IAM + RBAC to least privilege for each operator persona.
- Prefer namespace-scoped roles for day-to-day usage.
