# Policy: read-only CodeArtifact
data "aws_iam_policy_document" "codeartifact_read" {
  statement {
    sid       = "TokenAndEndpoint"
    effect    = "Allow"
    actions   = ["codeartifact:GetAuthorizationToken", "codeartifact:GetRepositoryEndpoint"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadFromRepository"
    effect    = "Allow"
    actions   = ["codeartifact:ReadFromRepository"]
    resources = local.ca_repo_arns
  }
}

resource "aws_iam_policy" "codeartifact_read" {
  name   = "CodeArtifactRead-${aws_eks_cluster.eks_cluster.name}-${var.irsa_namespace}-${var.irsa_service_account}"
  policy = data.aws_iam_policy_document.codeartifact_read.json
}

locals {
  oidc_hostpath = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  ca_repo_arns  = [
    "arn:aws:codeartifact:${var.region}:${var.codeartifact_account}:repository/${var.codeartifact_domain}/*"
  ]
}

# Role: IRSA trust to SA
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_hostpath}:sub"
      values   = ["system:serviceaccount:${var.irsa_namespace}:${var.irsa_service_account}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  name               = "irsa-codeartifact-${aws_eks_cluster.eks_cluster.name}-${var.irsa_namespace}-${var.irsa_service_account}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "attach_read" {
  role       = aws_iam_role.irsa.name
  policy_arn = aws_iam_policy.codeartifact_read.arn
}