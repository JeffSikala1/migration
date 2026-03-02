#!/usr/bin/bash -x

CURRENT_CONTEXT=$(kubectl config current-context)
echo "Uninstall cilium and remove all addons coredns etc.."
echo "You are going to make a fundamental or potentially disruptive change. Current kubernet environment is ${CURRENT_CONTEXT}"
read -p "Do you want to proceed? (y/N): " -n 1 ans

if [[ $ans != [yY] ]]; then
    echo "Aborting..."
    exit;
fi

API_SERVER_IP=$(kubectl cluster-info |grep "control plane" |sed 's/^.*https:\/\/\(.*\)/\1/')
helm uninstall cilium --kube-apiserver https://${API_SERVER_IP}:443 --namespace kube-system

aws eks delete-addon --cluster-name cnxsdev-selfmanaged --addon-name coredns; aws eks delete-addon --cluster-name cnxsdev-selfmanaged --addon-name aws-ebs-csi-driver; aws eks delete-addon --cluster-name cnxsdev-selfmanaged --addon-name aws-efs-csi-driver; aws eks delete-addon --cluster-name cnxsdev-selfmanaged --addon-name eks-pod-identity-agent

