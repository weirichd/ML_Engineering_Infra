#!/usr/bin/env bash
# Minimal deploy script (old-style) for the ML Eng Course stack.
# Usage:
#   scripts/deploy.sh deploy     # create/update the stack
#   scripts/deploy.sh outputs    # print outputs
#   scripts/deploy.sh events     # recent failed events (debug)
#   scripts/deploy.sh delete     # delete the stack

set -euo pipefail
ACTION="${1:-deploy}"

# --- load .env (lean style) ---
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${ROOT_DIR}/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE (copy .env.example -> .env and edit)." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# Required
: "${STACK_NAME:?Set STACK_NAME in .env}"
: "${REGION:?Set REGION in .env}"
: "${SUFFIX:?Set SUFFIX in .env}"
: "${TEMPLATE:?Set TEMPLATE in .env}"

# Optional / EC2-related (only used if TrainingInstance exists in template)
KEY_NAME="${KEY_NAME:-}"                  # EC2 keypair name
VPC_ID="${VPC_ID:-}"                      # if empty, auto-resolve default VPC
SUBNET_ID="${SUBNET_ID:-}"                # if empty, auto-resolve default subnet in that VPC
ALLOWED_CIDR="${ALLOWED_CIDR:-0.0.0.0/0}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
IMAGE_ID="${IMAGE_ID:-}"                  # if empty, auto-resolve AL2023 AMI (x86_64)
AWS_PROFILE="${AWS_PROFILE:-}"

AWS_ARGS=(--region "$REGION")
[[ -n "$AWS_PROFILE" ]] && AWS_ARGS+=(--profile "$AWS_PROFILE")

# --- helpers ---
ok()  { printf "\033[32m%s\033[0m\n" "$*"; }
err() { printf "\033[31m%s\033[0m\n" "$*" >&2; }
info(){ printf "\033[36m%s\033[0m\n" "$*"; }

stack_outputs() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" "${AWS_ARGS[@]}" \
    --query "Stacks[0].Outputs[].[OutputKey,OutputValue]" \
    --output table
}

stack_failed_events() {
  aws cloudformation describe-stack-events \
    --stack-name "$STACK_NAME" "${AWS_ARGS[@]}" \
    --query "StackEvents[?ResourceStatus=='CREATE_FAILED'||ResourceStatus=='UPDATE_FAILED'].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]" \
    --output table || true
}

# --- Build parameter list (always include StackSuffix) ---
PARAMS=( StackSuffix="$SUFFIX" )

# If the template includes TrainingInstance, we expect EC2 params.
# We'll auto-resolve VPC/SUBNET/AMI if not provided, but only proceed if KEY_NAME is set.
if [[ -n "${KEY_NAME}" ]]; then
  # Resolve default VPC + a default subnet (your original approach)
  if [[ -z "${VPC_ID}" || "${VPC_ID}" == "None" ]]; then
    VPC_ID="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text "${AWS_ARGS[@]}")"
  fi
  if [[ -z "${SUBNET_ID}" || "${SUBNET_ID}" == "None" ]]; then
    SUBNET_ID="$(aws ec2 describe-subnets \
      --filters Name=vpc-id,Values=${VPC_ID} Name=default-for-az,Values=true \
      --query 'Subnets[0].SubnetId' --output text "${AWS_ARGS[@]}")" || true
    if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
      SUBNET_ID="$(aws ec2 describe-subnets \
        --filters Name=vpc-id,Values=${VPC_ID} \
        --query 'Subnets[0].SubnetId' --output text "${AWS_ARGS[@]}")"
    fi
  fi
  [[ -n "$VPC_ID"    && "$VPC_ID"    != "None" ]]   || { err "Could not resolve default VPC"; exit 1; }
  [[ -n "$SUBNET_ID" && "$SUBNET_ID" != "None" ]]   || { err "Could not resolve default Subnet"; exit 1; }

  # Resolve a vanilla Amazon Linux 2023 AMI (x86_64), excluding ECS/GPU/minimal variants
  if [[ -z "$IMAGE_ID" ]]; then
    info "Resolving Amazon Linux 2023 AMI (x86_64) in $REGION…"
    set +e
    IMAGE_ID="$(
      aws ec2 describe-images \
        --owners amazon \
        --filters \
          "Name=name,Values=al2023-ami-*-x86_64-*" \
          "Name=state,Values=available" \
          "Name=architecture,Values=x86_64" \
          "Name=virtualization-type,Values=hvm" \
          "Name=root-device-type,Values=ebs" \
        --query "Images
          | sort_by(@,&CreationDate)
          | [?contains(Name, 'ecs')==\`false\`
             && contains(Name, 'gpu')==\`false\`
             && contains(Name, 'minimal')==\`false\`
             && (contains(Name, 'kernel-6.1') || contains(Name, 'k6.1'))]
          | [-1].ImageId" \
        --output text "${AWS_ARGS[@]}" 2>/dev/null
    )"
    # Fallback: any AL2023 x86_64 (still excluding ecs/gpu/minimal), newest first
    if [[ -z "$IMAGE_ID" || "$IMAGE_ID" == "None" ]]; then
      IMAGE_ID="$(
        aws ec2 describe-images \
          --owners amazon \
          --filters \
            "Name=name,Values=*al2023-ami-*" \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
            "Name=virtualization-type,Values=hvm" \
            "Name=root-device-type,Values=ebs" \
          --query "Images
            | sort_by(@,&CreationDate)
            | [?contains(Name, 'ecs')==\`false\`
               && contains(Name, 'gpu')==\`false\`
               && contains(Name, 'minimal')==\`false\`]
            | [-1].ImageId" \
          --output text "${AWS_ARGS[@]}" 2>/dev/null
      )"
    fi
    set -e
    [[ -n "$IMAGE_ID" && "$IMAGE_ID" != "None" ]] || { err "Could not auto-resolve an AL2023 AMI. Set IMAGE_ID in .env and retry."; exit 2; }
    # Print the chosen AMI name for sanity
    AMI_NAME="$(aws ec2 describe-images --image-ids "$IMAGE_ID" "${AWS_ARGS[@]}" --query 'Images[0].Name' --output text || true)"
    info "Using AMI: $IMAGE_ID (${AMI_NAME:-name unavailable})"
  fi

  PARAMS+=(
    KeyName="$KEY_NAME"
    VpcId="$VPC_ID"
    SubnetId="$SUBNET_ID"
    AllowedCidr="$ALLOWED_CIDR"
    InstanceType="$INSTANCE_TYPE"
    ImageId="$IMAGE_ID"
  )
fi

case "$ACTION" in
  deploy)
    info "Deploying stack: $STACK_NAME"
    set +e
    OUT=$(aws cloudformation deploy \
      --stack-name "$STACK_NAME" \
      --template-file "$TEMPLATE" \
      --parameter-overrides "${PARAMS[@]}" \
      --capabilities CAPABILITY_NAMED_IAM \
      "${AWS_ARGS[@]}" 2>&1)
    STATUS=$?
    set -e
    if [[ $STATUS -ne 0 ]]; then
      err "Deployment failed."
      echo "---- aws cli output ----"
      echo "$OUT"
      echo "------------------------"
      info "Recent failure events:"
      stack_failed_events
      exit $STATUS
    fi
    ok "Deployment succeeded."
    info "Stack outputs:"
    stack_outputs
    ;;
  outputs)
    stack_outputs
    ;;
  events)
    stack_failed_events
    ;;
  delete)
    info "Deleting stack: $STACK_NAME"
    aws cloudformation delete-stack --stack-name "$STACK_NAME" "${AWS_ARGS[@]}"
    info "Waiting for delete to complete…"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME" "${AWS_ARGS[@]}"
    ok "Delete complete."
    ;;
  *)
    err "Unknown action: $ACTION"
    echo "Usage: $0 {deploy|outputs|events|delete}"
    exit 1
    ;;
esac

