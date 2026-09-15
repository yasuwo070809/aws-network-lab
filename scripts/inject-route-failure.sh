#!/usr/bin/env bash
# Fault injection 3: delete the public route table's default route
# (0.0.0.0/0 -> IGW). The instance itself is untouched - only the route table
# entry is removed - so this is the "route missing" failure mode as distinct
# from an SG or NACL deny.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/collect-evidence.sh"

EIP="$(get_tf_output public_eip)"
RTB_ID="$(cd "$TF_DIR" && terraform state show aws_route_table.public | awk -F'"' '/^ *id +=/{print $2; exit}')"

echo "This will DELETE the 0.0.0.0/0 route from route table $RTB_ID (public, aws-network-lab)."
echo "Target EIP under test: $EIP"
read -r -p "Type YES to proceed: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "aborted"; exit 1; }

echo "-- before: curl (expect 200) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 5 "http://$EIP/" || true)"
echo "$OUT"
evi_save "06-flow-logs" "before-route-delete.txt" "$OUT"

echo "-- deleting default route --"
aws ec2 delete-route --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --route-table-id "$RTB_ID" --destination-cidr-block 0.0.0.0/0

echo "-- after: curl (expect timeout - no route to host from the client's perspective) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 8 "http://$EIP/" 2>&1 || true)"
echo "$OUT"
evi_save "06-flow-logs" "after-route-delete.txt" "$OUT"

echo "-- current route table --"
OUT="$(aws ec2 describe-route-tables --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --route-table-ids "$RTB_ID" --output table)"
evi_save "06-flow-logs" "route-table-after-delete.txt" "$OUT"

echo "FAULT INJECTED: default route removed from $RTB_ID."
echo "Run scripts/restore.sh to add it back."
