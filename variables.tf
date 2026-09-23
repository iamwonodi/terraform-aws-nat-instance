# -----------------------------------------------------------------------------
# Naming
# -----------------------------------------------------------------------------

variable "project_name" {
  type        = string
  description = "Project the NAT instance belongs to. Part of its name."

  validation {
    condition     = trimspace(var.project_name) != ""
    error_message = "project_name must not be empty."
  }
}

variable "environment" {
  type        = string
  description = "Environment the NAT instance belongs to. Part of its name."

  validation {
    condition     = trimspace(var.environment) != ""
    error_message = "environment must not be empty."
  }
}

variable "name" {
  type        = string
  default     = "nat"
  description = "Distinguishes this NAT instance in the project and environment. Resources are named <project>-<environment>-<name>."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase letters, digits and hyphens, starting with a letter or digit."
  }
}

# -----------------------------------------------------------------------------
# Network
# -----------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "VPC the NAT instance serves."

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID (vpc-...)."
  }
}

variable "subnet_id" {
  type        = string
  description = "A PUBLIC subnet (one routing to an Internet Gateway) to place the instance in. It reaches the internet from there, through its Elastic IP."

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must be a subnet ID (subnet-...)."
  }
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  description = "IPv4 ranges allowed to send traffic through the NAT, for example the private and internal tiers' ranges. Only these are admitted by its security group and translated by it."

  validation {
    condition     = length(var.allowed_cidr_blocks) > 0 && alltrue([for cidr in var.allowed_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "allowed_cidr_blocks must contain at least one valid IPv4 CIDR block."
  }

  validation {
    condition     = !contains(var.allowed_cidr_blocks, "0.0.0.0/0")
    error_message = "allowed_cidr_blocks must not be 0.0.0.0/0: that would make this an open relay for anyone who can reach it."
  }
}

# -----------------------------------------------------------------------------
# Instance
# -----------------------------------------------------------------------------

variable "instance_type" {
  type        = string
  default     = "t4g.nano"
  description = "Instance type. t4g.nano (Graviton, 2 vCPUs, 0.5 GiB) is the cheapest; its network bandwidth, not its CPU, is what limits a NAT. The image's architecture follows the type: Graviton types (t4g, c7g, ...) run arm64, others x86_64."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like t4g.nano."
  }
}

variable "ami_id" {
  type        = string
  default     = null
  description = "Image to run. Null uses the latest Amazon Linux 2023 for the instance type's architecture, read when the instance is created; a newer image does not replace a running instance (see README)."

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-f]+$", coalesce(var.ami_id, "x")))
    error_message = "ami_id must be an AMI ID (ami-...)."
  }
}

variable "cpu_credits" {
  type        = string
  default     = "standard"
  description = "CPU credit mode for burstable types: \"standard\" never bills beyond the hourly price (bursts stop when credits run out); \"unlimited\" may. Ignored by non-burstable types."

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be \"standard\" or \"unlimited\"."
  }
}

variable "root_volume_size" {
  type        = number
  default     = 8
  description = "Root volume in GiB, encrypted gp3. Amazon Linux 2023 needs 8."

  validation {
    condition     = var.root_volume_size >= 8
    error_message = "root_volume_size must be at least 8 GiB."
  }
}

variable "enable_ssm" {
  type        = bool
  default     = true
  description = "Give the instance a role for Session Manager, the only way to reach its shell: there is no SSH."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}
