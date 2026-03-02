#!/usr/bin/bash -x

# karpenterinstall.sh(or {$0}) \"${var.karpenterchartversion}\" \"${module.eks.cluster_name}\" \"${var.awsaccountid}\" \"${module.eks.cluster_enpoint}\" \"${module.eks.oidc_provider_arn}\"

export karpenterchartversion="${1}"
export eksclustername="${2}"
export awsaccountid="${3}"

aws eks describe-cluster --name ${eksclustername} --query "cluster.endpoint" --output text
export CLUSTER_ENDPOINT="${4}"
export KARPENTER_IAM_ROLE_ARN="${5}"
aws eks --region us-east-1 update-kubeconfig --name ${eksclustername}


docker logout public.ecr.aws
helm version
helm registry logout public.ecr.aws
echo "Sleeping for 600 seconds to allow cluster to settle down and be ready for karpenter install"
sleep 600
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version ${karpenterchartversion} --namespace kube-system \
  --set settings.clusterName=${eksclustername} \
  --set settings.interruptionQueueName=${eksclustername} \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait --debug | tee karpenterinstall.log

exit

#helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version ${karpenterchartversion} --namespace kube-system \
#  --set settings.clusterName=${eksclustername} \
#  --set settings.aws.clusterEndpoint=${CLUSTER_ENDPOINT} \
#  --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-${eksclustername} \
#  --set settings.interruptionQueueName=${eksclustername} \
#  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${KARPENTER_IAM_ROLE_ARN} \
#  --wait --debug | tee karpenterinstall.log


helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.0.0 --namespace kube-system --set settings.clusterName=cnxsdev-karpenter --set settings.interruptionQueueName=cnxsdev-karpenter --set controller.resources.requests.cpu=1 --set controller.resources.requests.memory=1Gi --set controller.resources.limits.cpu=1 --set controller.resources.limits.memory=1Gi --wait --debug

