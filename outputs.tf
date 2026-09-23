output "network_interface_id" {
  description = "The instance's network interface. Route tables send 0.0.0.0/0 here (terraform-aws-routing's nat_network_interface_id)."
  value       = aws_instance.this.primary_network_interface_id
}

output "instance_id" {
  description = "ID of the NAT instance, for Session Manager and diagnosis."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The Elastic IP every translated connection leaves from; the address outside services see."
  value       = aws_eip.this.public_ip
}

output "private_ip" {
  description = "The instance's private address."
  value       = aws_instance.this.private_ip
}

output "security_group_id" {
  description = "The NAT instance's security group."
  value       = aws_security_group.this.id
}

output "architecture" {
  description = "arm64 or x86_64, following the instance type."
  value       = local.architecture
}
