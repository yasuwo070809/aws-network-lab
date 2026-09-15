#!/usr/bin/env bash
# Fault injection 2: NACL-level failure on the public subnet.
#
#   --mode http       deny INBOUND tcp/80 (looks similar to an SG deny from
#                      curl's point of view - used for the SG-vs-NACL comparison)
#   --mode ephemeral  (default) deny OUTBOUND to the client's ephemeral port
#                      range (1024-65535). Inbound port 80 stays allowed, so
#                      the SYN gets through and the server sends a reply, but
#                      the reply is dropped by the NACL because NACLs are
#                      stateless and evaluate the return leg as its own flow.
#
# Adds a single low-numbered DENY rule (evaluated before the existing
# allow-all rule 100) rather than replacing the NACL, so restore.sh only has
# to delete that one rule.

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/collect-evidence.sh"

MODE="${1:-ephemeral}"
EIP="$(get_tf_output public_eip)"
NACL_ID="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=association.subnet-id,Values=$(get_tf_output public_subnet_id)" \
    --query "NetworkAcls[0].NetworkAclId" --output text)"

echo "Mode: $MODE"
echo "Target NACL: $NACL_ID (public subnet, aws-network-lab)"
case "$MODE" in
  http)
    echo "Will add rule 90: DENY inbound tcp/80 from 0.0.0.0/0"
    ;;
  ephemeral)
    echo "Will add rule 90: DENY outbound tcp/1024-65535 to 0.0.0.0/0 (blocks the HTTP response's return leg)"
    ;;
  *) echo "usage: $0 [http|ephemeral]"; exit 1 ;;
esac
read -r -p "Type YES to proceed: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "aborted"; exit 1; }

echo "-- before: curl (expect 200) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 5 "http://$EIP/" || true)"
echo "$OUT"
evi_save "03-nacl" "before-${MODE}-deny.txt" "$OUT"

if [[ "$MODE" == "http" ]]; then
  aws ec2 create-network-acl-entry --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --network-acl-id "$NACL_ID" --rule-number 90 --protocol tcp \
    --port-range From=80,To=80 --cidr-block 0.0.0.0/0 --rule-action deny --ingress
else
  aws ec2 create-network-acl-entry --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --network-acl-id "$NACL_ID" --rule-number 90 --protocol tcp \
    --port-range From=1024,To=65535 --cidr-block 0.0.0.0/0 --rule-action deny --egress
fi

echo "-- after: curl (expect timeout) --"
OUT="$(curl -sS -o /dev/null -w "http_status=%{http_code}\n" --max-time 8 "http://$EIP/" 2>&1 || true)"
echo "$OUT"
evi_save "03-nacl" "after-${MODE}-deny.txt" "$OUT"

echo "-- current NACL rules --"
OUT="$(aws ec2 describe-network-acls --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --network-acl-ids "$NACL_ID" --output table)"
evi_save "03-nacl" "rules-after-${MODE}-deny.txt" "$OUT"

echo "FAULT INJECTED: NACL $NACL_ID rule 90 ($MODE) added."
echo "Run scripts/restore.sh to remove it."
