#!/usr/bin/bash -x




CURRENT_CONTEXT=$(kubectl config current-context)

echo "You are going to make a fundamental or potentially disruptive change. Current kubernet environment is ${CURRENT_CONTEXT}"
read -p "Do you want to proceed? (y/N): " -n 1 ans

if [[ $ans != [yY] ]]; then
    echo "Aborting..."
    exit;
fi



echo
read -p "Upgrade(u) or Install(I): " -n1 uori
INSTALLTYPE="install" 
if [[ $uori =~ [uU] ]]; then
    echo "Upgrading"
    INSTALLTYPE="upgrade"
    exit;
fi

helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts


API_SERVER_IP=$(kubectl cluster-info |grep "control plane" |sed 's/^.*https:\/\/\(.*\)/\1/')
API_SERVER_PORT=443
echo ${API_SERVER_IP}

helm ${INSTALLTYPE} -n kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver --set syncSecret.enabled=true

kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
