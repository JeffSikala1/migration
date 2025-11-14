# ingress-nginx Helm Chart

This folder contains custom Helm values for installing the ingress-nginx controller in NodePort mode.

## Installation

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# If not already created
kubectl create namespace ingress-nginx

# Then install/upgrade:
helm upgrade --install my-nginx \
  ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  -f ./values.yaml