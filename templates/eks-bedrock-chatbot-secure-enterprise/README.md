# EKS Bedrock Chatbot — Secure Enterprise

Production-hardened tier of the EKS Bedrock chatbot template family. Includes all capabilities
of `eks-bedrock-chatbot-rag` plus:

This tier supports AI provider mode selection:

- `bedrock` (AWS GovCloud Bedrock)
- `azure` (Azure OpenAI in Azure US Government)
- `dual` (both enabled; request-time provider selection)

It remains tuned for **GovCloud Sonnet 4.5** as the default model target and preserves the same
operator-entered integration settings: GitHub repo/branch, GitHub server, Jira server,
Confluence server, and a PAT/API token for each external system.

- **Amazon Cognito OIDC/SSO** — authenticates human users before reaching the chatbot
- **AWS Secrets Manager + External Secrets Operator (ESO)** — all credentials sourced from AWS
  Secrets Manager; no plaintext values in Kubernetes manifests
- **Kubernetes NetworkPolicies** — explicit allow-listing of all ingress/egress
- **PodDisruptionBudgets** — protect availability during cluster maintenance
- **Pod Security Standards (restricted)** — enforced at the namespace level
- **OpenTelemetry tracing** — traces exported to AWS X-Ray via the ADOT Collector
- **CloudWatch audit logging** — structured request/response logs for compliance

## Architecture

```text
          Cognito        EKS (chatbot ns — PSS: restricted)
 User ──► OIDC ────────► ALB Ingress
                              │
                     ┌────────▼─────────┐
                     │ OTEL Collector   │ ── X-Ray / CloudWatch
                     └────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
       Chatbot Pod     Ingestion CronJob    ESO Pod
       (Converse+KB)   (S3 → KB sync)    (Secrets sync)
              │
       AWS Secrets Manager
         (all connector tokens)
```

## Prerequisites

Inherits all prerequisites from `eks-bedrock-chatbot-rag`, plus:

| Requirement | Notes |
| --- | --- |
| Amazon Cognito User Pool | With an ALB-integrated app client |
| External Secrets Operator | Installed via Helm in the `external-secrets` namespace |
| ADOT Collector | Installed via EKS Add-on or Helm |
| AWS Load Balancer Controller | For ALB Ingress |
| Pod Security Standards enforced | Namespace-level label |

## Required environment variables

Includes all from `eks-bedrock-chatbot-rag`, plus:

| Variable | Description |
| --- | --- |
| `COGNITO_USER_POOL_ID` | Cognito User Pool ID |
| `COGNITO_CLIENT_ID` | Cognito app client ID |
| `COGNITO_REGION` | Region of the Cognito User Pool |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | ADOT collector endpoint (default: `http://adot-collector:4317`) |
| `OTEL_SERVICE_NAME` | Service name for traces |
| `ESO_SECRET_STORE_NAME` | ESO `ClusterSecretStore` or `SecretStore` name |
| `MODEL_PROVIDER` | `bedrock`, `azure`, or `dual` |
| `AZURE_OPENAI_ENDPOINT` | Azure Gov endpoint such as `https://<resource>.openai.azure.us/` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `AZURE_OPENAI_API_VERSION` | Azure API version (default `2024-10-21`) |
| `AZURE_OPENAI_API_KEY` | Azure API key loaded from Kubernetes Secret/ESO |

> **Note:** `IRSA_ROLE_ARN` can be left empty when pod identity/IRSA association is already managed externally.

Inherited connector inputs remain part of the operator workflow:

| Variable | Description |
| --- | --- |
| `GITHUB_SERVER_URL` | GitHub or GitHub Enterprise Server URL |
| `GITHUB_REPOSITORY` | Target repo in `owner/repo` form |
| `GITHUB_BRANCH` | Target branch for GitHub operations |
| `GITHUB_REPO_SCOPE` | `any`, `configured`, or `allowlist` repo policy |
| `GITHUB_ALLOWED_REPOSITORIES` | CSV allowlist used when `GITHUB_REPO_SCOPE=allowlist` |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub PAT |
| `JIRA_SERVER_URL` | Jira server URL |
| `JIRA_PROJECT_KEY` | Default Jira project key |
| `JIRA_API_TOKEN` | Jira PAT/API token |
| `CONFLUENCE_SERVER_URL` | Confluence server URL |
| `CONFLUENCE_SPACE_KEY` | Default Confluence space key |
| `CONFLUENCE_API_TOKEN` | Confluence PAT/API token |

## Minimal operator inputs (recommended)

Set these explicitly:

- `EKS_CLUSTER_NAME`
- `BEDROCK_MODEL_ID`, `BEDROCK_KB_ID`, `BEDROCK_KB_DATA_SOURCE_ID`
- `S3_DOCUMENT_BUCKET`
- `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID`, `COGNITO_REGION`
- `ESO_SECRET_STORE_NAME` and secret mappings
- image repository/tag

Can be left empty / auto-derived by template defaults:

- `IRSA_ROLE_ARN` → optional when pod identity/IRSA association is already managed externally
- `workspace_name` → active Coder workspace name
- `k8s_namespace` → derived from workspace name when blank
- `jira_user_email`, `confluence_user_email` → fall back to `workspace_owner_email`
- with `auth_owner_only=true`, allow-list resolves to owner email automatically
- `github_repo_scope` defaults to `any` for developer multi-repo workflows

## Developer repo-scope controls (GitHub)

When GitHub connector usage is enabled, repository scope policy can be configured:

- `github_repo_scope=any` *(default)*: any `owner/repo` target is permitted.
- `github_repo_scope=configured`: only `github_repository` is permitted.
- `github_repo_scope=allowlist`: only repositories from
   `github_allowed_repositories_csv` are permitted (falls back to `github_repository`
   when allowlist is empty).

## Enabling ESO

1. Install External Secrets Operator:

   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
   ```

2. Create an `ExternalSecret` referencing your Secrets Manager secret (see `k8s/external-secret.yaml`).
   Keep server URLs, repo, branch, project key, and space key in the non-secret ConfigMap;
   store only PAT/API tokens and usernames in Secrets Manager.

3. ESO will sync the values into a Kubernetes `Secret` that the pod mounts.

## Security notes

- All tokens and credentials are sourced exclusively from AWS Secrets Manager via ESO.
- Azure API keys should be synced through ESO/Secrets Manager (or another approved backend secret store), never hardcoded.
- The namespace has `pod-security.kubernetes.io/enforce: restricted` applied.
- NetworkPolicies allow only explicit traffic paths.
- PodDisruptionBudgets (`minAvailable: 1`) prevent outages during rolling updates.
- All Bedrock/AOSS calls traverse VPC endpoints — no traffic exits the VPC.
- CloudWatch Logs retention is set to 90 days by default.
