# EC2 instance role for Systems Manager (Session Manager, verification 5).
# Attached to both instances: the private one is the actual SSM target, the
# public one gets it too so it can be reached via Session Manager as a
# fallback even if its SSH ingress rule is ever tightened during testing.
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "${local.name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${local.name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = local.common_tags
}
