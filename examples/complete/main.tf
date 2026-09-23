# -----------------------------------------------------------------------------
# Complete Example
# -----------------------------------------------------------------------------
# A NAT instance for existing private subnets:
#
#   - the smallest Graviton instance, with an Elastic IP, in a public subnet;
#   - translating only the private ranges given, so it is no open relay;
#   - the private route tables' default route pointed at its interface.
#
# A caller using terraform-aws-routing passes network_interface_id as that
# module's nat_network_interface_id instead of creating routes itself.
#
# It creates a real instance and Elastic IP, which cost money.
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region
}

module "nat_instance" {
  source = "../../"

  project_name = "example"
  environment  = "staging"

  vpc_id    = var.vpc_id
  subnet_id = var.public_subnet_id

  allowed_cidr_blocks = var.private_cidr_blocks

  tags = {
    Component = "Network"
  }
}

resource "aws_route" "private_default" {
  count = length(var.private_route_table_ids)

  route_table_id         = var.private_route_table_ids[count.index]
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat_instance.network_interface_id
}
