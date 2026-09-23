locals {
  name = "${var.project_name}-${var.environment}-${var.name}"

  # Graviton families end their generation with "g" (t4g, c7g, c7gn, m8g ...).
  architecture = can(regex("^[a-z]+[0-9]+g[a-z]*\\.", var.instance_type)) ? "arm64" : "x86_64"

  ami_id = coalesce(var.ami_id, try(data.aws_ssm_parameter.amazon_linux[0].value, null))

  burstable = startswith(var.instance_type, "t")

  # Rendered here so the configuration can be tested without an instance.
  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    allowed_cidr_blocks = var.allowed_cidr_blocks
  })

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}
