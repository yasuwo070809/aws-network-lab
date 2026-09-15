#!/usr/bin/env bash
# Restores normal state after any of the inject-*-failure.sh scripts.
#
#  - SG rule (HTTP ingress) and the route table's default route are both
#    Terraform-managed resources, so `terraform apply` reconciles them back
#    on its own once the out-of-band aws-cli change is detected as drift.
#  - The NACL deny rule (rule 90) was added directly via aws-cli and is NOT
#    a Terraform resource, so it has to be deleted directly here first.
#
# `terraform apply` still prompts for its own yes/no confirmation - this
# script does not auto-approve it.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/collect-evidence.sh"

EIP="$(get_tf_output public_eip)"
NACL_ID="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=association.subnet-id,Values=$(get_tf_output public_subnet_id)" \
    --query "NetworkAcls[0].NetworkAclId" --output text)"

echo "== 1/3: removing any injected NACL rule 90 (ingress/egress) on $NACL_ID =="
aws ec2 delete-network-acl-entry --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --network-acl-id "$NACL_ID" --rule-number 90 --ingress 2>/dev/null && echo "removed ingress rule 90" || echo "no ingress rule 90 to remove"
aws ec2 delete-network-acl-entry --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --network-acl-id "$NACL_ID" --rule-number 90 --egress 2>/dev/null && echo "removed egress rule 90" || echo "no egress rule 90 to remove"

echo
echo "== 2/3: reconciling Terraform-managed resources (SG rule, default route) =="
echo "The plan below should show only drift-repair (re-adding the HTTP SG rule"
echo "and/or the 0.0.0.0/0 route if they were removed by an injection script)."
(cd "$TF_DIR" && terraform plan -out=/tmp/aws-network-lab-restore.tfplan && terraform apply /tmp/aws-network-lab-restore.tfplan)

echo
echo "== 3/3: verifying normal state =="
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 8 "http://$EIP/" || true)"
echo "$OUT"
evi_save "02-security-group" "restored-http.txt" "$OUT"

echo "restore complete."
