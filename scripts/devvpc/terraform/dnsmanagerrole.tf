resource "aws_iam_user" "dnsmgr" {
  name = "dnsmanager"
  tags = var.tags
}

resource "aws_iam_user_policy" "route53policy" {
  name   = "CertManagerRoute53"
  user   = aws_iam_user.dnsmgr.name
  policy = <<POLEOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/*"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ListHostedZonesByName",
      "Resource": "*"
    }
  ]
}
POLEOF
}




/*resource "aws_iam_role" "dnsmanager" {
  name                = "dnsmanagerrole"
  managed_policy_arns = [aws_iam_policy.CertManagerRoute53Access.arn]
  assume_role_policy  = data.aws_iam_policy_document.route53_assume_role_policy.json 
}

data "aws_iam_policy_document" "route53_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }
  }
}


resource "aws_iam_policy" "CertManagerRoute53Access" {
  name = "CertManagerRoute53Access"
  path        = "/"
  description = "For Lets encrypt cert manager dns challenge"

}
*/
