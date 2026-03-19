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
  default     = "eks-bedrock-chatbot"
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
  description = "ARN of the IRSA IAM role for the workload ServiceAccount. See docs/iam-policies/bedrock-chatbot-starter-irsa-policy.json."
  sensitive   = true
}

variable "image_repository" {
  type        = string
  description = "Container image repository (e.g. 012345678901.dkr.ecr.us-gov-west-1.amazonaws.com/bedrock-chatbot)."
  default     = "replace-me/eks-bedrock-chatbot"
}

variable "image_tag" {
  type        = string
  description = "Container image tag."
  default     = "latest"
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
  template_tags = ["eks", "bedrock", "chatbot", "aws", "python"]
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
    AWS_REGION       = var.aws_region
    BEDROCK_MODEL_ID = var.bedrock_model_id
    APP_NAMESPACE    = var.k8s_namespace
  }
}

# ---------------------------------------------------------------------------
# Helm release
# ---------------------------------------------------------------------------

resource "helm_release" "chatbot" {
  name      = "bedrock-chatbot"
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
    name             = local.template_name
    owner            = var.workspace_owner
    tags             = local.template_tags
    eks_cluster      = var.eks_cluster_name
    k8s_namespace    = kubernetes_namespace.chatbot.metadata[0].name
    bedrock_model_id = var.bedrock_model_id
    aws_region       = var.aws_region
    helm_release     = helm_release.chatbot.name
  }
  description = "Workspace metadata for Coder UI and auditing."
}
