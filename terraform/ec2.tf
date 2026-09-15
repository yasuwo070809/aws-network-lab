# The private key matching this public key is generated and kept locally by
# the operator (e.g. `ssh-keygen -t ed25519 -f ~/.ssh/aws-network-lab`) and is
# never read, stored, or uploaded by Terraform - only the .pub file is used.
resource "aws_key_pair" "this" {
  key_name   = "${local.name}-key"
  public_key = trimspace(file(var.ssh_public_key_path))

  tags = local.common_tags
}

resource "aws_instance" "public" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.public.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = false # reachability comes from the Elastic IP below
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "<h1>${local.name} public EC2 ($(hostname -f))</h1>" > /var/www/html/index.html
  EOF

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-ec2"
    Tier = "public"
  })

  lifecycle {
    # Once the Elastic IP below is associated, AWS reports the primary
    # network interface as having a public IP, which makes the provider see
    # associate_public_ip_address as having drifted from false -> true and
    # want to replace the instance. It hasn't actually changed at launch
    # time - only the EIP association changed - so this attribute is not a
    # meaningful diff to act on.
    ignore_changes = [associate_public_ip_address]
  }
}

resource "aws_eip" "public" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-eip"
  })
}

resource "aws_eip_association" "public" {
  instance_id   = aws_instance.public.id
  allocation_id = aws_eip.public.id
}

resource "aws_instance" "private" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.private.id]
  key_name                    = aws_key_pair.this.key_name
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_ssm.name

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-ec2"
    Tier = "private"
  })
}
