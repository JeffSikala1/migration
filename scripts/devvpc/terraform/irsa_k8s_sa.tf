resource "kubernetes_service_account" "codeartifact_deployer" {
  metadata {
    name      = var.irsa_service_account
    namespace = var.irsa_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.irsa.arn
    }
  }
}