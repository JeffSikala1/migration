data "aws_ami" "amazon_linux_2_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-AMAZON-LINUX-2-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.amazon_linux_2_gsa_hardened.id
}