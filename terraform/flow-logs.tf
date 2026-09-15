resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws-network-lab/${local.name}/vpc-flow-logs"
  retention_in_days = var.flow_logs_retention_days

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${local.name}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_publish" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_publish" {
  name   = "${local.name}-flow-logs-publish"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_publish.json
}

# ALL = both ACCEPT and REJECT records, needed to compare SG-deny vs
# NACL-deny vs missing-route behavior (verification 6 / fault injection tests).
resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = 60

  tags = merge(local.common_tags, {
    Name = "${local.name}-vpc-flow-log"
  })
}
