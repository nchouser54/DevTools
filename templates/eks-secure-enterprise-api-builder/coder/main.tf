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

variable "workspace_name" {
  type        = string
  description = "Coder workspace display name."
  default     = "eks-secure-api-builder"
}

variable "workspace_owner" {
  type        = string
  description = "Team or individual that owns the workspace."
  default     = "platform-team"
}

variable "aws_region" {
  type        = string
  description = "AWS region where EKS cluster is running."
  default     = "us-gov-west-1"
}

variable "eks_cluster_name" {
  type        = string
  description = "Target EKS cluster name."
  default     = "devtools-cluster"
}

variable "k8s_namespace" {
  type        = string
  description = "Namespace for the API workload."
  default     = "secure-api"
}

variable "irsa_role_arn" {
  type        = string
  description = "ARN for the IRSA role used by the API ServiceAccount. See docs/iam-policies/secure-enterprise-api-builder-irsa-policy.json."
  sensitive   = true
}

variable "image_repository" {
  type        = string
  description = "Container image repository URI."
  default     = "replace-me/eks-secure-api-builder"
}

variable "image_tag" {
  type        = string
  description = "Container image tag."
  default     = "latest"
}

variable "api_log_level" {
  type        = string
  description = "Application log level."
  default     = "info"
}

variable "ingress_host" {
  type        = string
  description = "DNS host for Ingress routing (optional)."
  default     = ""
}

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

locals {
  template_name = var.workspace_name
  template_tags = ["eks", "aws", "api", "security", "helm", "irsa"]
}

resource "kubernetes_namespace" "api" {
  metadata {
    name = var.k8s_namespace
    labels = {
      "app.kubernetes.io/managed-by"    = "coder"
      "app.kubernetes.io/part-of"       = var.workspace_name
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }
}

resource "kubernetes_service_account" "api" {
  metadata {
    name      = "secure-api"
    namespace = kubernetes_namespace.api.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = var.irsa_role_arn
    }
  }
}

resource "kubernetes_config_map" "api_config" {
  metadata {
    name      = "secure-api-config"
    namespace = kubernetes_namespace.api.metadata[0].name
  }

  data = {
    AWS_REGION    = var.aws_region
    API_LOG_LEVEL = var.api_log_level
  }
}

resource "helm_release" "api_builder" {
  name      = "secure-api-builder"
  chart     = "${path.module}/../helm"
  namespace = kubernetes_namespace.api.metadata[0].name

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
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.api.metadata[0].name
  }

  set {
    name  = "app.logLevel"
    value = var.api_log_level
  }

  set {
    name  = "ingress.host"
    value = var.ingress_host
  }

  set_sensitive {
    name  = "aws.irsaRoleArn"
    value = var.irsa_role_arn
  }

  depends_on = [
    kubernetes_namespace.api,
    kubernetes_service_account.api,
    kubernetes_config_map.api_config,
  ]
}

output "template_summary" {
  value = {
    name          = local.template_name
    owner         = var.workspace_owner
    tags          = local.template_tags
    aws_region    = var.aws_region
    eks_cluster   = var.eks_cluster_name
    k8s_namespace = kubernetes_namespace.api.metadata[0].name
    helm_release  = helm_release.api_builder.name
  }
  description = "Workspace metadata for Coder UI and operational handoff."
}
