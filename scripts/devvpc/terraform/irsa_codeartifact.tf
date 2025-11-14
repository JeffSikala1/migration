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
  name   = local.ca_policy_name
  policy = data.aws_iam_policy_document.codeartifact_read.json
}

locals {
  oidc_hostpath = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
  ca_repo_arns  = [
    "arn:aws:codeartifact:${var.region}:${var.codeartifact_account}:repository/${var.codeartifact_domain}/*"
  ]

  # Bounded names to meet IAM limits
  _cluster = substr(data.aws_eks_cluster.this.name, 0, 20)
  _ns      = substr(var.irsa_namespace, 0, 15)
  _sa      = substr(var.irsa_service_account, 0, 25)
  _hash    = substr(sha1("${data.aws_eks_cluster.this.name}-${var.irsa_namespace}-${var.irsa_service_account}"), 0, 6)

  irsa_role_name = substr("irsa-ca-${local._cluster}-${local._ns}-${local._sa}-${local._hash}", 0, 64)
  ca_policy_name = substr("CodeArtifactRead-${local._cluster}-${local._ns}-${local._sa}-${local._hash}", 0, 128)
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
  name               = local.irsa_role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "attach_read" {
  role       = aws_iam_role.irsa.name
  policy_arn = aws_iam_policy.codeartifact_read.arn
}