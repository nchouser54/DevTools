# EKS Bedrock Chatbot — RAG

Extends `eks-bedrock-chatbot-connectors` with **Retrieval-Augmented Generation** (RAG) using
Amazon Bedrock Knowledge Bases backed by Amazon OpenSearch Serverless (AOSS). An ingestion
pipeline syncs documents from S3, and the chatbot retrieves grounded context with every query.

This tier supports AI provider mode selection:

- `bedrock` (AWS GovCloud Bedrock)
- `azure` (Azure OpenAI in Azure US Government)
- `dual` (both enabled; request-time provider selection)

It keeps **GovCloud Sonnet 4.5** as the default model target and carries forward the connector
inputs from the connectors tier: GitHub repo/branch plus the designated server and PAT/API token
flow for GitHub, Jira, and Confluence.

## Architecture

```text
                   ┌─────────────────────────────────────────┐
                   │              Amazon EKS                  │
  User             │                                          │
    │              │  ┌───────────────┐   ┌───────────────┐  │
    └──HTTP──────► │  │ Chatbot Pod   │   │ Ingestion     │  │
                   │  │               │   │ Worker Pod    │  │
                   │  │ Bedrock       │   │               │  │
                   │  │ Converse API  │   │ S3 → AOSS     │  │
                   │  │     +         │   │ sync job      │  │
                   │  │ KB Retrieve   │   └───────────────┘  │
                   │  └───────────────┘          │           │
                   └──────────┬──────────────────┼───────────┘
                              │ Retrieve         │ Ingest
                              ▼                  ▼
                   ┌──────────────────────────────────────────┐
                   │  Bedrock Knowledge Base                   │
                   │  (AOSS vector index + S3 data source)     │
                   └──────────────────────────────────────────┘
```

## What this template adds over connectors

- `workspace/ingest.py` — ingestion script that syncs an S3 prefix to the Knowledge Base
- `workspace/rag_chatbot.py` — chatbot that retrieves context before calling Converse
- `k8s/ingestion-job.yaml` — Kubernetes `CronJob` for scheduled document sync
- `k8s/hpa.yaml` — Horizontal Pod Autoscaler for the chatbot deployment

## Prerequisites

Inherits all prerequisites from `eks-bedrock-chatbot-connectors`, plus:

| Requirement | Notes |
| --- | --- |
| Bedrock Knowledge Base | Created in the AWS console or via IaC |
| S3 bucket | Contains source documents (PDF, TXT, DOCX) |
| Amazon OpenSearch Serverless | AOSS collection backing the Knowledge Base |
| IAM role with KB permissions | `bedrock:RetrieveAndGenerate`, `bedrock:Retrieve`, `aoss:*`, `s3:GetObject` |
| Bedrock embedding model access | `amazon.titan-embed-text-v2:0` must be enabled |

## Required environment variables

Includes all from `eks-bedrock-chatbot-connectors`, plus:

| Variable | Description |
| --- | --- |
| `BEDROCK_KB_ID` | Bedrock Knowledge Base ID |
| `BEDROCK_KB_DATA_SOURCE_ID` | Knowledge Base data source ID |
| `BEDROCK_EMBEDDING_MODEL_ID` | Embedding model (default: `amazon.titan-embed-text-v2:0`) |
| `S3_DOCUMENT_BUCKET` | S3 bucket containing source documents |
| `S3_DOCUMENT_PREFIX` | S3 key prefix for documents (default: `docs/`) |
| `RAG_MAX_RESULTS` | Max KB retrieval results per query (default: `5`) |
| `MODEL_PROVIDER` | `bedrock`, `azure`, or `dual` |
| `AZURE_OPENAI_ENDPOINT` | Azure Gov endpoint such as `https://<resource>.openai.azure.us/` |
| `AZURE_OPENAI_DEPLOYMENT` | Azure OpenAI deployment name |
| `AZURE_OPENAI_API_VERSION` | Azure API version (default `2024-10-21`) |
| `AZURE_OPENAI_API_KEY` | Azure API key loaded from Kubernetes Secret |

> **Note:** `IRSA_ROLE_ARN` can be left empty when pod identity/IRSA association is already managed externally.

The inherited connector variables remain available here:

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
- `S3_DOCUMENT_BUCKET` (and optional custom prefix)
- image repository/tag
- connector targets/tokens if connectors are enabled

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

## Running the ingestion

```bash
export BEDROCK_KB_ID=replace-me
export BEDROCK_KB_DATA_SOURCE_ID=replace-me
python workspace/ingest.py
```

## Running the RAG chatbot

```bash
export BEDROCK_KB_ID=replace-me
export MODEL_PROVIDER=dual
export AZURE_OPENAI_ENDPOINT=https://<resource>.openai.azure.us/
export AZURE_OPENAI_DEPLOYMENT=gpt-4o
python workspace/rag_chatbot.py
```

## Security notes

- IRSA grants the pod access to Bedrock Knowledge Bases, AOSS, and S3 — no long-lived keys.
- Store Azure API keys in Kubernetes Secrets (or External Secrets), never in plaintext source files.
- Restrict S3 bucket policy to the IRSA role.
- Use VPC endpoints for Bedrock and S3 to keep traffic off the public internet.
