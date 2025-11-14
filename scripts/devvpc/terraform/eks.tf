resource "aws_iam_role" "admin_role" {
  name = var.adminrole
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${var.awsaccountid}:root"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "admin_attach" {
  name       = "FullAdminPolicyAttachment"
  roles      = [aws_iam_role.admin_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_eks_access_entry" "eks_access_for_admin_role" {
  cluster_name  = var.eksclustername
  principal_arn = "arn:aws:iam::${var.awsaccountid}:role/${var.adminrole}"
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = ">= 20.24.2"

  cluster_name    = var.eksclustername
  cluster_version = var.eksclusterversion

  vpc_id                                   = data.aws_vpc.vpc.id
  subnet_ids                               = [for k, v in var.svcsubnetids : v]
  cluster_endpoint_public_access           = true
  cluster_endpoint_private_access          = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  # If you do not set ami_id, the module picks the standard EKS-optimized AMI
  eks_managed_node_group_defaults = {
    tags = {
      "k8s.io/cluster-autoscaler/${var.eksclustername}" = "owned"
      "k8s.io/cluster-autoscaler/enabled"               = "true"
    }
  }

  access_entries = {
    super-adminrole = {
      principal_arn = "arn:aws:iam::${var.awsaccountid}:role/${var.adminrole}"

      policy_associations = {
        this = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  # single node group
  eks_managed_node_groups = {
    ingress = {
      name           = "ingress-nginx-nodes"
      instance_types = ["t3.medium"]
      desired_size   = 2
      min_size       = 2
      max_size       = 4

      # These become Kubernetes node-labels
      labels = {
        role = "ingress"
        app  = "ingress-nginx"
      }

      tags = {
        "ingress" = "true"
      }
    }
    argocd = {
      name           = "argocd-nodes"
      instance_types = ["t3.small"] # dev-sized
      desired_size   = 1
      min_size       = 1
      max_size       = 2

      labels = { role = "argocd" } # kubernetes node-labels
      taints = [
        {
          key    = "dedicated"
          value  = "argocd"
          effect = "NO_SCHEDULE"
        }
      ]

      tags = { argocd = "true" }
    }
    workloads = {
      name           = "workload-nodes"
      instance_types = ["m6i.xlarge"]
      desired_size   = 1
      min_size       = 1
      max_size       = 3

      # no taints – any pod can land here
      labels = { role = "workload" }
    }
  }
}


module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "VPC-CNI-IRSA"
  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true
  attach_ebs_csi_policy = true
  oidc_providers = {
    efs = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller-sa"]
    }
  }
}

/*
resource "aws_security_group" "ingressnodessh" {
   name = "ingressnodessh"
   vpc_id = data.aws_vpc.vpc.id

   // Let SSH incoming
   ingress {
     description = "Security Group for letting in SSH to worker node"
     from_port = 0
     to_port = 22
     protocol = "tcp"
     cidr_blocks = ["10.56.0.0/16"] 
   }
   
   egress {
     description = "Out from node"     
     from_port = 0
     to_port = 0
     protocol = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }
   tags = {
     Name = "ingress_node_ssh"
     //karpenter.sh/discovery = "cnxscert-karpenter"
   }

}
*/

resource "aws_eks_addon" "aws_efs_csi_driver" {
  #count = var.eks_addon_version_efs_csi_driver != null ? 1 : 0

  cluster_name  = module.eks.cluster_name
  addon_name    = "aws-efs-csi-driver"
  addon_version = "v2.0.8-eksbuild.1"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = module.efs_csi_irsa.iam_role_arn

  preserve = true

  tags = {
    "eks_addon" = "aws-ebs-csi-driver"
  }
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-ebs-csi-driver"
  # -- optional: let AWS pick the latest
  # addon_version             = "v1.30.0-eksbuild.1"

  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  preserve                    = true

  tags = { eks_addon = "aws-ebs-csi-driver" }
}

resource "kubernetes_storage_class" "gp2_csi" {
  metadata {
    name = "gp2-csi"
  }

  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type = "gp2"
  }
}

/*resource "terraform_data" "karpenterinstall" {
  input = " '${var.karpenterchartversion}' '${module.eks.cluster_name}' '${var.awsaccountid}' '${module.eks.cluster_endpoint}' '${module.eks.oidc_provider_arn}'"
  //provisioner "local-exec" {                                                                                            
    //command = "${path.module}/karpenterinstall.sh '${var.karpenterchartversion}' '${module.eks.cluster_name}' '${var.awsaccountid}' '${module.eks.cluster_endpoint}' '${module.eks.oidc_provider_arn}'"
    //interpreter = ["/usr/bin/bash"]
    //working_dir = "${path.module}"
  //}                                                                                                                     
}*/

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}
output "oidc_stuff" {
  description = "Check oidc_issuer_url - oidc_provider - oidc_provider_arn - "
  value       = "Issuer: ${module.eks.cluster_oidc_issuer_url} Provider: ${module.eks.oidc_provider} ARN: ${module.eks.oidc_provider_arn}"
}

//IRSA + OIDC
//Get oidc - aws eks describe-cluster --no-verify-ssl --name conexus-dev-eks-PiXj0AhG --region us-east-1 --query "cluster.identity.oidc.issuer" --output text
// https://docs.aws.amazon.com/eks/latest/userguide/associate-service-account-role.html

output "node_security_group_id" {
  description = "Security group ID for all EKS worker nodes"
  value       = module.eks.node_security_group_id
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "EBS-CSI-IRSA"
  attach_ebs_csi_policy = true
  oidc_providers = {
    ebs = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}