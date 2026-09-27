# Run with: terraform init -backend=false && terraform test   (no AWS access needed)

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  project_name        = "acme"
  environment         = "staging"
  vpc_id              = "vpc-0abc"
  subnet_id           = "subnet-0abc1"
  allowed_cidr_blocks = ["10.20.16.0/20", "10.20.32.0/20"]
}

run "defaults_are_cheap_and_locked_down" {
  command = plan

  assert {
    condition     = aws_instance.this.instance_type == "t4g.nano" && output.architecture == "arm64"
    error_message = "the cheapest Graviton type, running arm64"
  }

  assert {
    condition     = aws_instance.this.source_dest_check == false
    error_message = "a NAT must forward traffic that is not its own"
  }

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required" && aws_instance.this.root_block_device[0].encrypted
    error_message = "IMDSv2 only, and an encrypted disk"
  }

  assert {
    condition     = aws_instance.this.credit_specification[0].cpu_credits == "standard"
    error_message = "standard credits: never billed beyond the hourly price"
  }

  assert {
    condition     = aws_instance.this.maintenance_options[0].auto_recovery == "default"
    error_message = "recovers on host failure"
  }

  assert {
    condition     = toset(keys(aws_vpc_security_group_ingress_rule.from_allowed)) == toset(["10.20.16.0/20", "10.20.32.0/20"])
    error_message = "only the allowed ranges are admitted"
  }

  assert {
    condition     = aws_instance.this.tags["Name"] == "acme-staging-nat" && aws_eip.this.domain == "vpc"
    error_message = "named <project>-<environment>-nat, with an Elastic IP"
  }

  assert {
    condition     = length(aws_iam_instance_profile.this) == 1
    error_message = "Session Manager access by default"
  }
}

run "the_boot_script_forwards_and_translates_only_the_allowed_ranges" {
  command = plan

  assert {
    condition     = strcontains(local.user_data, "elements = { 10.20.16.0/20, 10.20.32.0/20 }")
    error_message = "the allowed ranges are the nftables set"
  }

  assert {
    condition     = strcontains(local.user_data, "policy drop;") && strcontains(local.user_data, "ip saddr @allowed oifname \"$interface\" masquerade")
    error_message = "forwarding is dropped unless from an allowed range; only those are masqueraded"
  }

  assert {
    condition     = strcontains(local.user_data, "Restart=on-failure") && strcontains(local.user_data, "systemctl enable --now --no-block nat-instance.service")
    error_message = "a service that retries, and runs again on every boot"
  }
}

run "the_image_follows_the_architecture" {
  command = plan

  variables {
    instance_type = "t3.nano"
  }

  assert {
    condition     = output.architecture == "x86_64" && data.aws_ssm_parameter.amazon_linux[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    error_message = "an Intel type runs the x86_64 image"
  }
}

run "a_graviton_type_reads_the_arm64_image" {
  command = plan

  variables {
    instance_type = "c7gn.medium"
  }

  assert {
    condition     = output.architecture == "arm64" && data.aws_ssm_parameter.amazon_linux[0].name == "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
    error_message = "c7gn is Graviton"
  }
}

run "a_given_image_skips_the_lookup" {
  command = plan

  variables {
    ami_id = "ami-0fedcba9876543210"
  }

  assert {
    condition     = length(data.aws_ssm_parameter.amazon_linux) == 0 && aws_instance.this.ami == "ami-0fedcba9876543210"
    error_message = "a caller's image is used as given"
  }
}

run "a_non_burstable_type_has_no_credit_setting" {
  command = plan

  variables {
    instance_type = "c7gn.medium"
  }

  assert {
    condition     = length(aws_instance.this.credit_specification) == 0
    error_message = "only burstable types take a credit mode"
  }
}

run "without_ssm_there_is_no_role" {
  command = plan

  variables {
    enable_ssm = false
  }

  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_iam_instance_profile.this) == 0
    error_message = "no role when Session Manager is off"
  }
}

run "an_open_relay_is_refused" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "no_allowed_ranges_is_refused" {
  command = plan

  variables {
    allowed_cidr_blocks = []
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "a_malformed_range_is_refused" {
  command = plan

  variables {
    allowed_cidr_blocks = ["10.20.0.0/33"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

# AWS accepts only these characters in security group and rule descriptions;
# anything else passes the plan and fails the apply (v1.0.0's egress rule had
# an apostrophe, so the instance had no outbound rule and could not NAT).
run "descriptions_use_only_characters_aws_accepts" {
  command = plan

  assert {
    condition = alltrue([
      for d in concat(
        [aws_security_group.this.description, aws_vpc_security_group_egress_rule.to_internet.description],
        [for r in aws_vpc_security_group_ingress_rule.from_allowed : r.description],
      ) : length(d) <= 255 && can(regex("^[a-zA-Z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]*$", d))
    ])
    error_message = "a security group or rule description uses a character AWS refuses"
  }
}
