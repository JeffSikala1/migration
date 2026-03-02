data "aws_ami" "amz_linux_eks_v1_27_gsa_hardened" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ISE-AMZ-LINUX-EKS-v1.27-GSA-HARDENED-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

output "ami_id" {
  value = data.aws_ami.amz_linux_eks_v1_27_gsa_hardened.id
}