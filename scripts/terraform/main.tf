
provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

locals {
  cluster_name = "conexus-dev-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "sandbox-vpc"

  cidr = "10.20.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.20.30.0/24", "10.20.40.0/24", "10.20.50.0/24"]
  public_subnets  = ["10.20.130.0/24", "10.20.140.0/24", "10.20.150.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  }
}

/*
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  # version = "19.15.3"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true
  #cluster_timeout       = 3000
  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }
#  timeouts {
#    create = "40m"
#    update = "60m"
#    delete = "30m"
#  }
  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["m5a.xlarge"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "node-group-2"

      instance_types = ["m5a.xlarge"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}
    
*/
/*
resource "aws_security_group" "ingresssftpefs" {
   name = "ingresssftpefs"
   vpc_id = module.vpc.vpc_id

   // Let NFS incoming
   ingress {
     description = "Security Group for letting in NFS requests"
     from_port = 2049
     to_port = 2049
     protocol = "tcp"
     cidr_blocks = ["0.0.0.0/0"] 
   }
   
   egress {
     description = "Out from NFS/EFS"     
     from_port = 0
     to_port = 0
     protocol = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }
   tags = {
     Name = "ingress_efs_sftp"
   }

}
resource "aws_efs_file_system" "efschroot" {
  creation_token = "Conexus SFTP Data"
  encrypted      = false
  tags = {
    Name = "Conexus SFTP Data"
  }
}
resource "aws_efs_file_system" "efsquarantine" {
  creation_token = "Conexus SFTP reject"
  encrypted      = false
  tags = {
    Name = "Conexus SFTP reject"
  }
}
resource "aws_efs_file_system" "efsdatabase" {
  creation_token = "Conexus SFTP Database"
  encrypted      = false
  tags = {
    Name = "Conexus SFTP Database"
  }
}
resource "aws_efs_file_system" "efsattachments" {
  creation_token = "Conexus Order attachments"
  encrypted      = false
  tags = {
    Name = "Conexus Order attachments"
  }
}
resource "aws_efs_file_system" "efsreports" {
  creation_token = "Conexus UI Reports"
  encrypted      = false
  tags = {
    Name = "Conexus UI Reports"
  }
}


resource "aws_efs_mount_target" "efstargetchroot" {
  file_system_id  = aws_efs_file_system.efschroot.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetquarantine" {
  file_system_id  = aws_efs_file_system.efsquarantine.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetdatabase" {
  file_system_id  = aws_efs_file_system.efsdatabase.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetattachments" {
  file_system_id  = aws_efs_file_system.efsattachments.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.ingresssftpefs.id]
}
resource "aws_efs_mount_target" "efstargetreports" {
  file_system_id  = aws_efs_file_system.efsreports.id
  subnet_id       = module.vpc.private_subnets[0]
  security_groups = [aws_security_group.ingresssftpefs.id]
}

*/

/*
# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.20.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}
*/

/*
module "book" {
  source = "./book"
  vpc_id = module.vpc.vpc_id
}
*/

//ssh key pair
resource "aws_key_pair" "deployer" {
  key_name   = "kundm01key"
  public_key = file("${path.module}/kundm01.pub")
}

/*
//Network IP static
resource "aws_network_interface" "sftpdataprocessorIP" {
  subnet_id = module.vpc.private_subnets[0]
  private_ips = "10.20.30.

  tags = {
    Name = "ec2_sftpdataprocessor_network_interface"
  }
}
*/

resource "aws_security_group" "sshingress" {
  name = "ssh ingress"
  vpc_id = module.vpc.vpc_id
  ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "ssh only ingress"
  }
}
/*
resource "aws_instance" "sftpdataprocessor" {
  //ami al2023-ami-2023.5.20240722.0-kernel-6.1-x86_64    
  ami = "ami-0427090fd1714168b" 
  instance_type = "t3a.medium"
  key_name = aws_key_pair.deployer.key_name
  subnet_id = module.vpc.private_subnets[0]
  vpc_security_group_ids = ["${aws_security_group.sshingress.id}"]
  tags = {
    Name = "sftp-data-processor"
  }  
}
*/
//DNS
/*resource "aws_route53_record" "sftphostrecord" {
  zone_id = "Z2JXOZTIPMXYX1"
  name    = "sftpdataprocessor.local" 
  type    = "CNAME"
  ttl     = "60"
  records = [aws_instance.sftpdataprocessor.private_dns]
}*/

/*
# Create a new hosted zone in Route53 for conexus-dev-sandbox.org
resource "aws_route53_zone" "conexus-hosted-zone" {
  name    = "conexus-dev-sandbox.org"
  comment = "Conexus project hosted zone"
  tags = {
    Name = "conexus-dev-sandbox.org"
  }
}
*/

resource "aws_route53_zone" "conexus-private-hosted-zone" {
  name         = "internal.conexus-dev-sandbox.org"
  vpc {
    vpc_id = module.vpc.vpc_id
  }
  tags = {
    Name = "internal.conexus-dev-sandbox.org"
  }
}

/*
# Request an ACM certificate for the domain and validate it via DNS
resource "aws_acm_certificate" "conexus_cert" {
  domain_name       = "*.conexus-dev-sandbox.org"
  validation_method = "DNS"
  tags = {
    Name = "conexus-dev-sandbox.org-certificate"
  }
}

# Create DNS records for each domain validation option
resource "aws_route53_record" "cert_dns_validation" {
  for_each = {
    for dvo in aws_acm_certificate.conexus_cert.domain_validation_options : dvo.domain_name => dvo
  }
  zone_id = aws_route53_zone.conexus-hosted-zone.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 300
}

# Validate the ACM certificate using all validation records
resource "aws_acm_certificate_validation" "conexus_cert_validation" {
  certificate_arn         = aws_acm_certificate.conexus_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_dns_validation : record.fqdn]
}
*/

//Jump Host - Bastion sandbox-bastion.conexus-dev-sandbox.org
resource "aws_iam_role" "bastion" {
  name = "bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "bastion_policy" {
  name        = "bastion-policy"
  description = "Policy for bastion to call EKS"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:aws:eks:us-east-1:200008295591:cluster/cnxsdev-karpenter"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_attach" {
  role       = aws_iam_role.bastion.name
  policy_arn = aws_iam_policy.bastion_policy.arn
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "bastion-instance-profile"
  role = aws_iam_role.bastion.name
}

resource "aws_instance" "bastion" {
  ami                    = "ami-0ebfd941bbafe70c6"              // e.g., "ami-0ebfd941bbafe70c6"
  instance_type          = "t3a.small"            // e.g., "t3a.small"
  key_name               = "kundalam01"
  subnet_id              = element(module.vpc.public_subnets, 0)
  iam_instance_profile   = coalesce(var.iam_instance_profile, aws_iam_instance_profile.bastion_profile.name)
  vpc_security_group_ids = [aws_security_group.sshingress.id]

  root_block_device {
    volume_size = 20
    encrypted   = false
  }

  tags = {
    Name        = "sandbox_bastion_name"
    Description = "Bastion host for sandbox environment"
  }
}

# Find the IAM role the bastion is actually assuming
data "aws_iam_role" "live_bastion" {
  name = "terraform-20250218154025606100000001" # look up instance profile with curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
}

# Attach your EKS DescribeCluster policy to that role
resource "aws_iam_role_policy_attachment" "attach_eks_describe" {
  role       = data.aws_iam_role.live_bastion.name
  policy_arn = aws_iam_policy.bastion_policy.arn
}

module "bastion" {
  source = "./aws-bastion"
  #source  = "Guimove/bastion/aws"
  #version = "3.0.6"
  bucket_name = var.sandbox_bastion_s3
  region = var.region
  vpc_id = module.vpc.vpc_id
  is_lb_private = "false"
  bastion_host_key_pair = "kundalam01"
  create_dns_record = "true"
  hosted_zone_id = "Z03201631KQBE9RN4411F"
  bastion_record_name = "sandbox-bastion.conexus-dev-sandbox.org."
  bastion_iam_policy_name = "SandboxBastionHostPolicy"
  instance_type = "t3a.small"
  bastion_ami = "ami-0ebfd941bbafe70c6"
  disk_encrypt = "false"
  disk_size = "20"
  elb_subnets = module.vpc.public_subnets
  auto_scaling_group_subnets = module.vpc.public_subnets
  cidrs = [ "199.128.0.0/11", "3.231.207.175/32", "35.174.11.115/32" ]
  tags = {
    "name" = "sandbox_bastion_name",
    "description" = "Bastion host for sandbox environment"
  }
  s3_vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_ids       = module.vpc.private_route_table_ids
  iam_instance_profile = aws_iam_instance_profile.bastion_profile.name
}

#locals {
#  object_source = "${path.module}/kundm01.pub"
#}

resource "aws_s3_object" "file_upload" {
  for_each    = fileset("./", "*pub")
  bucket      = var.sandbox_bastion_s3
  key         = "public-keys/${each.value}"
  source      = "./${each.value}"
  source_hash = filemd5("./${each.value}")
}

resource "aws_dynamodb_table" "conexus_devvpctflockid" {
  name           = "conexus-devvpctflockid"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = {
    Name = "conexus-devvpctflockid"
  }
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "conexus-devvpc-tfstate"
  tags = {
    Name = "conexus-devvpc-tfstate"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_kms_alias" "key_alias" {
  name = "alias/${var.sandbox_bastion_s3_key_alias}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state_sse" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = data.aws_kms_alias.key_alias.target_key_id
    }
  }
}

#####################
# vpc endpoint for s3
#####################

# S3 Gateway VPC Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = module.vpc.vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = module.vpc.private_route_table_ids
  tags = {
    Name = "s3-vpc-endpoint"
  }
}

data "aws_iam_policy_document" "s3_vpc_endpoint_policy" {
  statement {
    sid    = "AllowVPCeAccess"
    effect = "Allow"
    actions = [
      "s3:*"
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceVpce"
      values   = [aws_vpc_endpoint.s3.id]
    }
  }

  # Retain the deny insecure transport policy
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# Attach the policy to the bucket
resource "aws_s3_bucket_policy" "allow_vpc_endpoint" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = data.aws_iam_policy_document.s3_vpc_endpoint_policy.json
}
