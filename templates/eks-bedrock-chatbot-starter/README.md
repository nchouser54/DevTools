# EKS Bedrock Chatbot Starter

Baseline Coder workspace template for a chatbot application running on Amazon EKS, backed by the AWS Bedrock Converse API with **GovCloud Sonnet 4.5** as the primary target model.

## What this template provides

- Python 3.12 workspace with `boto3` and a minimal Bedrock Converse client stub
- Kubernetes manifests for a pod `ServiceAccount` with IRSA annotation, a `Deployment`, and a `Service`
- Helm chart skeleton for parameterised deployment across environments
- MCP server stubs for filesystem access
- `.env.example` documenting every required operator variable

## Prerequisites

| Requirement | Notes |
| --- | --- |
| Amazon EKS cluster | Version 1.28+ recommended |
| IRSA-enabled node group | OIDC provider must be associated with the cluster |
| IAM role with `AmazonBedrockFullAccess` | Scope down to model ARN in production |
| Bedrock model access enabled | Requested in the AWS console per region |
| Helm 3.14+ | For chart-based deployments |
| `kubectl` | Configured with cluster credentials |

## Required environment variables

| Variable | Description |
| --- | --- |
| `AWS_REGION` | AWS GovCloud region where Bedrock is enabled (default: `us-gov-west-1`) |
| `BEDROCK_MODEL_ID` | Your GovCloud Sonnet 4.5 Bedrock model ID |
| `IRSA_ROLE_ARN` | ARN of the IAM role to annotate on the `ServiceAccount` |
| `EKS_CLUSTER_NAME` | EKS cluster name |
| `K8S_NAMESPACE` | Kubernetes namespace for the chatbot workload |
| `WORKSPACE_NAME` | Coder workspace label |
| `WORKSPACE_OWNER` | Coder workspace owner or team |

## Getting started

1. Copy `.env.example` to `.env` and fill in all variables.
2. Apply the IAM role annotation to your `ServiceAccount`:

   ```bash
   kubectl annotate serviceaccount bedrock-chatbot \
     -n ${K8S_NAMESPACE} \
     eks.amazonaws.com/role-arn=${IRSA_ROLE_ARN}
   ```

3. Deploy with Helm:

   ```bash
   helm upgrade --install bedrock-chatbot helm/ \
     --namespace ${K8S_NAMESPACE} \
     --set aws.region=${AWS_REGION} \
     --set aws.bedrockModelId=${BEDROCK_MODEL_ID}
   ```

4. Run the stub chatbot:

   ```bash
   python workspace/chatbot.py
   ```

## Security notes

- Never commit live AWS credentials. IRSA provides pod-level identity without long-lived keys.
- Restrict the IAM policy to the specific Bedrock model ARN used in production.
- See `k8s/network-policy.yaml` for a baseline deny-all ingress/egress posture.

## Template lineage

This is the **starter** tier. For connector integrations (GitHub, Jira, Confluence) see
`eks-bedrock-chatbot-connectors`. For RAG see `eks-bedrock-chatbot-rag`. For enterprise
security hardening see `eks-bedrock-chatbot-secure-enterprise`.
