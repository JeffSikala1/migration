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

helm repo add cilium https://helm.cilium.io/

API_SERVER_IP=$(kubectl cluster-info |grep "control plane" |sed 's/^.*https:\/\/\(.*\)/\1/')
API_SERVER_PORT=443

#helm install cilium cilium/cilium --version 1.17.5 \
#  --namespace kube-system \
#  --set eni.enabled=true \
#  --set ipam.mode=eni \
#  --set egressMasqueradeInterfaces=eth0 \
#  --set routingMode=native \
#  --set kubeProxyReplacement=true \
#  --set k8sServiceHost=${API_SERVER_IP} \
#  --set k8sServicePort=${API_SERVER_PORT}
#     --set ipam.operator.clusterPoolIPv4PodCIDRList=172.16.0.0/16 \
#     --set cluster.pool-cidr=172.16.0.0/16 \
#     --set ipam.operator.clusterPoolIPv4MaskSize=16 \
	       
echo ${API_SERVER_IP}

kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

read -p "Are the above Gateway API CRD installed alright? Do you want to proceed to helm install/upgrade cilium? (y/N): " -n 1 ansg

if [[ $ansg != [yY] ]]; then
    echo "Aborting..."
    exit;
fi

helm ${INSTALLTYPE} cilium cilium/cilium --version 1.17.5 \
     --namespace kube-system \
     --set bpf.masquerade=true \
     --set kubeProxyReplacement=true \
     --set gatewayAPI.enabled=true \
     --set cluster.id=1 \
     --set cluster.name=cnxsdev-selfmanaged \
     --set ipam.mode=cluster-pool \
     --set ipam.operator.clusterPoolIPv4PodCIDRList='{192.168.0.0/16,172.16.0.0/12}' \
     --set ipMasqAgent.enabled=true \
     --set ipMasqAgent.config.nonMasqueradeCIDRs='{172.16.0.0/12,192.168.0.0/16}' \
     --set ipMasqAgent.config.masqLinkLocal=false \
     --set ingressController.enabled=true \
     --set ingressController.loadbalancerMode=dedicated \
     --set hubble.relay.enabled=true \
     --set hubble.ui.enabled=true \
     --set encryption.enabled=true \
     --set encryption.type=wireguard \
     --set encryption.nodeEncryption=true \
     --set localRedirectPolicy=true \
     --set k8sServiceHost=${API_SERVER_IP} \
     --set k8sServicePort=${API_SERVER_PORT} 


SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
echo "Script directory: $SCRIPT_DIR"
cd $(dirname "${BASH_SOURCE[0]}")
pwd

wget -O node-local-dns.yaml https://raw.githubusercontent.com/cilium/cilium/1.17.5/examples/kubernetes-local-redirect/node-local-dns.yaml
kubedns=$(kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}) && sed -i "s/__PILLAR__DNS__SERVER__/$kubedns/g;" node-local-dns.yaml
kubectl apply -f node-local-dns.yaml

     
#     --set autoDirectNodeRoutes=true \
#     --set ipv4NativeRoutingCIDR=172.16.0.0/12 \


 #    --set rollOutCiliumPods=true \
 #    --set envoy.rollOutPods=true \
 #    --set operator.rollOutPods=true

#  --set eni.enabled=true \
#  --set ipam.mode=eni \
#  --set egressMasqueradeInterfaces=eth0 \
#  --set routingMode=native \
#  
#  --set k8sServiceHost=${API_SERVER_IP} \
#  --set k8sServicePort=${API_SERVER_PORT}

