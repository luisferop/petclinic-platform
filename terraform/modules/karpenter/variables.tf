variable "project" {
  description = "Project name"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider (used for the IRSA trust policy)"
  type        = string
}

variable "node_role_arn" {
  description = "ARN of the node IAM role used by Karpenter-launched nodes"
  type        = string
}

variable "service_account_namespace" {
  description = "Namespace of the Karpenter ServiceAccount"
  type        = string
  default     = "kube-system"
}

variable "service_account_name" {
  description = "Name of the Karpenter ServiceAccount"
  type        = string
  default     = "karpenter"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
