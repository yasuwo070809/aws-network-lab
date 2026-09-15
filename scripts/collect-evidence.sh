#!/usr/bin/env bash
# Shared evidence-collection helpers for aws-network-lab.
#
# Used two ways:
#   1. sourced by the other scripts in this directory for its helper functions
#      (get_tf_output, ts, evi_save, ssh_public, ssh_private)
#   2. run directly to capture a full baseline evidence sweep (verifications 1-3)
#      into evidence/01-public-ec2, evidence/02-security-group, evidence/03-nacl
#
# Never prints/saves AWS credentials, the SSH private key, or the AWS account ID.

set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$LAB_ROOT/terraform"
EVIDENCE_DIR="$LAB_ROOT/evidence"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/aws-network-lab}"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

get_tf_output() {
  # get_tf_output <output_name>
  (cd "$TF_DIR" && terraform output -raw "$1")
}

# The AWS account ID must never end up in a committed evidence file (see
# project requirement: no account IDs/credentials in deliverables). Resolved
# once per script run via STS - never hardcoded anywhere in this repo.
_ACCOUNT_ID=""
get_account_id() {
  if [[ -z "$_ACCOUNT_ID" ]]; then
    _ACCOUNT_ID="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" --query Account --output text 2>/dev/null || true)"
  fi
  printf '%s' "$_ACCOUNT_ID"
}

redact() {
  # redact <text> - strips the current AWS account ID out of ARNs/output.
  local text="$1" acct
  acct="$(get_account_id)"
  if [[ -n "$acct" ]]; then
    printf '%s' "${text//$acct/<ACCOUNT_ID>}"
  else
    printf '%s' "$text"
  fi
}

evi_save() {
  # evi_save <phase-dir> <filename> <content-as-arg>
  # Takes content as a positional argument (from a command-substitution
  # capture, not a live pipe) - SSH/curl output is fully captured first, so
  # there's no dependency on a subprocess's stdout fd closing cleanly.
  # Account ID is redacted before writing - see redact() above.
  local phase="$1" file="$2" content="$3"
  local dir="$EVIDENCE_DIR/$phase"
  mkdir -p "$dir"
  { echo "# captured $(ts)"; printf '%s\n' "$(redact "$content")"; } > "$dir/$file"
  echo "saved: $dir/$file"
}

ssh_public() {
  # ssh_public <remote-command...>
  local eip
  eip="$(get_tf_output public_eip)"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 "ec2-user@$eip" "$@"
}

ssh_private_via_proxyjump() {
  # ssh_private_via_proxyjump <remote-command...>
  # ProxyJump through the public EC2. The private key is used locally by the
  # operator's ssh client for BOTH hops; it is never copied onto the bastion.
  #
  # Explicit -o ProxyCommand (rather than -J) so the identity file is passed
  # to the jump-hop ssh subprocess too - plain `-i ... -J host2 host2-priv`
  # spawns an implicit proxy ssh that does NOT inherit -i on some OpenSSH
  # builds, which surfaces as "Permission denied" on the BASTION hop even
  # though the same key works for a direct SSH to that same bastion.
  local eip priv_ip
  eip="$(get_tf_output public_eip)"
  priv_ip="$(get_tf_output private_instance_private_ip)"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
      -o "ProxyCommand=ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new -W %h:%p ec2-user@$eip" \
      "ec2-user@$priv_ip" "$@"
}

# --- run-directly mode: baseline evidence sweep --------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "== aws-network-lab: baseline evidence sweep =="
  EIP="$(get_tf_output public_eip)"

  echo "--- 01-public-ec2: HTTP ---"
  OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code} time_total=%{time_total}s\n" "http://$EIP/" || true)"
  evi_save "01-public-ec2" "http-curl.txt" "$OUT"

  echo "--- 01-public-ec2: SSH banner ---"
  OUT="$(timeout 8 bash -c "exec 3<>/dev/tcp/$EIP/22; head -c 64 <&3" 2>&1 || true)"
  evi_save "01-public-ec2" "ssh-banner.txt" "$OUT"

  echo "--- 01-public-ec2: internal IP / routing table (via SSH) ---"
  OUT="$(ssh_public "hostname; echo; ip -4 addr show; echo; ip route" 2>&1 || true)"
  evi_save "01-public-ec2" "ip-and-route.txt" "$OUT"

  echo "--- 02-security-group: SG rules ---"
  SG_ID="$(cd "$TF_DIR" && terraform state show aws_security_group.public | grep -m1 '^ *id ' | awk '{print $3}' | tr -d '"')"
  OUT="$(aws ec2 describe-security-group-rules --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --filters "Name=group-id,Values=$SG_ID" --output table 2>&1 || true)"
  evi_save "02-security-group" "sg-rules.txt" "$OUT"

  echo "--- 03-nacl: NACL rules (public) ---"
  NACL_ID="$(cd "$TF_DIR" && terraform output -raw public_subnet_id | xargs -I{} aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" --filters "Name=association.subnet-id,Values={}" --query "NetworkAcls[0].NetworkAclId" --output text)"
  OUT="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --network-acl-ids "$NACL_ID" --output table 2>&1 || true)"
  evi_save "03-nacl" "nacl-rules.txt" "$OUT"

  echo "== done =="
fi
