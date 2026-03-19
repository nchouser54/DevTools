terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables – operators supply these when importing the template into Coder.
# ---------------------------------------------------------------------------

variable "workspace_name" {
  type        = string
  description = "Coder workspace display name."
  default     = "eks-bedrock-chatbot-enterprise"
}

variable "workspace_owner" {
  type        = string
  description = "Team or individual that owns the workspace."
  default     = "platform-team"
}

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region where Bedrock and EKS reside."
  default     = "us-gov-west-1"
}

variable "bedrock_model_id" {
  type        = string
  description = "Primary Bedrock model ID. Set this to your GovCloud Sonnet 4.5 model ID."
  default     = "replace-with-govcloud-sonnet-4.5-model-id"
}

variable "bedrock_embedding_model_id" {
  type        = string
  description = "Bedrock embedding model ID for Knowledge Base retrieval."
  default     = "amazon.titan-embed-text-v2:0"
}

variable "eks_cluster_name" {
  type        = string
  description = "Target EKS cluster name."
  default     = "devtools-cluster"
}

variable "k8s_namespace" {
  type        = string
  description = "Kubernetes namespace for the chatbot workload."
  default     = "chatbot"
}

variable "irsa_role_arn" {
  type        = string
  description = "ARN of the IRSA IAM role for the workload ServiceAccount. See docs/iam-policies/bedrock-chatbot-enterprise-irsa-policy.json."
  sensitive   = true
}

variable "image_repository" {
  type        = string
  description = "Container image repository (e.g. 012345678901.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-enterprise)."
  default     = "replace-me/eks-bedrock-chatbot-enterprise"
}

variable "image_tag" {
  type        = string
  description = "Container image tag."
  default     = "latest"
}

variable "bedrock_kb_id" {
  type        = string
  description = "Amazon Bedrock Knowledge Base ID."
}

variable "bedrock_kb_data_source_id" {
  type        = string
  description = "Bedrock Knowledge Base data source ID."
}

variable "s3_document_bucket" {
  type        = string
  description = "S3 bucket containing source documents for knowledge base ingestion."
}

variable "s3_document_prefix" {
  type        = string
  description = "S3 key prefix to scope ingestion."
  default     = "docs/"
}

variable "rag_max_results" {
  type        = number
  description = "Maximum number of Knowledge Base results returned per query."
  default     = 5
}

variable "ingestion_schedule" {
  type        = string
  description = "Cron schedule for the Knowledge Base ingestion job."
  default     = "0 * * * *"
}

variable "cognito_user_pool_id" {
  type        = string
  description = "Amazon Cognito User Pool ID for request authentication."
}

variable "cognito_client_id" {
  type        = string
  description = "Cognito app client ID."
  sensitive   = true
}

variable "cognito_region" {
  type        = string
  description = "AWS region where the Cognito User Pool is provisioned."
  default     = "us-gov-west-1"
}

variable "eso_secret_store_name" {
  type        = string
  description = "Name of the ESO ClusterSecretStore or SecretStore used to sync secrets from AWS Secrets Manager."
  default     = "aws-secrets-store"
}

variable "otel_service_name" {
  type        = string
  description = "OpenTelemetry service name for trace/metric labeling."
  default     = "bedrock-chatbot-enterprise"
}

variable "otel_collector_endpoint" {
  type        = string
  description = "OTLP gRPC endpoint for the ADOT/OTel collector sidecar."
  default     = "http://adot-collector:4317"
}

variable "enable_github_connector" {
  type    = bool
  default = false
}

variable "enable_jira_connector" {
  type    = bool
  default = false
}

variable "enable_confluence_connector" {
  type    = bool
  default = false
}

variable "github_server_url" {
  type    = string
  default = "https://github.com"
}

variable "github_repository" {
  type    = string
  default = "owner/repo"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "github_personal_access_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "jira_server_url" {
  type    = string
  default = "https://your-org.atlassian.net"
}

variable "jira_project_key" {
  type    = string
  default = "TEAM"
}

variable "jira_user_email" {
  type    = string
  default = "you@example.com"
}

variable "jira_pat" {
  type      = string
  default   = ""
  sensitive = true
}

variable "confluence_server_url" {
  type    = string
  default = "https://your-org.atlassian.net/wiki"
}

variable "confluence_space_key" {
  type    = string
  default = "ENG"
}

variable "confluence_user_email" {
  type    = string
  default = "you@example.com"
}

variable "confluence_pat" {
  type      = string
  default   = ""
  sensitive = true
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.eks_cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  template_name = var.workspace_name
  template_tags = [
    "eks", "bedrock", "rag", "chatbot", "enterprise",
    "cognito", "eso", "otel", "security"
  ]
}

# ---------------------------------------------------------------------------
# Kubernetes resources
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "chatbot" {
  metadata {
    name = var.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "coder"
      "app.kubernetes.io/part-of"    = var.workspace_name
    }
  }
}

resource "kubernetes_service_account" "chatbot" {
  metadata {
    name      = "chatbot"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.irsa_role_arn
    }
  }
}

resource "kubernetes_config_map" "chatbot_config" {
  metadata {
    name      = "chatbot-config"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
  }

  data = {
    AWS_REGION                 = var.aws_region
    BEDROCK_MODEL_ID           = var.bedrock_model_id
    BEDROCK_EMBEDDING_MODEL_ID = var.bedrock_embedding_model_id
    BEDROCK_KB_ID              = var.bedrock_kb_id
    BEDROCK_KB_DATA_SOURCE_ID  = var.bedrock_kb_data_source_id
    S3_DOCUMENT_BUCKET         = var.s3_document_bucket
    S3_DOCUMENT_PREFIX         = var.s3_document_prefix
    RAG_MAX_RESULTS            = tostring(var.rag_max_results)
    COGNITO_USER_POOL_ID       = var.cognito_user_pool_id
    COGNITO_REGION             = var.cognito_region
    ESO_SECRET_STORE_NAME      = var.eso_secret_store_name
    OTEL_SERVICE_NAME          = var.otel_service_name
    OTEL_EXPORTER_OTLP_ENDPOINT = var.otel_collector_endpoint
    APP_NAMESPACE              = var.k8s_namespace
    GITHUB_ENABLED             = tostring(var.enable_github_connector)
    GITHUB_SERVER_URL          = var.github_server_url
    GITHUB_REPOSITORY          = var.github_repository
    GITHUB_BRANCH              = var.github_branch
    JIRA_ENABLED               = tostring(var.enable_jira_connector)
    JIRA_SERVER_URL            = var.jira_server_url
    JIRA_PROJECT_KEY           = var.jira_project_key
    JIRA_USER_EMAIL            = var.jira_user_email
    CONFLUENCE_ENABLED         = tostring(var.enable_confluence_connector)
    CONFLUENCE_SERVER_URL      = var.confluence_server_url
    CONFLUENCE_SPACE_KEY       = var.confluence_space_key
    CONFLUENCE_USER_EMAIL      = var.confluence_user_email
  }
}

# Cognito client ID stored as a Kubernetes secret.
resource "kubernetes_secret" "cognito" {
  metadata {
    name      = "cognito-secret"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
  }

  data = {
    COGNITO_CLIENT_ID = var.cognito_client_id
  }

  type = "Opaque"
}

resource "kubernetes_secret" "github_connector" {
  count = var.enable_github_connector ? 1 : 0

  metadata {
    name      = "github-connector-secret"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
  }

  data = {
    GITHUB_PAT = var.github_personal_access_token
  }

  type = "Opaque"
}

resource "kubernetes_secret" "jira_connector" {
  count = var.enable_jira_connector ? 1 : 0

  metadata {
    name      = "jira-connector-secret"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
  }

  data = {
    JIRA_PAT = var.jira_pat
  }

  type = "Opaque"
}

resource "kubernetes_secret" "confluence_connector" {
  count = var.enable_confluence_connector ? 1 : 0

  metadata {
    name      = "confluence-connector-secret"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
  }

  data = {
    CONFLUENCE_PAT = var.confluence_pat
  }

  type = "Opaque"
}

# ---------------------------------------------------------------------------
# Helm release
# ---------------------------------------------------------------------------

resource "helm_release" "chatbot" {
  name      = "bedrock-chatbot-enterprise"
  chart     = "${path.module}/../helm"
  namespace = kubernetes_namespace.chatbot.metadata[0].name

  set {
    name  = "image.repository"
    value = var.image_repository
  }

  set {
    name  = "image.tag"
    value = var.image_tag
  }

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  set {
    name  = "aws.bedrockModelId"
    value = var.bedrock_model_id
  }

  set {
    name  = "aws.bedrockEmbeddingModelId"
    value = var.bedrock_embedding_model_id
  }

  set_sensitive {
    name  = "aws.irsaRoleArn"
    value = var.irsa_role_arn
  }

  set {
    name  = "bedrock.knowledgeBaseId"
    value = var.bedrock_kb_id
  }

  set {
    name  = "bedrock.knowledgeBaseDataSourceId"
    value = var.bedrock_kb_data_source_id
  }

  set {
    name  = "s3.documentBucket"
    value = var.s3_document_bucket
  }

  set {
    name  = "s3.documentPrefix"
    value = var.s3_document_prefix
  }

  set {
    name  = "rag.maxResults"
    value = tostring(var.rag_max_results)
  }

  set {
    name  = "ingestion.schedule"
    value = var.ingestion_schedule
  }

  set {
    name  = "cognito.userPoolId"
    value = var.cognito_user_pool_id
  }

  set {
    name  = "cognito.region"
    value = var.cognito_region
  }

  set {
    name  = "eso.secretStoreName"
    value = var.eso_secret_store_name
  }

  set {
    name  = "otel.endpoint"
    value = var.otel_collector_endpoint
  }

  set {
    name  = "otel.serviceName"
    value = var.otel_service_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.chatbot.metadata[0].name
  }

  set {
    name  = "connectors.github.enabled"
    value = tostring(var.enable_github_connector)
  }

  set {
    name  = "connectors.github.serverUrl"
    value = var.github_server_url
  }

  set {
    name  = "connectors.github.repository"
    value = var.github_repository
  }

  set {
    name  = "connectors.github.branch"
    value = var.github_branch
  }

  set {
    name  = "connectors.jira.enabled"
    value = tostring(var.enable_jira_connector)
  }

  set {
    name  = "connectors.jira.serverUrl"
    value = var.jira_server_url
  }

  set {
    name  = "connectors.jira.projectKey"
    value = var.jira_project_key
  }

  set {
    name  = "connectors.confluence.enabled"
    value = tostring(var.enable_confluence_connector)
  }

  set {
    name  = "connectors.confluence.serverUrl"
    value = var.confluence_server_url
  }

  set {
    name  = "connectors.confluence.spaceKey"
    value = var.confluence_space_key
  }

  depends_on = [
    kubernetes_namespace.chatbot,
    kubernetes_service_account.chatbot,
    kubernetes_config_map.chatbot_config,
    kubernetes_secret.cognito,
  ]
}

# ---------------------------------------------------------------------------
# Outputs – consumed by Coder workspace metadata panel.
# ---------------------------------------------------------------------------

output "template_summary" {
  value = {
    name                    = local.template_name
    owner                   = var.workspace_owner
    tags                    = local.template_tags
    eks_cluster             = var.eks_cluster_name
    k8s_namespace           = kubernetes_namespace.chatbot.metadata[0].name
    bedrock_model_id        = var.bedrock_model_id
    bedrock_embedding_model = var.bedrock_embedding_model_id
    bedrock_kb_id           = var.bedrock_kb_id
    cognito_user_pool_id    = var.cognito_user_pool_id
    aws_region              = var.aws_region
    helm_release            = helm_release.chatbot.name
    otel_service_name       = var.otel_service_name
    github_target = {
      server     = var.github_server_url
      repository = var.github_repository
      branch     = var.github_branch
    }
    jira_target = {
      server  = var.jira_server_url
      project = var.jira_project_key
    }
    confluence_target = {
      server = var.confluence_server_url
      space  = var.confluence_space_key
    }
  }
  description = "Enterprise workspace metadata."
}
