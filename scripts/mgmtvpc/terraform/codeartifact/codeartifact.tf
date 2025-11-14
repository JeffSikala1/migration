resource "aws_kms_key" "cnxsmgmtcodeartifactkey" {
  description = "code artifact key"
}

resource "aws_codeartifact_domain" "conexuscodeartifacturl" {
  domain         = "cnxsartifact"
  encryption_key = aws_kms_key.cnxsmgmtcodeartifactkey.arn
}

resource "aws_codeartifact_repository" "conexuscodeartifact" {
  repository = "conexusartifacts"
  domain     = aws_codeartifact_domain.conexuscodeartifacturl.domain
}
