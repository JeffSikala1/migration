variable "region" {
  type = string
  description = "AWS region"
  default = ""
}
variable "vpc_name" {
  type = string
  description = "VPC name"
  default = ""
}
variable "dnsdomain" {
  type = string
  description = "DNS Domain name in route53"
  default = ""
} 
// VPC Environment Flag for ec2s
variable "createdevec2s" {
  type = bool
  description = "Create ec2s or not"
  default = "false"
}
variable "sectoolregenv" {
  type = string
  description = "Sectool Registration environment "
  default = ""
} 
variable "ciliuminstalled" {
  type = bool
  description = "Create cluster then helm install cilium and then create nodes - This flag prevents initial node creation"
  default = "false"
}

//Accounts
variable "awsaccountid" {
  type = string
  description = "Account number for the environment"
  default = ""
}
variable "adminuser" {
  type = map(string)
  default = {
    one = ""
    two = ""
    three = ""
  }
}
variable "aws_auth_roles" {
  description = "List of role maps to add to the aws-auth configmap"
  type        = list(any)
  default     = []
}

variable "adminrole" {
  type = string
  description = "Admin role from FCS Federated account"
  default = ""
}
variable "sshpubkeyname" {
  type = string
  description = "Public ssh key name stored for terraformops user keyfile cloudshellkey.pub"
  default = ""
}

//Subnets
variable "services_ec2_cidr_blocks" {
  type = list(string)
  description = "List of CIDRs across azs to spin ec2s in general"
  default = []
}
variable "intnlb_cidr_blocks" {
  type = list(string)
  description = "List of CIDRs for GSA network ingress NLB "
  default = []
}
variable "extnlb_cidr_blocks" {
  type = list(string)
  description = "List of CIDRs for USDA network ingress NLB"
  default = []
}

variable "intnlbipaddress" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}
variable "extnlbipaddress" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}

// Subnets
variable "intnlbsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}
variable "extnlbsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}
//This will decide whether it is external or internet - for dev/test have nlb in internal and cert/prod in external sub network.
variable "nlbsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}
variable "svcsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}

variable "ekslaunchtemplatezone" {
  type = string
  default = "us-east-1b"
}


variable "dbsubnetids" {
  type = map(string)
  default = {
    az4 = ""
    az1 = ""
  }
}   

// DNS
variable "dnszone" {
  type = map(string)
  default = {
    ext = ""
    int = ""
  }
}
variable "dnszoneinuse" {
  type = string
  description = "Actual DNS zone, internal for Dev/Test and external for Cert/Prod"
  default = ""
}

//EC2 related
variable "amiid" {
  type = string
  description = "AWS Machine Image ID"
  default = ""
}
variable "dbadminamiid" {
  type = string
  description = "AWS Machine Image ID for DB Admin host"
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

variable "sandbox_bastion_s3" {
  type        = string
  description = "S3 bucket backing the sandbox bastion host module"
  default     = null
}

variable "sandbox_bastion_s3_key_alias" {
  type        = string
  description = "KMS key alias used to encrypt the sandbox bastion S3 bucket"
  default     = null
}

variable "iam_instance_profile" {
  type        = string
  description = "Optional IAM instance profile to attach to the sandbox bastion EC2 instance"
  default     = null
}

variable "truststore_s3" {
  type = string
  description = "S3 bucket to store CA bundle for mTLS verification"
  default = ""
}


variable "svcjumpipaddress"  {
  type = map(list(string))
  default = {
  }
}

////For Dev EC2s provisioned in devec2s subfolder
variable "ec2devaipaddress" {
  type = map(list(string))
  default = {
  }
}
variable "ec2devbipaddress" {
  type = map(list(string))
  default = {
  }
}
////

variable "dbadminipaddress"  {
  type = map(list(string))
  default = {
  }
}
         

//EKS
variable "eksamiid" {
  type = string
  description = "For EKS worker node - AWS Machine Image ID"
  default = ""
}

variable "eksamiid1" {
  type = string
  description = "For testing - AWS Machine Image ID"
  default = ""
}

variable "eksamiid2" {
  type = string
  description = "For testing.. - AWS Machine Image ID"
  default = ""
}

variable "eksamiidal2" {
  type = string
  description = "For testing.. - AWS Machine Image ID"
  default = ""
}

variable "eksclusterversion" {
  type = string
  description = "For EKS worker node - AWS Machine Image ID"
  default = ""
}

variable "eksinstancetype" {
  type = list(string)
  default = []
}

variable "ec2instancetype" {
  type = string
  default = "m7a.medium"
}
variable "ec2dbinstancetype" {
  type = string
  default = "r6a.xlarge"
}
variable "karpenterpodinstancetype" {
  type = list(string)
  description = "The EKS managed EC2 node where the pods of karpenter itself will reside"
  default = []
} 

variable "eks_cluster_name" {
  type        = string
  description = "Existing EKS cluster name used for IRSA integration and tagging"
  default     = ""
}

variable "eksclustername" {
  type = string
  default = ""
}

variable "tags" {
  type = map(string)
  default = {}
}

variable karpenterchartversion {
  type = string
  description = "karpenter chart version to use from oci ECR(AWS public) repo"
  default = ""
}

variable uinlbdnsname {
  type = string
  description = "NLB for webfacing conexus ui app / nginx ingress DNS name"
  default = ""
}

variable acmerecord {
  type = list(string)
  description = "Acme txt record produced by certbot "
  default = []
}

variable aws_efs_csi_driver_version {
  type = string
  description = "Fetch using aws eks describe-addon-versions --addon-name aws-efs-csi-driver --kubernetes-version 1.32"
  default = ""
}

variable "sftpusers" {
  type = list(string)
  default = []
}


variable "databaseaz2mtid" {
  type = string
  description = "Variable to store AZ2 mount target for database EFS - Used by dbadminhost"
  default = ""
}

//DB -Aurora Postgresql

variable "db_cluster_name" {
  description = "The name of the Aurora cluster"
  type        = string
}

variable "master_username" {
  description = "Username of the DB super user"
  type = string
  default = "postgres"
}

variable "secret_name" {
  description = "The name of the secret in AWS Secrets Manager"
  type        = string
}
 
variable "master_password" {
  description = "The database password to store in the secret"
  type        = string
  sensitive   = true
} 

# Namespace where the deployer ServiceAccount will live
variable "irsa_namespace" {
  type        = string
  description = "Kubernetes namespace for the IRSA-enabled ServiceAccount"
  default     = "ingress-nginx"
}

# Name of the ServiceAccount the deploy Job will use
variable "irsa_service_account" {
  type        = string
  description = "Kubernetes ServiceAccount name to annotate with the IRSA role"
  default     = "codeartifact-deployer"
}

variable "codeartifact_account" {
  type        = string
  description = "AWS Account ID that owns the CodeArtifact domain"
  default     = "339713019047"
}

variable "codeartifact_domain" {
  type        = string
  description = "CodeArtifact domain name"
  default     = "cnxsartifact"
}

# Whether Terraform also creates the Kubernetes ServiceAccount (true) or you
# manage it in Git/ArgoCD (false). If false, TF still creates IAM role/policy
# and you just reference the role ARN in your SA manifest.
variable "manage_k8s_sa" {
  type        = bool
  description = "Let Terraform create the annotated ServiceAccount"
  default     = true
}

variable "vpc_id" {
  type        = string
  description = "VPC ID used for load balancer target groups"
  default     = ""
}

variable "enable_bitbucket" {
  type        = bool
  description = "Whether to deploy Bitbucket stack"
  default     = false
}