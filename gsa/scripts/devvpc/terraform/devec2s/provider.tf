terraform {                                                                                          
  required_providers {                                                                               
    aws = {                                                                                          
      source  = "hashicorp/aws"                                                                      
      version = "~> 5.61.0"                                                                          
    }

  }
  
  backend "s3" {
    bucket="devvpc-tfstate"
    region="us-east-1"
    encrypt=true
    dynamodb_table="ec2devvpctflockid"
    key              	   = "ec2state/terraform.tfstate"
  }
}

provider "aws" {                                                                                     
  region = "us-east-1"                                                                               
}

# This provider is required for ECR to autheticate with public repos. Please note ECR authetication requires us-east-1 as region hence its hardcoded below.
# If your region is same as us-east-1 then you can just use one aws provider
/*provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}*/

/*data "aws_eks_cluster_auth" "this" {
  name = "<cluster_id>"
}

data "aws_ecr_authorization_token" "token" {
  registry_id = "<ecr_aws_account_id>"
}*/


################################################################################
# Common data/locals
################################################################################

/*data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}*/

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
