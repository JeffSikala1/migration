data "aws_ami" "windows_2022_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-WINDOWS-2022-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.windows_2022_gsa_hardened.id
}
