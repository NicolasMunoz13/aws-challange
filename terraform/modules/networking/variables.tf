variable "name" {
  description = "Short name for this VPC, e.g. \"gateway\" or \"backend\"."
  type        = string
}

variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "single_nat_gateway" {
  description = "If true, create one NAT Gateway (in the first AZ) shared by all private subnets. If false, one NAT Gateway per AZ."
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster that will live in this VPC. Used to tag subnets (kubernetes.io/cluster/<name>) so EKS and the in-tree AWS cloud provider can discover them for load balancer placement."
  type        = string
}
