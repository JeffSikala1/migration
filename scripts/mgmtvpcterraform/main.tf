terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.45.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

locals {

  vpc_name = "fcs-conexus-mgmt-M"
  ec2_cidr_blocks = [ "10.56.112.0/24", "10.56.113.0/24" ]
  intnlb_cidr_blocks = [ "10.56.119.0/28", "10.56.119.16/28" ]
  pubnlb_cidr_blocks = [ "10.56.82.64/26", "10.56.82.192/26" ]
  intnlb_az4_ipv4_address = "10.56.119.8"
  intnlb_az6_ipv4_address = "10.56.119.26"
  lpvtsvcaz4="Private-Services-az4"
  lpvtsvcaz6="Private-Services-az6"
 
}

data "aws_vpc" "vpc" {
  filter {
    name = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "subnets" {
  filter {
    name   = "vpc-id"
    values = [ data.aws_vpc.vpc.id ]
  }
}


output "subnets_out" {
  value = data.aws_subnets.subnets
 
