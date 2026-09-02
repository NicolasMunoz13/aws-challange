output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "The EKS-managed security group shared by the control plane and, by default, every managed node group instance's primary ENI."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}
