output "region" {
  value = var.region
}

output "gateway_cluster_name" {
  value = module.eks_gateway.cluster_name
}

output "backend_cluster_name" {
  value = module.eks_backend.cluster_name
}

output "gateway_vpc_id" {
  value = module.network_gateway.vpc_id
}

output "backend_vpc_id" {
  value = module.network_backend.vpc_id
}

output "backend_vpc_cidr" {
  value = module.network_backend.vpc_cidr_block
}

output "gateway_vpc_cidr" {
  value = module.network_gateway.vpc_cidr_block
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "backend_ecr_repository_url" {
  value = module.ecr.repository_urls["sentinel-backend-app-${var.suffix}"]
}

output "gateway_ecr_repository_url" {
  value = module.ecr.repository_urls["sentinel-gateway-proxy-${var.suffix}"]
}

output "gateway_node_port" {
  value = var.gateway_node_port
}

output "backend_node_port" {
  value = var.backend_node_port
}
