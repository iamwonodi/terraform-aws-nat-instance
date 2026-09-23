variable "aws_region" {
  type        = string
  description = "AWS Region where the example resources will be created."
  default     = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "ID of the VPC the NAT instance serves."

  validation {
    condition     = trimspace(var.vpc_id) != ""
    error_message = "vpc_id must not be empty."
  }
}

variable "public_subnet_id" {
  type        = string
  description = "ID of a public subnet (one routing to an Internet Gateway) for the NAT instance."

  validation {
    condition     = trimspace(var.public_subnet_id) != ""
    error_message = "public_subnet_id must not be empty."
  }
}

variable "private_route_table_ids" {
  type        = list(string)
  description = "IDs of the private route tables that should send their internet traffic through the NAT instance. They must not already have a 0.0.0.0/0 route."
}

variable "private_cidr_blocks" {
  type        = list(string)
  description = "The private subnets' ranges: the only sources the NAT instance will translate."
}
