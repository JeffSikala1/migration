resource "kubernetes_manifest" "argocd_ingress" {
  manifest = yamldecode(file("${path.module}/../k8s/ingress/argocd.yaml"))
}