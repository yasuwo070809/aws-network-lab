#!/usr/bin/env bash
# aws-network-lab verification runner (verifications 1-4).
# Read-only against AWS: issues curl/ssh/aws-describe-* calls only, makes no changes.
#
# Usage: ./scripts/verify.sh [1|2|3|4|all]

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/collect-evidence.sh"

verify_1_public_ec2() {
  echo "== Verification 1: Public EC2 =="
  local eip priv_ip out
  eip="$(get_tf_output public_eip)"
  priv_ip="$(get_tf_output public_instance_private_ip)"
  echo "Elastic IP: $eip / Private IP: $priv_ip"

  echo "-- HTTP --"
  out="$(curl -sS -i "http://$eip/")"
  echo "$out"
  evi_save "01-public-ec2" "http-response.txt" "$out"

  echo "-- SSH reachability (banner only, no login) --"
  out="$(timeout 8 bash -c "exec 3<>/dev/tcp/$eip/22; head -c 64 <&3" 2>&1 || true)"
  echo "$out"
  evi_save "01-public-ec2" "ssh-banner.txt" "$out"

  echo "-- internal IP / route table (requires SSH key) --"
  out="$(ssh_public "echo '--- hostname ---'; hostname; echo '--- ip addr ---'; ip -4 addr show; echo '--- ip route ---'; ip route")"
  echo "$out"
  evi_save "01-public-ec2" "ip-and-route.txt" "$out"
}

verify_2_security_group() {
  echo "== Verification 2: Security Group (stateful) =="
  local eip sg_id out
  eip="$(get_tf_output public_eip)"

  echo "-- current SG rules --"
  sg_id="$(cd "$TF_DIR" && terraform state show aws_security_group.public | awk -F'"' '/^ *id +=/{print $2; exit}')"
  out="$(aws ec2 describe-security-group-rules --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --filters "Name=group-id,Values=$sg_id" --output table)"
  echo "$out"
  evi_save "02-security-group" "sg-rules-current.txt" "$out"

  echo "-- HTTP with rule present (expect 200) --"
  out="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" "http://$eip/")"
  echo "$out"
  evi_save "02-security-group" "http-allowed.txt" "$out"

  echo "-- statefulness note --"
  out="(the SG only has one inbound rule for port 80; the response traffic back to the client is allowed automatically because Security Groups are stateful)"
  evi_save "02-security-group" "stateful-note.txt" "$out"
}

verify_3_nacl() {
  echo "== Verification 3: NACL (stateless) =="
  local nacl_id out
  nacl_id="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --filters "Name=association.subnet-id,Values=$(get_tf_output public_subnet_id)" \
      --query "NetworkAcls[0].NetworkAclId" --output text)"
  out="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --network-acl-ids "$nacl_id" --output table)"
  echo "$out"
  evi_save "03-nacl" "nacl-rules-current.txt" "$out"

  echo "-- ephemeral port note --"
  out='NACLs are stateless: a reply to an outbound (or inbound) request is only
allowed if a rule explicitly permits it in the OPPOSITE direction too.
For a client on the internet -> public EC2:80 request, the servers reply
goes out from port 80 to the clients ephemeral source port (Linux default
range 32768-60999, see /proc/sys/net/ipv4/ip_local_port_range on the EC2).
The current NACL uses "allow all" rules (protocol -1) so this is not
observable yet - it becomes observable once the NACL fault-injection test
(scripts/inject-nacl-failure.sh) narrows the rules to specific ports.'
  evi_save "03-nacl" "ephemeral-port-note.txt" "$out"
}

verify_4_private_ec2() {
  echo "== Verification 4: Private EC2 (bastion via ProxyJump) =="
  local priv_ip priv_id out
  priv_ip="$(get_tf_output private_instance_private_ip)"
  echo "Private EC2 private IP: $priv_ip (no public IP by design)"

  echo "-- confirm no public IP via EC2 API (not via login) --"
  priv_id="$(get_tf_output private_instance_id)"
  out="$(aws ec2 describe-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --instance-ids "$priv_id" \
      --query "Reservations[0].Instances[0].{PublicIpAddress:PublicIpAddress,PrivateIpAddress:PrivateIpAddress}" \
      --output table)"
  echo "$out"
  evi_save "04-private-ec2" "no-public-ip.txt" "$out"

  echo "-- ProxyJump through the public EC2 (private key used locally only, never copied to the bastion) --"
  out="$(ssh_private_via_proxyjump "echo '--- hostname ---'; hostname; echo '--- ip addr ---'; ip -4 addr show")"
  echo "$out"
  evi_save "04-private-ec2" "proxyjump-session.txt" "$out"
}

case "${1:-all}" in
  1) verify_1_public_ec2 ;;
  2) verify_2_security_group ;;
  3) verify_3_nacl ;;
  4) verify_4_private_ec2 ;;
  all)
    verify_1_public_ec2
    verify_2_security_group
    verify_3_nacl
    verify_4_private_ec2
    ;;
  *) echo "usage: $0 [1|2|3|4|all]"; exit 1 ;;
esac
