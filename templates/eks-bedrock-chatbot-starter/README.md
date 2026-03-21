# EKS Bedrock Chatbot Starter

Baseline Coder workspace template for a chatbot application running on Amazon EKS with a selectable AI provider mode:

- `bedrock` (AWS GovCloud Bedrock)
- `azure` (Azure OpenAI in Azure US Government)
- `dual` (both enabled; request-time provider selection)

## What this template provides

- Python 3.12 workspace with `boto3` and `openai` SDK support for Bedrock/Azure provider selection
- Kubernetes manifests for a pod `ServiceAccount` with IRSA annotation, a `Deployment`, and a `Service`
- Helm chart skeleton for parameterised deployment across environments
- MCP server stubs for filesystem access
- `.env.example` documenting every required operator variable

## Prerequisites

| Requirement | Notes |
| --- | --- |
| Amazon EKS cluster | Version 1.28+ recommended |
| IRSA-enabled node group | OIDC provider must be associated with the cluster |
| IAM role with `AmazonBedrockFullAccess` | Needed for Bedrock mode; scope down to model ARN in production |
| Bedrock model access enabled | Requested in the AWS console per region |
| Azure OpenAI (Azure Gov) resource | Needed for Azure or dual mode |
| Kubernetes Secret for Azure API key | Store Azure key in backend-managed secret (not plaintext Terraform variable) |
| Helm 3.14+ | For chart-based deployments |
| `kubectl` | Configured with cluster credentials |

## Required environment variables

| Variable | Description |
| --- | --- |
| `AWS_REGION` | AWS GovCloud region where Bedrock is enabled (default: `us-gov-west-1`) |
| `BEDROCK_MODEL_ID` | Your GovCloud Sonnet 4.5 Bedrock model ID |
| `MODEL_PROVIDER` | `bedrock`, `azure`, or `dual` |
| `AZURE_OPENAI_ENDPOINT` | Azure Gov endpoint such as `https://<resource>.openai.azure.us/` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `AZURE_OPENAI_API_VERSION` | Azure API version (default `2024-10-21`) |
| `AZURE_OPENAI_API_KEY` | Azure key loaded from Kubernetes Secret in deployment |
| `IRSA_ROLE_ARN` | Optional: ARN of the IAM role to annotate on the `ServiceAccount` |
| `EKS_CLUSTER_NAME` | EKS cluster name |
| `K8S_NAMESPACE` | Kubernetes namespace for the chatbot workload |
| `WORKSPACE_NAME` | Coder workspace label |
| `WORKSPACE_OWNER` | Coder workspace owner or team |

> **Note:** `IRSA_ROLE_ARN` can be left empty when pod identity/IRSA association is already managed externally.

## Minimal operator inputs (recommended)

Set these explicitly:

- `EKS_CLUSTER_NAME`
- `BEDROCK_MODEL_ID` (and Azure values if using `azure`/`dual`)
- Container image (`image.repository`, `image.tag`)

Can be left empty / auto-derived by template defaults:

- `IRSA_ROLE_ARN` → optional when pod identity/IRSA association is already managed externally
- `workspace_name` → uses active Coder workspace name
- `k8s_namespace` → derived from workspace name when blank
- auth allow-list behavior can default to owner email when `auth_owner_only=true`

## Getting started

1. Copy `.env.example` to `.env` and fill in all variables.
2. Apply the IAM role annotation to your `ServiceAccount`:

   ```bash
   kubectl annotate serviceaccount bedrock-chatbot \
     -n ${K8S_NAMESPACE} \
     eks.amazonaws.com/role-arn=${IRSA_ROLE_ARN}
   ```

3. Create/update Azure API key secret (required for `azure` or `dual` mode):

    ```bash
    kubectl create secret generic azure-openai \
       -n ${K8S_NAMESPACE} \
       --from-literal=api-key=replace-me
    ```

4. Deploy with Helm:

   ```bash
   helm upgrade --install bedrock-chatbot helm/ \
     --namespace ${K8S_NAMESPACE} \
       --set ai.provider=${MODEL_PROVIDER} \
     --set aws.region=${AWS_REGION} \
       --set aws.bedrockModelId=${BEDROCK_MODEL_ID} \
       --set ai.azure.endpoint=${AZURE_OPENAI_ENDPOINT} \
       --set ai.azure.deployment=${AZURE_OPENAI_DEPLOYMENT}
   ```

5. Run the chatbot:

   ```bash
   python workspace/chatbot.py
   ```

## Accessing the Chatbot After Spinup

Once the Coder workspace spins up and Terraform applies:

1. **Get the chatbot service URL**:

   ```bash
   kubectl get svc -n ${K8S_NAMESPACE} chatbot
   ```

   The `EXTERNAL-IP` column shows the LoadBalancer endpoint. Wait a few moments for AWS to assign the IP.

2. **Open in your browser**:
   - Navigate to `http://<EXTERNAL-IP>` (or your domain if you've set up DNS)
   - The web UI loads automatically with a chat interface
   - Select your preferred provider (Bedrock/Azure) from the dropdown
   - Start chatting!

3. **Conversation history** is stored in your browser's local storage—it persists as long as you don't clear browser data.

## Security notes

- Never commit live AWS credentials. IRSA provides pod-level identity without long-lived keys.
- Never commit Azure API keys. Store them in Kubernetes Secrets or an external backend (e.g., External Secrets + Key Vault).
- Restrict the IAM policy to the specific Bedrock model ARN used in production.
- See `k8s/network-policy.yaml` for a baseline deny-all ingress/egress posture.

## Template lineage

This is the **starter** tier. For connector integrations (GitHub, Jira, Confluence) see
`eks-bedrock-chatbot-connectors`. For RAG see `eks-bedrock-chatbot-rag`. For enterprise
security hardening see `eks-bedrock-chatbot-secure-enterprise`.
