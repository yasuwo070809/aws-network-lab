output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "public_eip" {
  description = "Elastic IP of the public EC2 - use this to SSH/curl."
  value       = aws_eip.public.public_ip
}

output "public_instance_id" {
  value = aws_instance.public.id
}

output "public_instance_private_ip" {
  value = aws_instance.public.private_ip
}

output "private_instance_id" {
  value = aws_instance.private.id
}

output "private_instance_private_ip" {
  value = aws_instance.private.private_ip
}

output "ssh_ingress_cidr_in_use" {
  description = "The CIDR actually applied to the SSH ingress rule (auto-detected or overridden)."
  value       = local.ssh_ingress_cidr
}

output "ssh_to_public" {
  value = "ssh -i <your-private-key> ec2-user@${aws_eip.public.public_ip}"
}

output "ssh_to_private_via_proxyjump" {
  description = "ProxyJump through the public EC2 via an explicit ProxyCommand (some OpenSSH builds don't forward -i to the implicit -J proxy hop). The private key stays on the operator's machine, never copied to the bastion."
  value       = "ssh -i <your-private-key> -o ProxyCommand=\"ssh -i <your-private-key> -W %h:%p ec2-user@${aws_eip.public.public_ip}\" ec2-user@${aws_instance.private.private_ip}"
}

output "ssm_start_session_private" {
  value = "aws ssm start-session --target ${aws_instance.private.id} --profile ${var.aws_profile} --region ${var.aws_region}"
}
