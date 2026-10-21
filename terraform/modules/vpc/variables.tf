variable "project" {
  description = "Project name used for naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either \"dev\" or \"prod\"."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (dev: 10.0.0.0/16, prod: 10.1.0.0/16)"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/(1[6-9]|2[0-8])$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR with a prefix length between /16 and /28."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2 && alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 0))])
    error_message = "Provide at least 2 valid IPv4 CIDR blocks for public_subnet_cidrs."
  }
}

variable "availability_zones" {
  description = "Availability zones for the public subnets (same length and order as public_subnet_cidrs)"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Provide at least 2 distinct availability zones."
  }
}

variable "tags" {
  description = "Additional tags merged onto every resource"
  type        = map(string)
  default     = {}
}
