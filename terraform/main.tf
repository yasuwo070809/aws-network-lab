locals {
  name = var.project_name

  common_tags = {
    Project = var.project_name
  }
}

# Latest Amazon Linux 2023 AMI via the official SSM parameter (no hardcoded/region-pinned AMI ID).
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Current global IP, used to scope SSH ingress to /32 when ssh_ingress_cidr is not overridden.
data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  detected_ssh_cidr = "${trimspace(data.http.my_ip.response_body)}/32"
  ssh_ingress_cidr  = coalesce(var.ssh_ingress_cidr, local.detected_ssh_cidr)
}
