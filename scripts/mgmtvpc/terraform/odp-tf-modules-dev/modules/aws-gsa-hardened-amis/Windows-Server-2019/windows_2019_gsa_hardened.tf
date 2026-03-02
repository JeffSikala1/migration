data "aws_ami" "windows_2019_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-WINDOWS-2019-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.windows_2019_gsa_hardened.id
}
