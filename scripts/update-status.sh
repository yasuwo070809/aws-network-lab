#!/usr/bin/env bash
# Read-only status check for aws-network-lab. Makes NO changes to AWS
# resources - only describe-*/get-*/list-* calls and a GET to the public
# web server. Dynamic IDs/IPs are read from `terraform output -raw`; if
# Phase 1 is not currently deployed (empty state), this is reported
# explicitly rather than treated as an error. No jq dependency.
#
# Usage: ./scripts/update-status.sh
# Output: evidence/current-status.txt (overwritten each run)

set -uo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$LAB_ROOT/terraform"
OUT_FILE="$LAB_ROOT/evidence/current-status.txt"
AWS_PROFILE="${AWS_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-ap-northeast-1}"
LOG_GROUP="/aws-network-lab/aws-network-lab/vpc-flow-logs"

mkdir -p "$(dirname "$OUT_FILE")"

tf_out() {
  # tf_out <output_name> - prints the value, or empty string if unavailable.
  (cd "$TF_DIR" && terraform output -raw "$1" 2>/dev/null) || true
}

{
echo "# aws-network-lab current status"
echo "# captured (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# read-only check - no AWS resources were changed by this script"
echo

VPC_ID="$(tf_out vpc_id)"

if [[ -z "$VPC_ID" ]]; then
  echo "## Deployment status: NOT DEPLOYED"
  echo "terraform output returned no vpc_id - Phase 1 infrastructure is not"
  echo "currently applied (terraform.tfstate has 0 resources, or no state)."
  echo "Run 'terraform apply' under terraform/ to redeploy before re-running"
  echo "this script for a live check."
  echo
  echo "## Last known resource IDs (for reference only, NOT re-verified here)"
  echo "See docs/resource-inventory.md for the last-deployment snapshot."
else
  PUB_ID="$(tf_out public_instance_id)"
  PRIV_ID="$(tf_out private_instance_id)"
  EIP="$(tf_out public_eip)"
  PUB_SUBNET="$(tf_out public_subnet_id)"

  echo "## Deployment status: DEPLOYED (vpc_id=$VPC_ID)"
  echo

  echo "## EC2 running state"
  aws ec2 describe-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$PUB_ID" "$PRIV_ID" \
    --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name}" \
    --output table 2>&1
  echo

  echo "## EC2 status checks (system/instance reachability)"
  aws ec2 describe-instance-status --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --instance-ids "$PUB_ID" "$PRIV_ID" \
    --query "InstanceStatuses[].{Id:InstanceId,SystemStatus:SystemStatus.Status,InstanceStatus:InstanceStatus.Status}" \
    --output table 2>&1
  echo

  echo "## VPC Endpoints (state)"
  aws ec2 describe-vpc-endpoints --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "VpcEndpoints[].{Id:VpcEndpointId,Service:ServiceName,State:State}" \
    --output table 2>&1
  echo

  echo "## VPC Flow Logs (status)"
  aws ec2 describe-flow-logs --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --filter "Name=resource-id,Values=$VPC_ID" \
    --query "FlowLogs[].{Id:FlowLogId,Status:FlowLogStatus,Dest:LogDestination}" \
    --output table 2>&1
  echo

  echo "## CloudWatch Log Group"
  aws logs describe-log-groups --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --log-group-name-prefix "$LOG_GROUP" \
    --query "logGroups[].{Name:logGroupName,RetentionDays:retentionInDays}" \
    --output table 2>&1
  echo

  echo "## Public EC2 HTTP response"
  if [[ -n "$EIP" ]]; then
    curl -sS -o /dev/null -w "http_status=%{http_code} time_total=%{time_total}s\n" --max-time 8 "http://$EIP/" 2>&1
  else
    echo "no public_eip in terraform output"
  fi
  echo

  echo "## Public route table: default route present?"
  if [[ -n "$PUB_SUBNET" ]]; then
    aws ec2 describe-route-tables --profile "$AWS_PROFILE" --region "$AWS_REGION" \
      --filters "Name=association.subnet-id,Values=$PUB_SUBNET" \
      --query "RouteTables[].Routes[?DestinationCidrBlock=='0.0.0.0/0']" \
      --output table 2>&1
  else
    echo "no public_subnet_id in terraform output"
  fi
fi
} > "$OUT_FILE" 2>&1

echo "status written to: $OUT_FILE"
