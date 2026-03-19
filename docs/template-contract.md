# Template Contract

This document defines the minimum structure required for any template in this repository.

## Required files

Every template directory under `templates/` must contain:

- `manifest.json`
- `README.md`
- `coder/main.tf`
- `workspace/Dockerfile`
- `workspace/bootstrap.sh`
- `mcp/servers.example.json`
- `.env.example`

## `manifest.json` requirements

Each manifest must include the following top-level fields:

- `name`
- `slug`
- `description`
- `owner`
- `version`
- `runtime`
- `mcp`
- `tags`

Additional manifest validation rules:

- `slug` must match the template directory name under `templates/`
- `name`, `slug`, `description`, `owner`, and `version` must be non-empty strings
- `tags` must be a non-empty list of non-empty strings

## Directory responsibilities

### `coder/`

Contains assets directly related to Coder template import or workspace provisioning.

### `workspace/`

Contains the build context and scripts used inside the workspace.

### `mcp/`

Contains example MCP server configuration and notes that operators can adapt to their environment.

## Security rules

- Never commit live secrets.
- Use example variables and placeholder values only.
- Prefer environment variables for operator-supplied configuration.
- Document every required variable in the template README.

## Optional EKS-specific files

Templates targeting **Amazon EKS** may include the following additional directories. These are
not enforced by the validator but are strongly recommended for EKS templates:

### `k8s/`

Raw Kubernetes manifests for direct `kubectl apply` workflows. Recommended files:

- `serviceaccount.yaml` — `ServiceAccount` with IRSA annotation
- `deployment.yaml` — workload with security context hardening
- `service.yaml` — Kubernetes `Service`
- `configmap.yaml` — non-sensitive configuration
- `network-policy.yaml` — explicit ingress/egress allow-listing
- `hpa.yaml` — `HorizontalPodAutoscaler` (RAG and enterprise tiers)
- `pdb.yaml` — `PodDisruptionBudget` (enterprise tier)
- `external-secret.yaml` — ESO `ExternalSecret` manifest (enterprise tier)
- `namespace.yaml` — namespace with Pod Security Standards labels (enterprise tier)
- `ingestion-job.yaml` — `CronJob` for document ingestion (RAG tier)

### `helm/`

Helm chart for parameterised, environment-specific deployment. Required files within `helm/`:

- `Chart.yaml`
- `values.yaml`
- `templates/_helpers.tpl`
- Additional `templates/*.yaml` mirroring the `k8s/` manifests

## EKS security baseline

All EKS templates in this repository follow these cross-cutting standards:

- **IRSA** — pod identity via IAM Roles for Service Accounts; no long-lived AWS credentials.
- **No plaintext secrets** — use Kubernetes `Secrets` sourced from AWS Secrets Manager via ESO.
- **Pod security** — `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`.
- **NetworkPolicies** — explicit allow-listing of all ingress and egress traffic.
- **HPA** — autoscaling enabled by default for RAG and enterprise tiers.

## Validation

Run `scripts/validate_templates.py` to confirm templates match the minimum repository contract.
