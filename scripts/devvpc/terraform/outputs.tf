output "subnets_out" {
  description = "Subnets used by this environment"
  value = {
    private = [for k in sort(keys(var.intnlbsubnetids)) : var.intnlbsubnetids[k]]
    public  = [for k in sort(keys(var.extnlbsubnetids)) : var.extnlbsubnetids[k]]
  }
}

output "vpc_id_out" {
  description = "VPC ID used by this environment"
  value       = var.vpc_id
}

/*
output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}
*/

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = data.aws_eks_cluster.this.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = data.aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value = element(
    split("/", data.aws_eks_cluster.this.role_arn),
    length(split("/", data.aws_eks_cluster.this.role_arn)) - 1
  )
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = data.aws_eks_cluster.this.certificate_authority[0].data
}

output "irsa_role_arn" {
  value       = aws_iam_role.irsa.arn
  description = "IRSA role ARN for codeartifact-deployer"
}

output "irsa_service_account" {
  value       = "${var.irsa_namespace}/${var.irsa_service_account}"
  description = "Namespace/Name of deployer SA"
}
