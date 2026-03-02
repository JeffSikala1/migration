data "aws_ami" "ubuntu_20_04_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-UBUNTU-20.04-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.ubuntu_20_04_gsa_hardened.id
}
