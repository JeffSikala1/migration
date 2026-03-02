variable "region" {
  type = string
  description = "AWS region"
  default = ""
}

variable "bastionami" {
  type = string
  description = "ISE hardened AWS Machine Image ID"
  default = ""
}

variable "bastion_s3" {
  type = string
  description = "S3 bucket to store pub keys for bastion host"
  default = ""
}

variable "dnsdomain" {
  type = string
  description = "DNS Domain name in route53"
  default = ""
}

variable "intnlbsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az6 = ""
  }
}
variable "svcsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az6 = ""
  }
}
variable "awsaccountid" {
  type = string
  description = "Account number for the environment"
  default = ""
}
variable "dnszone" {
  type = map(string)
  default = {
    ext = ""
    int = ""
  }
}
variable "services_ec2_cidr_blocks" {
  type = list(string)
  description = "List of CIDRs across azs to spin ec2s in general"
  default = []
}
