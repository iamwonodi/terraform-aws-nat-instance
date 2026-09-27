# Terraform AWS NAT Instance

Reusable Terraform module for **one EC2 instance acting as a NAT** for private subnets: a much cheaper alternative to a NAT Gateway for development, staging and other environments that can tolerate a short outbound outage.

```text
  private / internal subnets
            |
            |  route 0.0.0.0/0 --> the instance's network interface
            v
  +---------------------------------------------+
  |  NAT instance (public subnet)               |
  |  Amazon Linux 2023, source/dest check off   |
  |  forwards + masquerades ONLY allowed ranges |
  +----------------------+----------------------+
                         |  Elastic IP
                         v
                  Internet Gateway
```

The module does not create or change route tables. The caller points its private route tables' default route at `network_interface_id`, for example through `terraform-aws-routing`'s `nat_network_interface_id`.

---

# NAT instance or NAT Gateway

| | NAT instance (this module) | NAT Gateway |
| --- | --- | --- |
| Hourly | the instance's price (t4g.nano: a few dollars a month) plus the Elastic IP | about $33 a month in us-east-1, more elsewhere |
| Per GB processed | none | about $0.045 in us-east-1 |
| Throughput | the instance type's network bandwidth | up to 100 Gbps |
| Failure | EC2 automatic recovery moves it to healthy hardware; outbound traffic stops meanwhile | managed, zonal |
| Maintenance | the image (see Updating) | none |

Use it where cost matters more than a few minutes of outbound outage; keep a NAT Gateway where it does not.

---

# How it works

* **The instance** runs the latest Amazon Linux 2023 for its architecture (arm64 for Graviton types such as the default `t4g.nano`, x86_64 otherwise), with source/destination checking off so it can forward traffic that is not its own.
* **At boot** a systemd service enables IP forwarding and loads an nftables ruleset: traffic **from the allowed ranges** is forwarded and masqueraded behind the Elastic IP, replies come back, and **everything else is dropped**. It is not an open relay. The service retries until it succeeds (the instance may have no internet access until its Elastic IP is attached, and installs nftables if missing) and runs again on every boot. Re-running replaces the rules; it never duplicates them.
* **The Elastic IP** is a stable address for everything the private subnets send out, which outside services can allowlist. It survives recovery.
* **Recovery.** `auto_recovery = default`: if the host fails, AWS moves the instance to healthy hardware with the same interface, addresses and Elastic IP.
* **Locked down.** No SSH and no key pair; Session Manager is the only way in (`enable_ssm`). IMDSv2 only; the disk is encrypted. `standard` CPU credits, so it is never billed beyond its hourly price.

---

# Usage

```hcl
module "nat_instance" {
  source = "git::https://github.com/iamwonodi/terraform-aws-nat-instance.git?ref=v1.0.1"

  project_name = "acme"
  environment  = "staging"

  vpc_id    = module.vpc_base.vpc_id
  subnet_id = module.vpc_base.public_subnet_ids[0]

  allowed_cidr_blocks = ["10.20.16.0/20", "10.20.32.0/20"]
}

module "routing" {
  source = "git::https://github.com/iamwonodi/terraform-aws-routing.git?ref=v1.1.0"

  # ...
  nat_network_interface_id = module.nat_instance.network_interface_id
}
```

Without `terraform-aws-routing`, create the routes yourself (see `examples/complete`):

```hcl
resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat_instance.network_interface_id
}
```

---

# Updating the image

The image is read when the instance is created, and later images are **ignored**: a new Amazon Linux release must not replace a running NAT, cutting every private host's outbound traffic, on an unrelated apply. To move to the latest image deliberately:

```bash
terraform apply -replace='module.nat_instance.aws_instance.this'
```

Outbound traffic stops for the minutes the new instance takes to boot. Between replacements, `dnf upgrade` through Session Manager keeps it patched.

---

# Validation

Refused at plan time:

* `allowed_cidr_blocks` empty, malformed, or containing `0.0.0.0/0` (an open relay);
* IDs that are not a VPC, subnet or AMI ID;
* `cpu_credits` other than `standard` or `unlimited`;
* a root volume under 8 GiB.

---

# Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `project_name` | `string` | n/a | Project; part of the name |
| `environment` | `string` | n/a | Environment; part of the name |
| `name` | `string` | `"nat"` | Distinguishes this NAT; resources are `<project>-<environment>-<name>` |
| `vpc_id` | `string` | n/a | VPC the NAT serves |
| `subnet_id` | `string` | n/a | A public subnet to run in |
| `allowed_cidr_blocks` | `list(string)` | n/a | Ranges allowed through the NAT |
| `instance_type` | `string` | `"t4g.nano"` | Instance type; the image's architecture follows it |
| `ami_id` | `string` | `null` | Image; null uses the latest Amazon Linux 2023 |
| `cpu_credits` | `string` | `"standard"` | `standard` or `unlimited`, for burstable types |
| `root_volume_size` | `number` | `8` | Root volume, GiB (encrypted gp3) |
| `enable_ssm` | `bool` | `true` | Role for Session Manager |
| `tags` | `map(string)` | `{}` | Tags for every resource |

# Outputs

| Name | Description |
| --- | --- |
| `network_interface_id` | Where the route tables send `0.0.0.0/0` |
| `instance_id` | The instance, for Session Manager |
| `public_ip` | The Elastic IP outbound traffic leaves from |
| `private_ip` | The instance's private address |
| `security_group_id` | Its security group |
| `architecture` | `arm64` or `x86_64` |

---

# Requirements

| Name | Version |
| --- | --- |
| Terraform | `>= 1.6.0` (`terraform test` needs 1.7 or later) |
| AWS Provider | `>= 6.0.0, < 7.0.0` |

---

# Module Structure

```text
terraform-aws-nat-instance/
├── .gitignore
├── .terraform.lock.hcl
├── README.md
├── versions.tf
├── variables.tf
├── locals.tf
├── data.tf              -- the Amazon Linux image parameter
├── main.tf
├── outputs.tf
├── templates/
│   └── user-data.sh.tftpl
├── tests/
│   └── nat_instance.tftest.hcl
└── examples/
    └── complete/
```

Run the tests with `terraform init -backend=false && terraform test`; the provider is mocked.

---

# Versioning

Semantic Versioning; consume by tag. Current release: `v1.0.1`.

`v1.0.1` fixes the outbound rule's description. `v1.0.0`'s contained an apostrophe, which AWS refuses in security group rule descriptions: the rule was never created, so the instance had no outbound access and could not translate anything, or reach Session Manager. A test now checks every description the module sends to AWS. Inputs and outputs are unchanged. An instance deployed with `v1.0.0` recovers once the rule exists: its setup service keeps retrying until it can install nftables.

---

# License

Provided for reusable AWS infrastructure deployments, to be consumed as a versioned Terraform module.
