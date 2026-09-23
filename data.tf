# -----------------------------------------------------------------------------
# Image
# -----------------------------------------------------------------------------
# AWS publishes the latest Amazon Linux 2023 image ID for each architecture as a
# public SSM parameter. Read only when no ami_id is given.
# -----------------------------------------------------------------------------

data "aws_ssm_parameter" "amazon_linux" {
  count = var.ami_id == null ? 1 : 0

  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-${local.architecture}"
}
