# ---------------------------------------------------------------------------
# Public EC2 security group: SSH from the current global IP only, HTTP from
# anywhere (this is the web server under test), all egress.
# ---------------------------------------------------------------------------
resource "aws_security_group" "public" {
  name        = "${local.name}-public-sg"
  description = "Public EC2: SSH from admin IP, HTTP from anywhere"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-sg"
  })
}

resource "aws_security_group_rule" "public_in_ssh" {
  security_group_id = aws_security_group.public.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [local.ssh_ingress_cidr]
  description       = "SSH from current admin global IP (auto-detected unless ssh_ingress_cidr is overridden)"
}

resource "aws_security_group_rule" "public_in_http" {
  security_group_id = aws_security_group.public.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP - web server under test"
}

resource "aws_security_group_rule" "public_out_all" {
  security_group_id = aws_security_group.public.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

# ---------------------------------------------------------------------------
# Private EC2 security group: SSH only from the public EC2's security group
# (bastion), no direct internet ingress. Egress left open so it can reach
# SSM VPC endpoints (when enabled) / future NAT without extra edits.
# ---------------------------------------------------------------------------
resource "aws_security_group" "private" {
  name        = "${local.name}-private-sg"
  description = "Private EC2: SSH from the public EC2 (bastion) only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-sg"
  })
}

resource "aws_security_group_rule" "private_in_ssh_from_public" {
  security_group_id        = aws_security_group.private.id
  type                     = "ingress"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.public.id
  description              = "SSH from the public EC2 (bastion), not from the internet"
}

resource "aws_security_group_rule" "private_out_all" {
  security_group_id = aws_security_group.private.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound (needed for SSM VPC endpoints / yum, no NAT in Phase 1)"
}

# ---------------------------------------------------------------------------
# Security group for the SSM VPC interface endpoints (verification 5).
# Only created when enable_ssm_vpc_endpoints = true.
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  count       = var.enable_ssm_vpc_endpoints ? 1 : 0
  name        = "${local.name}-vpce-sg"
  description = "HTTPS from the private EC2 to the SSM VPC endpoints"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpce-sg"
  })
}

resource "aws_security_group_rule" "vpce_in_https_from_private" {
  count                    = var.enable_ssm_vpc_endpoints ? 1 : 0
  security_group_id        = aws_security_group.vpc_endpoints[0].id
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.private.id
  description              = "HTTPS from the private EC2 (SSM Agent)"
}

resource "aws_security_group_rule" "vpce_out_all" {
  count             = var.enable_ssm_vpc_endpoints ? 1 : 0
  security_group_id = aws_security_group.vpc_endpoints[0].id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
