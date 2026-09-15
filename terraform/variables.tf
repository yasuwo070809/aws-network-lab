variable "aws_region" {
  description = "AWS region to build the lab in."
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile (SSO) to use."
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Prefix/tag applied to every resource so this lab is identifiable and easy to clean up."
  type        = string
  default     = "aws-network-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.10.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet."
  type        = string
  default     = "10.10.11.0/24"
}

variable "availability_zone" {
  description = "AZ used for both subnets (single-AZ lab, keeps it simple/cheap)."
  type        = string
  default     = "ap-northeast-1a"
}

variable "instance_type" {
  description = "EC2 instance type. Free-tier eligible where possible."
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key_path" {
  description = "Path to a LOCAL public key file (e.g. ~/.ssh/aws-network-lab.pub). The matching private key is never uploaded to AWS or committed to git."
  type        = string
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH into the public EC2. Leave null to auto-detect the current global IP (as a /32) via checkip.amazonaws.com at plan/apply time."
  type        = string
  default     = null
}

variable "enable_ssm_vpc_endpoints" {
  description = "Creates SSM/EC2Messages/SSMMessages VPC interface endpoints so the private EC2 can be reached via Session Manager without a NAT Gateway. Each endpoint has an hourly + per-GB cost - leave false until Phase 1 verification 5 is explicitly approved."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention for VPC Flow Logs."
  type        = number
  default     = 14
}
