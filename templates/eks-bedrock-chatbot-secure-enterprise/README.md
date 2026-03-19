# EKS Bedrock Chatbot — Secure Enterprise

Production-hardened tier of the EKS Bedrock chatbot template family. Includes all capabilities
of `eks-bedrock-chatbot-rag` plus:

This tier is tuned for **GovCloud Sonnet 4.5** as the primary model target and preserves the
same operator-entered integration settings: GitHub repo/branch, GitHub server, Jira server,
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

Inherited connector inputs remain part of the operator workflow:

| Variable | Description |
| --- | --- |
| `GITHUB_SERVER_URL` | GitHub or GitHub Enterprise Server URL |
| `GITHUB_REPOSITORY` | Target repo in `owner/repo` form |
| `GITHUB_BRANCH` | Target branch for GitHub operations |
| `GITHUB_PERSONAL_ACCESS_TOKEN` | GitHub PAT |
| `JIRA_SERVER_URL` | Jira server URL |
| `JIRA_PROJECT_KEY` | Default Jira project key |
| `JIRA_API_TOKEN` | Jira PAT/API token |
| `CONFLUENCE_SERVER_URL` | Confluence server URL |
| `CONFLUENCE_SPACE_KEY` | Default Confluence space key |
| `CONFLUENCE_API_TOKEN` | Confluence PAT/API token |

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
- The namespace has `pod-security.kubernetes.io/enforce: restricted` applied.
- NetworkPolicies allow only explicit traffic paths.
- PodDisruptionBudgets (`minAvailable: 1`) prevent outages during rolling updates.
- All Bedrock/AOSS calls traverse VPC endpoints — no traffic exits the VPC.
- CloudWatch Logs retention is set to 90 days by default.
