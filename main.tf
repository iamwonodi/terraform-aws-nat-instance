# -----------------------------------------------------------------------------
# NAT Instance
# -----------------------------------------------------------------------------
# One EC2 instance acting as the NAT for private subnets: a far cheaper
# alternative to a NAT Gateway (a small hourly price, and no per-GB processing
# charge), at the price of throughput and availability.
#
#   private host --> route 0.0.0.0/0 --> this instance's network interface
#                --> masqueraded behind its Elastic IP --> Internet Gateway
#
# The caller points its route tables at network_interface_id. If the instance
# is ever rebuilt, the interface changes and so do the routes, in the same apply.
#
# Self-healing is EC2's automatic recovery: if the host it runs on fails, AWS
# moves the instance to healthy hardware with the same interface, addresses and
# Elastic IP. While that happens (minutes), outbound traffic stops -- the
# reason a production environment may prefer a NAT Gateway.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Admits only the allowed ranges; the instance's own rules forward and translate
# only them too. Outbound is open: forwarding to the internet is its job.
# -----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = local.name
  description = "NAT instance ${local.name}."
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { Name = local.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_allowed" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  cidr_ipv4         = each.value
  ip_protocol       = "-1"
  description       = "Traffic from ${each.value} to be translated."

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "to_internet" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Forwarded traffic, and the instance's own updates."

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Session Manager access
# -----------------------------------------------------------------------------
# The only way to the shell: the instance runs no SSH and has no key pair.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  count = var.enable_ssm ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.enable_ssm ? 1 : 0

  name               = local.name
  description        = "Session Manager access to the NAT instance ${local.name}."
  assume_role_policy = data.aws_iam_policy_document.trust[0].json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = var.enable_ssm ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  count = var.enable_ssm ? 1 : 0

  name = local.name
  role = aws_iam_role.this[0].name

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# The Instance
# -----------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami           = local.ami_id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.this.id]

  # A NAT forwards packets that are neither from nor for itself.
  source_dest_check = false

  iam_instance_profile = var.enable_ssm ? aws_iam_instance_profile.this[0].name : null

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # Recover on the same interface and Elastic IP if the underlying host fails.
  maintenance_options {
    auto_recovery = "default"
  }

  dynamic "credit_specification" {
    for_each = local.burstable ? [1] : []

    content {
      cpu_credits = var.cpu_credits
    }
  }

  tags = merge(local.common_tags, { Name = local.name })

  lifecycle {
    # A newer Amazon Linux image must not replace a running NAT (and cut every
    # host's outbound traffic) on an unrelated apply. See the README to update.
    ignore_changes = [ami]

    precondition {
      condition     = local.ami_id != null
      error_message = "No image: set ami_id, or leave it null to use the latest Amazon Linux 2023."
    }
  }
}

# -----------------------------------------------------------------------------
# Elastic IP
# -----------------------------------------------------------------------------
# A stable public address for everything the private subnets send out, which
# outside services can allowlist. It survives recovery; it is released only
# when the NAT is destroyed.
# -----------------------------------------------------------------------------

resource "aws_eip" "this" {
  domain   = "vpc"
  instance = aws_instance.this.id

  tags = merge(local.common_tags, { Name = local.name })
}
