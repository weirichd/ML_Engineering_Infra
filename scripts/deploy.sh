#!/usr/bin/env bash
set -euo pipefail

# --- helper: colored output ---
c_ok()   { printf "\033[32m%s\033[0m\n" "$*"; }
c_err()  { printf "\033[31m%s\033[0m\n" "$*" >&2; }
c_info() { printf "\033[36m%s\033[0m\n" "$*"; }

# --- load .env ---
ENV_FILE="${ENV_FILE:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  c_err "Missing $ENV_FILE. Copy .env.example to .env and fill in values."
  exit 1
fi
# shellcheck disable=SC2046
export $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" | xargs)

# --- required vars ---
: "${STACK_NAME:?Set STACK_NAME in .env}"
: "${REGION:?Set REGION in .env}"
: "${SUFFIX:?Set SUFFIX in .env}"
: "${TEMPLATE:?Set TEMPLATE in .env}"

AWS_ARGS=(--region "$REGION")
if [[ -n "${AWS_PROFILE:-}" ]]; then
  AWS_ARGS+=(--profile "$AWS_PROFILE")
fi

# --- preflight checks ---
command -v aws >/dev/null 2>&1 || { c_err "aws CLI not found. Install & configure it."; exit 2; }
[[ -f "$TEMPLATE" ]] || { c_err "Template not found: $TEMPLATE"; exit 2; }

c_info "Deploying stack: $STACK_NAME (region: $REGION, suffix: $SUFFIX)"
set +e
DEPLOY_OUT=$(aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --parameter-overrides StackSuffix="$SUFFIX" \
  --capabilities CAPABILITY_NAMED_IAM \
  "${AWS_ARGS[@]}" 2>&1)
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  c_err "Deployment failed."
  echo "---- aws cli output ----"
  echo "$DEPLOY_OUT"
  echo "------------------------"
  c_info "Fetching recent stack events for clues…"
  # If stack exists, print last few failure events
  set +e
  aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" "${AWS_ARGS[@]}" \
    --query "StackEvents[?ResourceStatus=='CREATE_FAILED'||ResourceStatus=='UPDATE_FAILED'].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]" \
    --output table 2>/dev/null || true
  set -e
  exit $STATUS
fi

# --- success: show outputs ---
c_ok "Deployment succeeded."
c_info "Stack outputs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" "${AWS_ARGS[@]}" \
  --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" \
  --output table

