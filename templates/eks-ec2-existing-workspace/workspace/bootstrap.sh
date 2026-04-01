#!/usr/bin/env bash
# workspace/bootstrap.sh
#
# PURPOSE
# -------
# This script documents the PREREQUISITE steps that must be applied to an
# existing EC2 instance BEFORE it can be connected as a Coder workspace.
# It is NOT run by the Coder Terraform template — it is provided as a
# runbook / manual prep guide that an operator executes once per instance.
#
# The Coder agent itself is delivered via AWS SSM Run Command each time
# a workspace is started (see coder/main.tf → aws_ssm_association).
#
# PREREQUISITES FOR THE TARGET EC2 INSTANCE
# ------------------------------------------
# 1. SSM Agent installed and running.
# 2. An IAM Instance Profile attached with at least:
#    arn:aws-us-gov:iam::aws:policy/AmazonSSMManagedInstanceCore
# 3. Outbound HTTPS (port 443) to the Coder server URL from the EC2.
#    If the VPC has no Internet Gateway, create a VPC Endpoint for SSM:
#      com.amazonaws.us-gov-west-1.ssm
#      com.amazonaws.us-gov-west-1.ssmmessages
#      com.amazonaws.us-gov-west-1.ec2messages
# 4. (Linux) A user named 'coder' (or adjust coder_user variable). Example:
#    sudo useradd -m -s /bin/bash coder
# 5. (Windows) RDP enabled and Windows Firewall rule open on 3389 for localhost.
#
# REQUIRED PROVISIONER-SIDE IAM PERMISSIONS (Coder provisioner pod IRSA)
# -----------------------------------------------------------------------
# The Coder provisioner pod (running on EKS) must have the following
# permissions to create/delete SSM documents and associations:
#
#   ssm:CreateDocument
#   ssm:DeleteDocument
#   ssm:DescribeDocument
#   ssm:GetDocument
#   ssm:UpdateDocument
#   ssm:CreateAssociation
#   ssm:DeleteAssociation
#   ssm:DescribeAssociation
#   ssm:UpdateAssociationStatus
#   ssm:ListAssociations
#   ec2:DescribeInstances
#
# See docs/iam-policies/ for the full IAM policy JSON.
#
# QUICK CHECK — run this from any machine with AWS CLI + correct credentials
# --------------------------------------------------------------------------
set -euo pipefail

INSTANCE_ID="${1:-}"
REGION="${2:-us-gov-west-1}"

if [[ -z "$INSTANCE_ID" ]]; then
  echo "Usage: $0 <instance-id> [region]"
  echo ""
  echo "This script checks whether the target EC2 instance is ready to be"
  echo "connected as a Coder workspace."
  exit 1
fi

echo "==> Checking EC2 instance: $INSTANCE_ID in $REGION"

STATE=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text 2>/dev/null || echo "UNKNOWN")

echo "    Instance state : $STATE"

if [[ "$STATE" != "running" ]]; then
  echo "    [WARN] Instance is not running. Start it before attaching as a Coder workspace."
fi

SSM_STATUS=$(aws ssm describe-instance-information \
  --region "$REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' \
  --output text 2>/dev/null || echo "NotFound")

echo "    SSM ping status: $SSM_STATUS"

if [[ "$SSM_STATUS" != "Online" ]]; then
  cat <<'MSG'

    [FAIL] SSM agent is not online for this instance. Common causes:

    1. SSM agent not installed or not running.
       Amazon Linux 2 / AL2023: pre-installed.
       Ubuntu: sudo snap install amazon-ssm-agent --classic
       Windows Server: https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-install-win.html

    2. No IAM Instance Profile with AmazonSSMManagedInstanceCore attached.
       AWS Console → EC2 → Actions → Security → Modify IAM Role

    3. Missing SSM VPC Endpoints in a private VPC (no IGW):
       Required endpoints:
         com.amazonaws.us-gov-west-1.ssm
         com.amazonaws.us-gov-west-1.ssmmessages
         com.amazonaws.us-gov-west-1.ec2messages

    4. Security group blocks outbound HTTPS (port 443) to AWS SSM endpoints.

MSG
  exit 1
fi

echo ""
echo "==> Instance $INSTANCE_ID is ready to be connected as a Coder workspace."
echo "    Set ec2_instance_id = \"$INSTANCE_ID\" in your Coder template variables."
