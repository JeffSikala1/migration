data "aws_ami" "redhat_7_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-REDHAT-7-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.redhat_7_gsa_hardened.id
}
