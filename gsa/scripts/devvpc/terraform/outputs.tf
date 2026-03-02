output "subnets_out" {                                                                               
  value = data.aws_subnets.subnets                                                                   
}

output "subnet" {                                                                                    
  value = [for subnet in data.aws_subnet.subnet : subnet.arn]                                        
}                                                                                                    
                                                                                                     
output "subnetcidr" {                                                                                
  value = [for subnet in data.aws_subnet.subnet : subnet.cidr_block]                                 
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
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
}

output "cluster_iam_role_name" {
  description = "IAM role name associated with EKS cluster"
  value       = aws_iam_role.eks_cluster_role.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.eks_cluster.certificate_authority[0].data
}

output "irsa_role_arn" {
  value       = aws_iam_role.irsa.arn
  description = "IRSA role ARN for codeartifact-deployer"
}

output "irsa_service_account" {
  value       = "${var.irsa_namespace}/${var.irsa_service_account}"
  description = "Namespace/Name of deployer SA"
}
