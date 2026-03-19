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
  }
}

# ---------------------------------------------------------------------------
# Variables – operators supply these when importing the template into Coder.
# ---------------------------------------------------------------------------

variable "workspace_name" {
  type        = string
  description = "Coder workspace display name."
  default     = "eks-bedrock-chatbot-connectors"
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
  description = "ARN of the IRSA IAM role for the workload ServiceAccount. See docs/iam-policies/bedrock-chatbot-connectors-irsa-policy.json."
  sensitive   = true
}

variable "image_repository" {
  type        = string
  description = "Container image repository (e.g. 012345678901.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot-connectors)."
  default     = "replace-me/eks-bedrock-chatbot-connectors"
}

variable "image_tag" {
  type        = string
  description = "Container image tag."
  default     = "latest"
}

variable "enable_github_connector" {
  type        = bool
  description = "Toggle the GitHub MCP connector at workspace provision time."
  default     = false
}

variable "enable_jira_connector" {
  type        = bool
  description = "Toggle the Jira MCP connector at workspace provision time."
  default     = false
}

variable "enable_confluence_connector" {
  type        = bool
  description = "Toggle the Confluence MCP connector at workspace provision time."
  default     = false
}

variable "allow_connector_writes" {
  type        = bool
  description = "Allow write actions (create issue/page, cross-system workflows) from embedded connector actions."
  default     = false
}

variable "github_server_url" {
  type        = string
  description = "GitHub or GitHub Enterprise Server URL."
  default     = "https://github.com"
}

variable "github_repository" {
  type        = string
  description = "Target GitHub repository in owner/repo form."
  default     = "owner/repo"
}

variable "github_branch" {
  type        = string
  description = "Target Git branch for repository operations."
  default     = "main"
}

variable "github_personal_access_token" {
  type        = string
  description = "GitHub PAT for the designated server and repository."
  default     = ""
  sensitive   = true
}

variable "jira_server_url" {
  type        = string
  description = "Jira server URL."
  default     = "https://your-org.atlassian.net"
}

variable "jira_project_key" {
  type        = string
  description = "Default Jira project key."
  default     = "TEAM"
}

variable "jira_user_email" {
  type        = string
  description = "Jira user email associated with the PAT/API token."
  default     = "you@example.com"
}

variable "jira_pat" {
  type        = string
  description = "Jira PAT/API token for the designated Jira server."
  default     = ""
  sensitive   = true
}

variable "confluence_server_url" {
  type        = string
  description = "Confluence server URL."
  default     = "https://your-org.atlassian.net/wiki"
}

variable "confluence_space_key" {
  type        = string
  description = "Default Confluence space key."
  default     = "ENG"
}

variable "confluence_user_email" {
  type        = string
  description = "Confluence user email associated with the PAT/API token."
  default     = "you@example.com"
}

variable "confluence_pat" {
  type        = string
  description = "Confluence PAT/API token for the designated Confluence server."
  default     = ""
  sensitive   = true
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
  template_tags = ["eks", "bedrock", "chatbot", "connectors", "github", "jira", "confluence"]

  active_connectors = compact([
    var.enable_github_connector ? "github" : "",
    var.enable_jira_connector ? "jira" : "",
    var.enable_confluence_connector ? "confluence" : "",
  ])
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
    AWS_REGION             = var.aws_region
    BEDROCK_MODEL_ID       = var.bedrock_model_id
    APP_NAMESPACE          = var.k8s_namespace
    ALLOW_CONNECTOR_WRITES = tostring(var.allow_connector_writes)
    GITHUB_ENABLED         = tostring(var.enable_github_connector)
    GITHUB_SERVER_URL      = var.github_server_url
    GITHUB_REPOSITORY      = var.github_repository
    GITHUB_BRANCH          = var.github_branch
    JIRA_ENABLED           = tostring(var.enable_jira_connector)
    JIRA_SERVER_URL        = var.jira_server_url
    JIRA_PROJECT_KEY       = var.jira_project_key
    JIRA_USER_EMAIL        = var.jira_user_email
    CONFLUENCE_ENABLED     = tostring(var.enable_confluence_connector)
    CONFLUENCE_SERVER_URL  = var.confluence_server_url
    CONFLUENCE_SPACE_KEY   = var.confluence_space_key
    CONFLUENCE_USER_EMAIL  = var.confluence_user_email
  }
}

# Connector secrets — created only when the connector is enabled.

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
  name      = "bedrock-chatbot-connectors"
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

  set_sensitive {
    name  = "aws.irsaRoleArn"
    value = var.irsa_role_arn
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
    name  = "connectors.allowWrites"
    value = tostring(var.allow_connector_writes)
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
    name  = "connectors.jira.userEmail"
    value = var.jira_user_email
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

  set {
    name  = "connectors.confluence.userEmail"
    value = var.confluence_user_email
  }

  depends_on = [
    kubernetes_namespace.chatbot,
    kubernetes_service_account.chatbot,
    kubernetes_config_map.chatbot_config,
  ]
}

# ---------------------------------------------------------------------------
# Outputs – consumed by Coder workspace metadata panel.
# ---------------------------------------------------------------------------

output "template_summary" {
  value = {
    name              = local.template_name
    owner             = var.workspace_owner
    tags              = local.template_tags
    eks_cluster       = var.eks_cluster_name
    k8s_namespace     = kubernetes_namespace.chatbot.metadata[0].name
    bedrock_model_id  = var.bedrock_model_id
    aws_region        = var.aws_region
    helm_release      = helm_release.chatbot.name
    active_connectors = local.active_connectors
    allow_connector_writes = var.allow_connector_writes
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
  description = "Workspace metadata including enabled connectors."
}
