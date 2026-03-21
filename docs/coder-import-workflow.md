# Coder Import Workflow

This guide explains how to import an EKS Bedrock chatbot template into a live Coder control plane, map template parameters, and bind your secrets backend.

For a copy/paste-safe operator flow (including Claude workspace templates), use: `docs/coder-copy-paste-runbook.md`.

---

## Prerequisites

- Coder v2.9 or later installed and reachable (`coder version`)
- Terraform CLI ≥ 1.5.0 on the Coder provisioner node
- AWS CLI configured with credentials that can reach all target services
- An EKS cluster with:
  - IRSA enabled (IAM OIDC provider associated with the cluster)
  - `aws-load-balancer-controller` or appropriate ingress controller for your tier
  - External Secrets Operator (enterprise tier only)
- An IRSA IAM role for the chatbot workload — see [docs/iam-policies/](iam-policies/) for per-tier policy examples

---

## Step 1 — Create the IRSA IAM role

Before importing the template, create the IRSA role that the workload ServiceAccount will use.

Replace the placeholders and run:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_PROVIDER=$(aws eks describe-cluster \
  --name devtools-cluster \
  --query "cluster.identity.oidc.issuer" \
  --output text | sed 's|https://||')

aws iam create-role \
  --role-name eks-bedrock-chatbot-irsa \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"Federated\": \"arn:aws-us-gov:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}\"},
      \"Action\": \"sts:AssumeRoleWithWebIdentity\",
      \"Condition\": {
        \"StringEquals\": {
          \"${OIDC_PROVIDER}:sub\": \"system:serviceaccount:chatbot:chatbot\"
        }
      }
    }]
  }"

aws iam put-role-policy \
  --role-name eks-bedrock-chatbot-irsa \
  --policy-name BedrockChatbotPolicy \
  --policy-document file://docs/iam-policies/bedrock-chatbot-starter-irsa-policy.json
```

Note the resulting role ARN — you will pass it as `irsa_role_arn` when creating the workspace.

For higher tiers, use the corresponding policy file:

| Template tier | Policy file |
| --- | --- |
| starter | `bedrock-chatbot-starter-irsa-policy.json` |
| connectors | `bedrock-chatbot-connectors-irsa-policy.json` |
| rag | `bedrock-chatbot-rag-irsa-policy.json` |
| secure-enterprise | `bedrock-chatbot-enterprise-irsa-policy.json` |
| secure-api-builder | `secure-enterprise-api-builder-irsa-policy.json` |

---

## Step 2 — Authenticate the Coder CLI

```bash
coder login https://coder.your-org.internal
```

Verify:

```bash
coder whoami
```

---

## Step 3 — Push the template to Coder

From the root of this repository:

```bash
coder templates push eks-bedrock-chatbot-starter \
  --directory templates/eks-bedrock-chatbot-starter/coder \
  --name eks-bedrock-chatbot-starter
```

Repeat for other tiers, substituting the directory and `--name` as needed:

```bash
# Connectors tier
coder templates push eks-bedrock-chatbot-connectors \
  --directory templates/eks-bedrock-chatbot-connectors/coder \
  --name eks-bedrock-chatbot-connectors

# RAG tier
coder templates push eks-bedrock-chatbot-rag \
  --directory templates/eks-bedrock-chatbot-rag/coder \
  --name eks-bedrock-chatbot-rag

# Enterprise tier
coder templates push eks-bedrock-chatbot-enterprise \
  --directory templates/eks-bedrock-chatbot-secure-enterprise/coder \
  --name eks-bedrock-chatbot-enterprise

# Secure API Builder tier
coder templates push eks-secure-enterprise-api-builder \
  --directory templates/eks-secure-enterprise-api-builder/coder \
  --name eks-secure-enterprise-api-builder
```

---

## Step 4 — Create a workspace

```bash
coder create my-chatbot \
  --template eks-bedrock-chatbot-starter \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p k8s_namespace=chatbot \
  -p bedrock_model_id=<your-govcloud-sonnet-4.5-model-id> \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot \
  -p image_tag=latest
```

For the connectors tier, add connector toggles and tokens:

```bash
coder create my-chatbot-connectors \
  --template eks-bedrock-chatbot-connectors \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-connectors-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-connectors \
  -p enable_github_connector=true \
  -p github_server_url=https://github.example.com \
  -p github_repository=org/repo \
  -p github_branch=main \
  -p github_personal_access_token=<PAT>
```

For the RAG tier, also supply Knowledge Base and S3 inputs:

```bash
coder create my-chatbot-rag \
  --template eks-bedrock-chatbot-rag \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-rag-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-rag \
  -p bedrock_kb_id=<KB_ID> \
  -p bedrock_kb_data_source_id=<DS_ID> \
  -p s3_document_bucket=<BUCKET_NAME>
```

For the enterprise tier, also supply Cognito, ESO, and OTel inputs:

```bash
coder create my-chatbot-enterprise \
  --template eks-bedrock-chatbot-enterprise \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/eks-bedrock-chatbot-enterprise-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-enterprise \
  -p bedrock_kb_id=<KB_ID> \
  -p bedrock_kb_data_source_id=<DS_ID> \
  -p s3_document_bucket=<BUCKET_NAME> \
  -p cognito_user_pool_id=<USER_POOL_ID> \
  -p cognito_client_id=<CLIENT_ID> \
  -p eso_secret_store_name=aws-secrets-store \
  -p otel_collector_endpoint=http://adot-collector:4317
```

For the secure API builder tier, supply API deployment inputs:

```bash
coder create my-secure-api \
  --template eks-secure-enterprise-api-builder \
  -p aws_region=us-gov-west-1 \
  -p eks_cluster_name=devtools-cluster \
  -p k8s_namespace=secure-api \
  -p irsa_role_arn=arn:aws-us-gov:iam::ACCOUNT_ID:role/secure-api-irsa \
  -p image_repository=ACCOUNT_ID.dkr.ecr.us-gov-west-1.amazonaws.com/secure-api-builder \
  -p image_tag=latest \
  -p api_log_level=info \
  -p ingress_host=secure-api.internal.example.mil
```

---

## Step 5 — Verify the workspace

```bash
coder show my-chatbot
```

Check that the Helm release deployed successfully and the pod is running:

```bash
kubectl -n chatbot get pods
kubectl -n chatbot get configmap chatbot-config -o yaml
```

Confirm the ServiceAccount has the correct IRSA annotation:

```bash
kubectl -n chatbot get serviceaccount chatbot -o jsonpath='{.metadata.annotations}'
```

---

## Parameter reference

All parameters defined in `coder/main.tf` map directly to Coder workspace parameters. Sensitive parameters (marked `sensitive = true`) are stored encrypted by the Coder control plane and never appear in plan output.

| Parameter | Required | Sensitive | Notes |
| --- | --- | --- | --- |
| `aws_region` | Yes | No | Defaults to `us-gov-west-1` |
| `eks_cluster_name` | Yes | No | Must be reachable by the Coder provisioner |
| `k8s_namespace` | Yes | No | Defaults to `chatbot` |
| `bedrock_model_id` | Yes | No | Set to your GovCloud Sonnet 4.5 model ID |
| `irsa_role_arn` | Yes | Yes | Pre-created IRSA role for the workload |
| `image_repository` | Yes | No | ECR or other container registry path |
| `image_tag` | Yes | No | Defaults to `latest` |
| `irsa_role_arn` | Yes | Yes | ARN of the pre-created IRSA role |
| `github_personal_access_token` | Connectors+ | Yes | Required when `enable_github_connector=true` |
| `jira_pat` | Connectors+ | Yes | Required when `enable_jira_connector=true` |
| `confluence_pat` | Connectors+ | Yes | Required when `enable_confluence_connector=true` |
| `cognito_client_id` | Enterprise | Yes | Cognito app client ID |

---

## GovCloud vs commercial AWS

All templates default to GovCloud (`us-gov-west-1`). To target commercial AWS:

1. Set `aws_region` to the correct commercial region (e.g. `us-east-1`).
2. Update `bedrock_model_id` to the commercial model ARN for Sonnet 4.5.
3. Replace `arn:aws-us-gov:` prefixes in your IAM trust policy with `arn:aws:`.
4. Cognito and Bedrock service availability varies by commercial region — verify against the [AWS regional services list](https://aws.amazon.com/about-aws/global-infrastructure/regional-product-services/).

---

## Troubleshooting

**Terraform cannot reach the EKS cluster**
Ensure the Coder provisioner node's IAM role or instance profile has `eks:DescribeCluster` on the target cluster.

**`aws_eks_cluster_auth` token expires mid-apply**
This is expected for large applies. Re-run `coder start <workspace>` to trigger a refresh.

**Helm release fails with image pull errors**
Confirm the `image_repository` is accessible from the EKS node group's ECR pull-through credentials or instance profile.

**ServiceAccount not annotated correctly**
Verify the IRSA OIDC trust policy subject matches `system:serviceaccount:<k8s_namespace>:chatbot`.

**EKS worker subnets run out of IPv4 addresses (pod networking pressure)**
Use the dedicated runbook: [`docs/eks-ipv4-pod-networking.md`](eks-ipv4-pod-networking.md).

Priority order:

1. Tune `aws-node` warm targets to reduce idle IP reservations.
2. Enable prefix delegation where supported.
3. Revisit node `maxPods` and subnet/CIDR sizing.

**VS Code SSH or Coder sessions drop during idle/long actions**
Apply both workspace and cluster-side hardening:

- Use templates that include SSH keepalive defaults and tmux support.
  - All workspace templates in this repo now write `/etc/ssh/ssh_config.d/99-devtools-keepalive.conf`.
  - Reconnect with `coder-resume` to return to the persistent tmux session.

- Increase ingress/load balancer idle timeouts for long-lived WebSocket/SSH tunnels.
  - For ALB ingress, set:

  ```yaml
  metadata:
    annotations:
     alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=3600
  ```

  - If using nginx ingress for Coder endpoints, set higher timeouts:

  ```yaml
  metadata:
    annotations:
     nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
     nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
     nginx.ingress.kubernetes.io/proxy-connect-timeout: "75"
  ```

- Keep Coder control-plane and workspace pods disruption-safe.
  - Ensure PodDisruptionBudgets are present.
  - Avoid aggressive node scale-down policies for active workspace node groups.

- Validate after rollout.
  - Start a workspace, open VS Code remote session, run a long command (>10 min), and confirm no disconnect.
  - Verify reconnect path by closing session and running `coder-resume`.
