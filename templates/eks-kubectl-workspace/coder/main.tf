terraform {
  required_version = ">= 1.5.0"
}

variable "workspace_name" {
  type        = string
  description = "Workspace name shown in Coder."
  default     = "eks-kubectl-workspace"
}

variable "workspace_owner" {
  type        = string
  description = "Workspace owner or team."
  default     = "platform-team"
}

variable "aws_region" {
  type        = string
  description = "AWS region for EKS API operations."
  default     = "us-gov-west-1"
}

variable "eks_cluster_name" {
  type        = string
  description = "Target EKS cluster name for kubectl operations."
  default     = "devtools-cluster"
}

variable "default_kube_namespace" {
  type        = string
  description = "Default namespace used by helper commands."
  default     = "default"
}

variable "auto_configure_kubeconfig" {
  type        = bool
  description = "Whether startup flow should automatically configure kubeconfig for the target EKS cluster."
  default     = true
}

variable "enable_helm" {
  type        = bool
  description = "Whether Helm should be installed in the workspace image during bootstrap."
  default     = false
}

variable "helm_version" {
  type        = string
  description = "Helm version to install when enable_helm is true. Example: v3.16.2"
  default     = "v3.16.2"
}

locals {
  template_name = var.workspace_name
  template_tags = compact([
    "eks",
    "kubectl",
    "kubernetes",
    "aws",
    "operations",
    var.enable_helm ? "helm" : ""
  ])
}

output "template_summary" {
  value = {
    name            = local.template_name
    owner           = var.workspace_owner
    tags            = local.template_tags
    aws_region      = var.aws_region
    eks_cluster     = var.eks_cluster_name
    kube_namespace  = var.default_kube_namespace
    auto_kubeconfig = var.auto_configure_kubeconfig
    helm = {
      enabled = var.enable_helm
      version = var.helm_version
    }
    startup_env = {
      WORKSPACE_NAME           = var.workspace_name
      WORKSPACE_OWNER          = var.workspace_owner
      AWS_REGION               = var.aws_region
      EKS_CLUSTER_NAME         = var.eks_cluster_name
      DEFAULT_KUBE_NAMESPACE   = var.default_kube_namespace
      AUTO_CONFIGURE_KUBECONFIG = tostring(var.auto_configure_kubeconfig)
      ENABLE_HELM              = tostring(var.enable_helm)
      HELM_VERSION             = var.helm_version
    }
    helper_commands = [
      "eks-login",
      "kctx-check"
    ]
  }
  description = "Workspace metadata and startup contract for EKS kubectl operations."
}
