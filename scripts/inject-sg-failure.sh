#!/usr/bin/env bash
# Fault injection 1: remove the HTTP ingress rule from the public EC2's
# Security Group. Captures curl behavior before/after, then leaves the SG in
# the FAILED state (SSH still works, since only the HTTP rule is removed).
# Run scripts/restore.sh afterwards to put the HTTP rule back.
#
# This script makes a real AWS change. It requires typed confirmation and is
# only meant to be run after the operator has approved it in the session.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/collect-evidence.sh"

EIP="$(get_tf_output public_eip)"
SG_ID="$(cd "$TF_DIR" && terraform state show aws_security_group.public | awk -F'"' '/^ *id +=/{print $2; exit}')"

echo "This will REVOKE the HTTP (tcp/80 from 0.0.0.0/0) ingress rule on SG $SG_ID."
echo "Target: aws-network-lab public EC2 ($EIP). SSH ingress is left untouched."
read -r -p "Type YES to proceed: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "aborted"; exit 1; }

echo "-- before: curl (expect 200) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 5 "http://$EIP/" || true)"
echo "$OUT"
evi_save "02-security-group" "before-revoke-http.txt" "$OUT"

echo "-- revoking HTTP ingress rule --"
aws ec2 revoke-security-group-ingress --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "-- after: curl (expect timeout / connection refused-equivalent) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 8 "http://$EIP/" 2>&1 || true)"
echo "$OUT"
evi_save "02-security-group" "after-revoke-http.txt" "$OUT"

echo "-- after: SSH still works (SG is stateful per-rule, unrelated rule removal doesn't affect SSH) --"
OUT="$(timeout 8 bash -c "exec 3<>/dev/tcp/$EIP/22; head -c 64 <&3" 2>&1 || true)"
echo "$OUT"
evi_save "02-security-group" "after-revoke-ssh-still-ok.txt" "$OUT"

echo "FAULT INJECTED: HTTP ingress rule removed from $SG_ID."
echo "Run scripts/restore.sh to restore the normal state."
