resource "aws_iam_role" "ssm_role" {
  name = var.role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = var.assume_role_arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      module = "https://github.com/GSA/odp-tf-module-aws-ssm-instance-profile"
    }
  )
}

resource "aws_iam_policy" "ssm_secrets_policy" {
  count = var.assume_role_arn != "" ? 1 : 0

  name        = "SSMSecretsPolicy"
  description = "Allows SSM role to access Secrets Manager in Secrets Account"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = "arn:aws:secretsmanager:us-east-1:${var.secrets_account_id}:secret:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_secrets_policy_attachment" {
  count      = var.assume_role_arn != "" ? 1 : 0
  role       = aws_iam_role.ssm_role.name
  policy_arn = aws_iam_policy.ssm_secrets_policy[count.index].arn
}

resource "aws_iam_role_policy_attachment" "ssm_role_policy" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = var.instance_profile_name
  role = aws_iam_role.ssm_role.name

  tags = merge(
    var.tags,
    {
      module = "https://github.com/GSA/odp-tf-module-aws-ssm-instance-profile"
    }
  )
}
