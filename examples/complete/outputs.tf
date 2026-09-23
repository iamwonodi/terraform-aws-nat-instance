output "public_ip" {
  description = "The address the private subnets' traffic leaves from."
  value       = module.nat_instance.public_ip
}

output "instance_id" {
  description = "The NAT instance, for Session Manager."
  value       = module.nat_instance.instance_id
}
