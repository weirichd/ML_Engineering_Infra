#!/usr/bin/env bash
set -euo pipefail

# Defaults (override via flags or env)
REGION="${AWS_REGION:-us-east-2}"
STACK="${STACK_NAME:-mlflow-sqlite}"
TEMPLATE="${TEMPLATE_FILE:-cloudformation/mlflow-sqlite.yaml}"
KEYPAIR="${EC2_KEYPAIR_NAME:-}"
CIDR="${SSH_CIDR:-auto}"
IMAGE="${DOCKER_IMAGE:-ghcr.io/weirichd/mlflow-server:latest}"
RECREATE="false"

usage() {
  cat <<EOF
Usage: $0 [--region us-east-2] [--stack mlflow-sqlite] [--template path.yaml] \\
          --keypair <ec2-keypair-name> --cidr <x.x.x.x/32> [--image <ghcr image>] [--recreate]
Env vars also supported: AWS_REGION, EC2_KEYPAIR_NAME, SSH_CIDR, DOCKER_IMAGE, STACK_NAME, TEMPLATE_FILE
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)   REGION="$2"; shift 2 ;;
    --stack)    STACK="$2"; shift 2 ;;
    --template) TEMPLATE="$2"; shift 2 ;;
    --keypair)  KEYPAIR="$2"; shift 2 ;;
    --cidr)     CIDR="$2"; shift 2 ;;
    --image)    IMAGE="$2"; shift 2 ;;
    --recreate) RECREATE="true"; shift 1 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

[[ -n "$KEYPAIR" ]] || { echo "Missing --keypair or EC2_KEYPAIR_NAME"; exit 1; }

export AWS_DEFAULT_REGION="$REGION"
export AWS_REGION="$REGION"

echo "Region: $REGION"
echo "Stack : $STACK"
echo "Image : $IMAGE"
echo "Tpl   : $TEMPLATE"

# Optionally recreate the stack (useful after user-data changes)
if [[ "$RECREATE" == "true" ]]; then
  if aws cloudformation describe-stacks --stack-name "$STACK" >/dev/null 2>&1; then
    echo "Deleting stack $STACK ..."
    aws cloudformation delete-stack --stack-name "$STACK"
    aws cloudformation wait stack-delete-complete --stack-name "$STACK"
    echo "Deleted."
  fi
fi

# Resolve CIDR if 'auto'
if [[ "$CIDR" == "auto" || -z "$CIDR" ]]; then
  # Try a couple of services; fall back to DNS
  PUBIP=$(curl -fsS https://checkip.amazonaws.com \
        || curl -fsS https://api.ipify.org \
        || dig +short myip.opendns.com @resolver1.opendns.com \
        || true)
  PUBIP=$(echo "$PUBIP" | tr -d '[:space:]')
  if [[ "$PUBIP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    CIDR="${PUBIP}/32"
    echo "Auto-detected SSH_CIDR=${CIDR}"
  else
    echo "Could not auto-detect a public IPv4 address. Please pass --cidr x.x.x.x/32" >&2
    exit 1
  fi
fi


# Discover default VPC + a default subnet
VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=${VPC_ID} Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)
if [[ -z "$SUBNET_ID" || "$SUBNET_ID" == "None" ]]; then
  SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} --query 'Subnets[0].SubnetId' --output text)
fi
[[ -n "$VPC_ID"     && "$VPC_ID"     != "None" ]] || { echo "Could not resolve default VPC"; exit 1; }
[[ -n "$SUBNET_ID"  && "$SUBNET_ID"  != "None" ]] || { echo "Could not resolve default Subnet"; exit 1; }

# Resolve latest Ubuntu 22.04 (Jammy) x86_64 AMI from Canonical
UBUNTU_AMI=$(aws ec2 describe-images --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            "Name=state,Values=available" \
            "Name=virtualization-type,Values=hvm" \
            "Name=architecture,Values=x86_64" \
  --query 'reverse(sort_by(Images, &CreationDate))[0].ImageId' --output text)
[[ -n "$UBUNTU_AMI" && "$UBUNTU_AMI" != "None" ]] || { echo "Failed to resolve Ubuntu AMI"; exit 1; }

echo "VPC_ID=$VPC_ID"
echo "SUBNET_ID=$SUBNET_ID"
echo "UBUNTU_AMI=$UBUNTU_AMI"

# Deploy (or update) the stack
aws cloudformation deploy \
  --template-file "$TEMPLATE" \
  --stack-name "$STACK" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    Env=prod \
    KeyPairName="$KEYPAIR" \
    SSHCidr="$CIDR" \
    DockerImage="$IMAGE" \
    VpcId="$VPC_ID" \
    SubnetId="$SUBNET_ID" \
    UbuntuAmiId="$UBUNTU_AMI"

# Show outputs
aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs" --output table

