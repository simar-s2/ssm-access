#!/usr/bin/env bash
# Deploy cloudformation/ssm-access.yaml: one stack per region, home region
# first because it creates the IAM role, instance profile and operator policy.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/deploy.sh --regions LIST [options]

  -r, --regions LIST     comma-separated regions; the first creates the IAM resources
  -p, --profile NAME     AWS CLI profile
      --name NAME        stack name (default: ssm-access)
      --param KEY=VALUE  template parameter, repeatable
                         (e.g. --param EnableDefaultHostManagement=true)
  -h, --help
USAGE
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REGIONS="" PROFILE="" NAME=ssm-access PARAMS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -r|--regions) REGIONS="${2:?}"; shift ;;
    -p|--profile) PROFILE="${2:?}"; shift ;;
    --name) NAME="${2:?}"; shift ;;
    --param) PARAMS+=("${2:?}"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ -n "$REGIONS" ] || { usage >&2; exit 2; }

aws_() {
  if [ -n "$PROFILE" ]; then aws --profile "$PROFILE" "$@"; else aws "$@"; fi
}

IFS=',' read -r -a REGION_LIST <<<"$REGIONS"
PARAMS=("HomeRegion=${REGION_LIST[0]}" ${PARAMS[@]+"${PARAMS[@]}"})

for REGION in "${REGION_LIST[@]}"; do
  echo "== stack $NAME in $REGION"
  aws_ cloudformation deploy --region "$REGION" --stack-name "$NAME" \
    --template-file "$ROOT/cloudformation/ssm-access.yaml" --capabilities CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset --parameter-overrides "${PARAMS[@]}"
done

echo
echo "Attach the operator policy to the people who connect:"
aws_ cloudformation describe-stacks --region "${REGION_LIST[0]}" --stack-name "$NAME" \
  --query "Stacks[0].Outputs[?OutputKey=='OperatorPolicyArn'].OutputValue" --output text
