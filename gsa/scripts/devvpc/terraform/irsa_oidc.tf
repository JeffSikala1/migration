data "aws_eks_cluster" "this" {
    name = aws_eks_cluster.eks_cluster.name
    }

# Get TLS certificate chain for the OIDC provider
data "tls_certificate" "oidc" {
    url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer 
}

# Create the IAM OIDC provider for the EKS cluster
resource "aws_iam_openid_connect_provider" "this" {
    url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
    client_id_list = ["sts.amazonaws.com"]
    thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}