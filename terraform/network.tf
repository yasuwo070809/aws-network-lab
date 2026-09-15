# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc"
  })
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false # the public EC2 gets reachability via an explicit Elastic IP, not an auto-assigned ephemeral public IP

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-subnet"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-subnet"
    Tier = "private"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-igw"
  })
}

# ---------------------------------------------------------------------------
# Public route table: 0.0.0.0/0 -> IGW
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-rt"
  })
}

# Kept as a standalone resource (rather than an inline `route` block) so the
# route-failure injection script can `terraform destroy -target` /
# `aws ec2 delete-route` this single resource without touching the route table itself.
resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Private route table: local only (no NAT Gateway in Phase 1 - see docs/cost-and-cleanup.md)
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Custom NACLs (explicit, not the account's implicit Default NACL) so
# verification 3 / the NACL fault-injection test can be scripted safely
# without touching anything outside this lab's own subnets.
# Default rule set below mirrors the permissive behavior of a Default NACL
# (allow all in/out) so it is transparent until a test deliberately narrows it.
# ---------------------------------------------------------------------------
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.public.id]

  tags = merge(local.common_tags, {
    Name = "${local.name}-public-nacl"
  })
}

resource "aws_network_acl_rule" "public_in_allow_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "public_out_allow_all" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.private.id]

  tags = merge(local.common_tags, {
    Name = "${local.name}-private-nacl"
  })
}

resource "aws_network_acl_rule" "private_in_allow_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "private_out_allow_all" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# SSM VPC interface endpoints (verification 5) - NOT created by default.
# Costs ~3 endpoints x $0.014/hr + per-GB data processing, in addition to the
# normal per-AZ hourly charge. Only enabled after explicit approval by
# setting enable_ssm_vpc_endpoints = true (see docs/cost-and-cleanup.md).
# This is the deliberate alternative to standing up a NAT Gateway early.
# ---------------------------------------------------------------------------
data "aws_region" "current" {}

locals {
  ssm_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each            = var.enable_ssm_vpc_endpoints ? toset(local.ssm_endpoint_services) : []
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpce-${each.value}"
  })
}
