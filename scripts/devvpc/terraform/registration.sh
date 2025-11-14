#!/bin/bash
TARGET_GROUP_ARN="arn:aws:elasticloadbalancing:us-east-1:200008295591:targetgroup/sandbox-vpc-alb2nginx-https/2c41b71a357cd168" #update this with your target group ARN
PORT=30080
REGION="us-east-1"

# Get EKS node IPs
NODE_IPS=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')

# Register each IP
for IP in $NODE_IPS; do
  aws elbv2 register-targets \
    --target-group-arn $TARGET_GROUP_ARN \
    --targets Id=$IP,Port=$PORT \
    --region $REGION
done