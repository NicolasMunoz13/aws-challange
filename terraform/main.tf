data "aws_caller_identity" "current" {}

locals {
  gateway_cluster_name = "eks-gateway-${var.suffix}"
  backend_cluster_name = "eks-backend-${var.suffix}"

  # grant both my user and the CI role admin access, doesn't matter who ran apply
  admin_principal_arns = distinct([
    data.aws_caller_identity.current.arn,
    "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sentinel-github-actions-${var.suffix}-v2",
  ])
}

module "network_gateway" {
  source = "./modules/networking"

  name                 = "gateway-${var.suffix}"
  vpc_cidr             = var.gateway_vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.gateway_private_subnet_cidrs
  public_subnet_cidrs  = var.gateway_public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  eks_cluster_name     = local.gateway_cluster_name
}

module "network_backend" {
  source = "./modules/networking"

  name                 = "backend-${var.suffix}"
  vpc_cidr             = var.backend_vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.backend_private_subnet_cidrs
  public_subnet_cidrs  = var.backend_public_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  eks_cluster_name     = local.backend_cluster_name
}

# peers both VPCs and adds routes on every route table
module "peering" {
  source = "./modules/peering"

  name = "gateway-backend-${var.suffix}"

  requester_vpc_id          = module.network_gateway.vpc_id
  requester_cidr            = module.network_gateway.vpc_cidr_block
  requester_route_table_ids = concat(module.network_gateway.private_route_table_ids, module.network_gateway.public_route_table_ids)

  accepter_vpc_id          = module.network_backend.vpc_id
  accepter_cidr            = module.network_backend.vpc_cidr_block
  accepter_route_table_ids = concat(module.network_backend.private_route_table_ids, module.network_backend.public_route_table_ids)
}

module "iam_gateway" {
  source      = "./modules/iam-eks"
  name_prefix = "eks-gateway-${var.suffix}"
}

module "iam_backend" {
  source      = "./modules/iam-eks"
  name_prefix = "eks-backend-${var.suffix}"
}

module "eks_gateway" {
  source = "./modules/eks"

  cluster_name         = local.gateway_cluster_name
  kubernetes_version   = var.kubernetes_version
  cluster_role_arn     = module.iam_gateway.cluster_role_arn
  node_role_arn        = module.iam_gateway.node_role_arn
  subnet_ids           = module.network_gateway.private_subnet_ids
  instance_types       = var.node_instance_types
  capacity_type        = var.node_capacity_type
  desired_size         = var.node_desired_size
  min_size             = var.node_min_size
  max_size             = var.node_max_size
  admin_principal_arns = local.admin_principal_arns
}

module "eks_backend" {
  source = "./modules/eks"

  cluster_name         = local.backend_cluster_name
  kubernetes_version   = var.kubernetes_version
  cluster_role_arn     = module.iam_backend.cluster_role_arn
  node_role_arn        = module.iam_backend.node_role_arn
  subnet_ids           = module.network_backend.private_subnet_ids
  instance_types       = var.node_instance_types
  capacity_type        = var.node_capacity_type
  desired_size         = var.node_desired_size
  min_size             = var.node_min_size
  max_size             = var.node_max_size
  admin_principal_arns = local.admin_principal_arns
}

module "cross_vpc_sg" {
  source = "./modules/cross-vpc-sg"

  gateway_cluster_security_group_id = module.eks_gateway.cluster_security_group_id
  backend_cluster_security_group_id = module.eks_backend.cluster_security_group_id
  gateway_node_port                 = var.gateway_node_port
  backend_node_port                 = var.backend_node_port

  depends_on = [module.peering]
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = [
    "sentinel-backend-app-${var.suffix}",
    "sentinel-gateway-proxy-${var.suffix}",
  ]
}
