# Get default versions
data "aws_eks_addon_version" "defaultawsefscsidriver" {
  addon_name         = "aws-efs-csi-driver"  
  kubernetes_version = var.eksclusterversion
}
data "aws_eks_addon_version" "defaultawsebscsidriver" {
  addon_name         = "aws-ebs-csi-driver"  
  kubernetes_version = var.eksclusterversion
}
data "aws_eks_addon_version" "defaultcoredns" {
  addon_name         = "coredns"  
  kubernetes_version = var.eksclusterversion
}
data "aws_eks_addon_version" "defaultekspodidentityagent" {
  addon_name         = "eks-pod-identity-agent"  
  kubernetes_version = var.eksclusterversion
}
data "aws_eks_addon_version" "defaultkubeproxy" {
  addon_name         = "kube-proxy"  
  kubernetes_version = var.eksclusterversion
}

resource "aws_eks_addon" "awsefscsidriver" {
  count = var.ciliuminstalled ? 1 : 0
  cluster_name  = var.eksclustername
  addon_name    = "aws-efs-csi-driver"
  addon_version = data.aws_eks_addon_version.defaultawsefscsidriver.version
/*  pod_identity_association {
    role_arn = aws_iam_role.ekspodidentityrole.arn
    service_account = "ekspodidentity-sa"
  } 
*/
  depends_on = [ aws_eks_cluster.eks_cluster ]
}
resource "aws_eks_addon" "awsebscsidriver" {
  count = var.ciliuminstalled ? 1 : 0
  cluster_name  = var.eksclustername
  addon_name    = "aws-ebs-csi-driver"
  addon_version = data.aws_eks_addon_version.defaultawsebscsidriver.version
  depends_on = [ aws_eks_cluster.eks_cluster ]
}
resource "aws_eks_addon" "coredns" {
  count = var.ciliuminstalled ? 1 : 0
  cluster_name  = var.eksclustername
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.defaultcoredns.version
  depends_on = [ aws_eks_cluster.eks_cluster ]
}
resource "aws_eks_addon" "ekspodidentityagent" {
  count = var.ciliuminstalled ? 1 : 0
  cluster_name  = var.eksclustername
  addon_name    = "eks-pod-identity-agent"
  addon_version = data.aws_eks_addon_version.defaultekspodidentityagent.version
  configuration_values = jsonencode({
    agent = {
      additionalArgs = {
	"-b" = "169.254.170.23"
      }
    }
  })
  depends_on = [ aws_eks_cluster.eks_cluster ]
}

/* Kubeproxy is not needed because of eBPF based CNI */
/*resource "aws_eks_addon" "kubeproxy" {
  cluster_name  = var.eksclustername
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.defaultkubeproxy.version
  depends_on = [ aws_eks_cluster.eks_cluster ]
}*/

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

resource "aws_iam_role" "ekspodidentityrole" {

  name               = "eks-pod-identity-ekspodidentityrole"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy_attachment" "ekspodidentity_s3" {

  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
  role       = aws_iam_role.ekspodidentityrole.name
}

resource "aws_iam_role_policy_attachment" "ekspodidentity_efs" {

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
  role = aws_iam_role.ekspodidentityrole.name
}

# policy for aws secrets
resource "aws_iam_policy" "ekssecretsmanagerpolicy" {

  name        = "ekssecretesmanagerpolicy"
  #path        = "/"
  description = "EKS pods access to secrets manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
	Effect = "Allow",
	Action = [
	  "secretsmanager:GetSecretValue",
	  "secretsmanager:DescribeSecret",
	  "secretsmanager:ListSecrets"
	]
	Resource =  ["arn:aws:secretsmanager:*:*:secret:*"]
      },
      {
	Action   = ["kms:Decrypt"]
	Effect   = "Allow"
	Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ekspodidentity_secretsmanager" {

  policy_arn = aws_iam_policy.ekssecretsmanagerpolicy.arn
  role = aws_iam_role.ekspodidentityrole.name
}

resource "aws_eks_pod_identity_association" "ekspodidentityassociation" {

  cluster_name    = var.eksclustername
  namespace       = "kube-system"
  service_account = "ekspodidentity-sa"
  role_arn        = aws_iam_role.ekspodidentityrole.arn
}

resource "aws_eks_pod_identity_association" "ekspodidentityassociationcnxs" {

  cluster_name    = var.eksclustername
  namespace       = "ingress-nginx"
  service_account = "ekspodidentity-sa"
  role_arn        = aws_iam_role.ekspodidentityrole.arn
}

resource "aws_eks_pod_identity_association" "ekspodidentityassociationdefault" {

  cluster_name    = var.eksclustername
  namespace       = "default"
  service_account = "ekspodidentity-sa"
  role_arn        = aws_iam_role.ekspodidentityrole.arn
}

