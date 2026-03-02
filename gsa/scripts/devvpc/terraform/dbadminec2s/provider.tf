terraform {                                                                                          
  required_providers {                                                                               
    aws = {                                                                                          
      source  = "hashicorp/aws"                                                                      
      //version = "~> 5.61.0"
      version = "~> 6.4.0"
    }
  }
  
  backend "s3" {
    key              	   = "dbstate/terraform.tfstate"
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

/*provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name
    ]
  }
}
provider "kubectl" {
  apply_retry_count      = 1
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

*/
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
