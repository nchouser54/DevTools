terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23, < 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0"
    }
    coder = {
      source  = "coder/coder"
      version = ">= 0.11.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables – operators supply these when importing the template into Coder.
# ---------------------------------------------------------------------------

variable "workspace_name" {
  type        = string
  description = "Coder workspace display name override. Leave empty to use the active Coder workspace name."
  default     = ""
}

variable "workspace_owner" {
  type        = string
  description = "Team or individual that owns the workspace."
  default     = "platform-team"
}

variable "workspace_owner_email" {
  type        = string
  description = "Email for the workspace owner. Used for optional owner-only auth enforcement."
  default     = ""
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

variable "model_provider" {
  type        = string
  description = "AI provider mode: bedrock, azure, or dual (both available; request can select provider)."
  default     = "bedrock"

  validation {
    condition     = contains(["bedrock", "azure", "dual"], lower(var.model_provider))
    error_message = "model_provider must be one of: bedrock, azure, dual"
  }
}

variable "azure_openai_endpoint" {
  type        = string
  description = "Azure OpenAI endpoint (Gov tenant), e.g. https://<resource>.openai.azure.us/."
  default     = ""
}

variable "azure_openai_deployment" {
  type        = string
  description = "Azure OpenAI deployment name used by the chatbot when provider mode includes azure."
  default     = ""
}

variable "azure_openai_api_version" {
  type        = string
  description = "Azure OpenAI API version."
  default     = "2024-10-21"
}

variable "azure_openai_api_key_secret_name" {
  type        = string
  description = "Kubernetes Secret name that stores AZURE_OPENAI_API_KEY. Secret should be created by backend secret management."
  default     = "azure-openai"
}

variable "azure_openai_api_key_secret_key" {
  type        = string
  description = "Secret key field containing the Azure OpenAI API key."
  default     = "api-key"
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
  description = "Kubernetes namespace override. Leave empty to auto-derive from workspace name."
  default     = ""
}

variable "irsa_role_arn" {
  type        = string
  description = "Optional ARN of the IRSA IAM role for the workload ServiceAccount. Leave empty when pod identity/IRSA is already managed externally. See template-specific policy examples under docs/iam-policies/."
  default     = ""
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

variable "enable_request_auth" {
  type        = bool
  description = "Require upstream authenticated user headers for all endpoints except /health."
  default     = false
}

variable "auth_owner_only" {
  type        = bool
  description = "If true and workspace_owner_email is set, only that email is allowed to access chatbot endpoints."
  default     = false
}

variable "auth_allowed_emails" {
  type        = string
  description = "Comma-separated allowed email list for request auth (used when auth_owner_only is false)."
  default     = ""
}

variable "auth_trusted_email_headers_csv" {
  type        = string
  description = "Comma-separated header names (in priority order) used to extract authenticated user email from upstream proxy/auth gateway."
  default     = "X-Forwarded-Email,X-Auth-Request-Email,X-Forwarded-User,Remote-Email"
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

variable "github_repo_scope" {
  type        = string
  description = "GitHub repo access scope for connector clients: any, configured, or allowlist."
  default     = "any"

  validation {
    condition     = contains(["any", "configured", "allowlist"], lower(var.github_repo_scope))
    error_message = "github_repo_scope must be one of: any, configured, allowlist"
  }
}

variable "github_allowed_repositories_csv" {
  type        = string
  description = "Comma-separated allow-list of owner/repo values used when github_repo_scope=allowlist."
  default     = ""
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
  default = ""
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
  default = ""
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

provider "coder" {
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  template_name = length(trimspace(var.workspace_name)) > 0 ? trimspace(var.workspace_name) : try(data.coder_workspace.me.name, "eks-bedrock-chatbot-enterprise")
  template_tags = [
    "eks", "bedrock", "azure-openai", "rag", "chatbot", "enterprise",
    "cognito", "eso", "otel", "security"
  ]
  ai_provider = lower(var.model_provider)
  github_repo_scope_effective = lower(var.github_repo_scope)
  k8s_namespace_effective = length(trimspace(var.k8s_namespace)) > 0 ? trimspace(var.k8s_namespace) : substr(regexreplace(lower(local.template_name), "[^a-z0-9-]", "-"), 0, 63)
  jira_user_email_effective = length(trimspace(var.jira_user_email)) > 0 ? trimspace(var.jira_user_email) : trimspace(var.workspace_owner_email)
  confluence_user_email_effective = length(trimspace(var.confluence_user_email)) > 0 ? trimspace(var.confluence_user_email) : trimspace(var.workspace_owner_email)
  auth_allowed_emails_effective = (
    var.auth_owner_only && length(trimspace(var.workspace_owner_email)) > 0
    ? trimspace(var.workspace_owner_email)
    : var.auth_allowed_emails
  )
}

# ---------------------------------------------------------------------------
# Kubernetes resources
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "chatbot" {
  metadata {
    name = local.k8s_namespace_effective
    labels = {
      "app.kubernetes.io/managed-by" = "coder"
      "app.kubernetes.io/part-of"    = local.template_name
    }
  }
}

resource "kubernetes_service_account" "chatbot" {
  metadata {
    name      = "chatbot"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
    annotations = length(trimspace(var.irsa_role_arn)) > 0 ? {
      "eks.amazonaws.com/role-arn" = var.irsa_role_arn
    } : {}
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
    MODEL_PROVIDER             = local.ai_provider
    AZURE_OPENAI_ENDPOINT      = var.azure_openai_endpoint
    AZURE_OPENAI_DEPLOYMENT    = var.azure_openai_deployment
    AZURE_OPENAI_API_VERSION   = var.azure_openai_api_version
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
    APP_NAMESPACE              = local.k8s_namespace_effective
    GITHUB_ENABLED             = tostring(var.enable_github_connector)
    GITHUB_SERVER_URL          = var.github_server_url
    GITHUB_REPOSITORY          = var.github_repository
    GITHUB_BRANCH              = var.github_branch
    GITHUB_REPO_SCOPE          = local.github_repo_scope_effective
    GITHUB_ALLOWED_REPOSITORIES = var.github_allowed_repositories_csv
    JIRA_ENABLED               = tostring(var.enable_jira_connector)
    JIRA_SERVER_URL            = var.jira_server_url
    JIRA_PROJECT_KEY           = var.jira_project_key
    JIRA_USER_EMAIL            = local.jira_user_email_effective
    CONFLUENCE_ENABLED         = tostring(var.enable_confluence_connector)
    CONFLUENCE_SERVER_URL      = var.confluence_server_url
    CONFLUENCE_SPACE_KEY       = var.confluence_space_key
    CONFLUENCE_USER_EMAIL      = local.confluence_user_email_effective
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

  set {
    name  = "ai.provider"
    value = local.ai_provider
  }

  set {
    name  = "ai.azure.endpoint"
    value = var.azure_openai_endpoint
  }

  set {
    name  = "ai.azure.deployment"
    value = var.azure_openai_deployment
  }

  set {
    name  = "ai.azure.apiVersion"
    value = var.azure_openai_api_version
  }

  set {
    name  = "ai.azure.apiKeySecret.name"
    value = var.azure_openai_api_key_secret_name
  }

  set {
    name  = "ai.azure.apiKeySecret.key"
    value = var.azure_openai_api_key_secret_key
  }

  dynamic "set_sensitive" {
    for_each = length(trimspace(var.irsa_role_arn)) > 0 ? [1] : []
    content {
      name  = "aws.irsaRoleArn"
      value = var.irsa_role_arn
    }
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
    name  = "auth.required"
    value = tostring(var.enable_request_auth)
  }

  set {
    name  = "auth.allowedEmails"
    value = local.auth_allowed_emails_effective
  }

  set {
    name  = "auth.trustedEmailHeadersCsv"
    value = var.auth_trusted_email_headers_csv
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
    name  = "connectors.github.repoScope"
    value = local.github_repo_scope_effective
  }

  set {
    name  = "connectors.github.allowedRepositoriesCsv"
    value = var.github_allowed_repositories_csv
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
# Kubernetes Service – expose chatbot on external IP
# ---------------------------------------------------------------------------

resource "kubernetes_service" "chatbot" {
  metadata {
    name      = "chatbot"
    namespace = kubernetes_namespace.chatbot.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "chatbot"
      "app.kubernetes.io/managed-by" = "coder"
    }
  }

  spec {
    selector = {
      "app.kubernetes.io/name" = "chatbot"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }

  depends_on = [helm_release.chatbot]
}

# ---------------------------------------------------------------------------
# Outputs – consumed by Coder workspace metadata panel.
# ---------------------------------------------------------------------------

output "template_summary" {
  value = {
    name                    = local.template_name
    owner                   = var.workspace_owner
    owner_email             = var.workspace_owner_email
    tags                    = local.template_tags
    eks_cluster             = var.eks_cluster_name
    k8s_namespace           = kubernetes_namespace.chatbot.metadata[0].name
    bedrock_model_id        = var.bedrock_model_id
    ai_provider             = local.ai_provider
    azure_endpoint          = var.azure_openai_endpoint
    azure_deployment        = var.azure_openai_deployment
    bedrock_embedding_model = var.bedrock_embedding_model_id
    bedrock_kb_id           = var.bedrock_kb_id
    cognito_user_pool_id    = var.cognito_user_pool_id
    aws_region              = var.aws_region
    helm_release            = helm_release.chatbot.name
    otel_service_name       = var.otel_service_name
    auth_required           = var.enable_request_auth
    auth_owner_only         = var.auth_owner_only
    auth_allowed_emails     = local.auth_allowed_emails_effective
    chatbot_service         = kubernetes_service.chatbot.metadata[0].name
    github_target = {
      server     = var.github_server_url
      repository = var.github_repository
      branch     = var.github_branch
      repo_scope = local.github_repo_scope_effective
      allowlist  = var.github_allowed_repositories_csv
    }
    jira_target = {
      server  = var.jira_server_url
      project = var.jira_project_key
      user    = local.jira_user_email_effective
    }
    confluence_target = {
      server = var.confluence_server_url
      space  = var.confluence_space_key
      user   = local.confluence_user_email_effective
    }
  }
  description = "Enterprise workspace metadata."
}

output "chatbot_service_name" {
  value       = kubernetes_service.chatbot.metadata[0].name
  description = "Kubernetes Service name for accessing the enterprise chatbot."
}

output "chatbot_namespace" {
  value       = kubernetes_namespace.chatbot.metadata[0].name
  description = "Kubernetes namespace where enterprise chatbot is deployed."
}

output "chatbot_loadbalancer_hostname" {
  value       = try(kubernetes_service.chatbot.status[0].load_balancer[0].ingress[0].hostname, "pending")
  description = "LoadBalancer hostname (AWS) for accessing the chatbot. May show 'pending' if still provisioning."
}

output "chatbot_loadbalancer_ip" {
  value       = try(kubernetes_service.chatbot.status[0].load_balancer[0].ingress[0].ip, "pending")
  description = "LoadBalancer IP address for accessing the chatbot. May show 'pending' if still provisioning."
}

output "embedding_model" {
  value       = var.bedrock_embedding_model_id
  description = "Bedrock embedding model ID used for RAG document ingestion."
}

output "knowledge_base_id" {
  value       = var.bedrock_kb_id
  description = "Bedrock Knowledge Base ID for RAG-powered responses."
}

output "cognito_user_pool" {
  value       = var.cognito_user_pool_id
  description = "AWS Cognito User Pool ID for enterprise authentication."
}

output "otel_service" {
  value       = var.otel_service_name
  description = "OpenTelemetry service name for observability."
}

# ---------------------------------------------------------------------------
# Coder metadata – workspace UI integration
# ---------------------------------------------------------------------------

data "coder_workspace" "me" {
}

resource "coder_metadata" "workspace_info" {
  count = data.coder_workspace.me.name != "" ? 1 : 0

  resource_id = data.coder_workspace.me.id
  icon        = "https://raw.githubusercontent.com/aws-samples/amazon-bedrock-workshop/main/00_intro/images/bedrock_icon.png"
  hide        = false

  item {
    key   = "cluster"
    value = var.eks_cluster_name
  }

  item {
    key   = "namespace"
    value = kubernetes_namespace.chatbot.metadata[0].name
  }

  item {
    key   = "bedrock_model"
    value = var.bedrock_model_id
  }

  item {
    key   = "ai_provider"
    value = local.ai_provider
  }

  item {
    key   = "embedding_model"
    value = var.bedrock_embedding_model_id
  }

  item {
    key   = "knowledge_base"
    value = var.bedrock_kb_id
  }

  item {
    key   = "cognito_pool"
    value = var.cognito_user_pool_id
  }

  item {
    key   = "otel_service"
    value = var.otel_service_name
  }

  item {
    key   = "github_repo_scope"
    value = local.github_repo_scope_effective
  }

  item {
    key   = "auth_required"
    value = tostring(var.enable_request_auth)
  }

  item {
    key   = "auth_owner_only"
    value = tostring(var.auth_owner_only)
  }

  item {
    key   = "service_account"
    value = kubernetes_service_account.chatbot.metadata[0].name
  }
}

resource "coder_metadata" "chatbot_access" {
  count = data.coder_workspace.me.name != "" ? 1 : 0

  resource_id = kubernetes_service.chatbot.id
  icon        = "https://www.svgrepo.com/show/353382/openai.svg"
  hide        = false

  item {
    key   = "service_name"
    value = kubernetes_service.chatbot.metadata[0].name
  }

  item {
    key   = "service_port"
    value = "80"
  }

  item {
    key   = "target_port"
    value = "8080"
  }

  item {
    key   = "service_type"
    value = kubernetes_service.chatbot.spec[0].type
  }

  item {
    key   = "status"
    value = try(kubernetes_service.chatbot.status[0].load_balancer[0].ingress[0].hostname != "", false) || try(kubernetes_service.chatbot.status[0].load_balancer[0].ingress[0].ip != "", false) ? "Ready" : "Provisioning"
  }
}

