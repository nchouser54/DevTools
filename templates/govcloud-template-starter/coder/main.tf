terraform {
  required_version = ">= 1.5.0"
}

variable "workspace_name" {
  type        = string
  description = "Workspace name shown in Coder."
  default     = "govcloud-template-starter"
}

variable "workspace_owner" {
  type        = string
  description = "Workspace owner or team."
  default     = "platform-team"
}

variable "aws_region" {
  type        = string
  description = "AWS GovCloud region for this template."
  default     = "us-gov-west-1"
}

variable "default_kube_namespace" {
  type        = string
  description = "Default Kubernetes namespace used by operational helpers."
  default     = "default"
}

variable "auto_configure_kubeconfig" {
  type        = bool
  description = "Whether startup flow should auto-configure kubeconfig for EKS workflows."
  default     = true
}

variable "enable_helm" {
  type        = bool
  description = "Whether Helm should be installed during workspace bootstrap."
  default     = false
}

variable "helm_version" {
  type        = string
  description = "Helm version to install when enable_helm is true."
  default     = "v3.16.2"
}

variable "enable_xrdp" {
  type        = bool
  description = "Whether Linux XRDP desktop support should be enabled in derived templates."
  default     = false
}

variable "xrdp_port" {
  type        = number
  description = "XRDP listen port when enabled."
  default     = 3389
}

locals {
  template_name = var.workspace_name
  template_slug = "govcloud_template_starter"
  template_tags = [
    "coder",
    "workspace",
    "govcloud",
    "starter"
  ]
}

output "template_summary" {
  value = {
    name            = local.template_name
    slug            = local.template_slug
    owner           = var.workspace_owner
    aws_region      = var.aws_region
    tags            = local.template_tags
    kube_namespace  = var.default_kube_namespace
    auto_kubeconfig = var.auto_configure_kubeconfig
    helm = {
      enabled = var.enable_helm
      version = var.helm_version
    }
    xrdp = {
      enabled = var.enable_xrdp
      port    = var.xrdp_port
    }
    startup_env = {
      WORKSPACE_NAME            = var.workspace_name
      WORKSPACE_OWNER           = var.workspace_owner
      AWS_REGION                = var.aws_region
      DEFAULT_KUBE_NAMESPACE    = var.default_kube_namespace
      AUTO_CONFIGURE_KUBECONFIG = tostring(var.auto_configure_kubeconfig)
      ENABLE_HELM               = tostring(var.enable_helm)
      HELM_VERSION              = var.helm_version
      ENABLE_XRDP               = tostring(var.enable_xrdp)
      XRDP_PORT                 = tostring(var.xrdp_port)
    }
  }
  description = "Starter metadata contract for building consistent GovCloud Coder templates."
}
