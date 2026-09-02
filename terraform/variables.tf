variable "region" {
  description = "AWS region. Fixed by the challenge constraints."
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = var.region == "eu-west-1"
    error_message = "This account's guardrail policy only allows eu-west-1."
  }
}

variable "suffix" {
  description = "Unique suffix appended to shared-account resource names (this AWS account is shared across multiple candidates)."
  type        = string
  default     = "juani"
}

variable "human_user_name" {
  description = "IAM user name granted EKS cluster-admin access alongside the CI role, for kubectl access outside the pipeline."
  type        = string
  default     = "juanicolasmuozcampos@gmail.com"
}

variable "azs" {
  description = "Availability zones used for both VPCs' subnets."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]
}

variable "gateway_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "gateway_private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/20", "10.0.16.0/20"]
}

variable "gateway_public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.32.0/24", "10.0.33.0/24"]
}

variable "backend_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "backend_private_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.0.0/20", "10.1.16.0/20"]
}

variable "backend_public_subnet_cidrs" {
  type    = list(string)
  default = ["10.1.32.0/24", "10.1.33.0/24"]
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway per VPC instead of one per AZ. Cost trade-off for a PoC (documented in README)."
  type        = bool
  default     = true
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT is cheaper but can be interrupted - fine for this PoC."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "gateway_node_port" {
  description = "Fixed NodePort for the public gateway Service, so the security group opens exactly one port to the internet instead of the whole NodePort range."
  type        = number
  default     = 30080
}

variable "backend_node_port" {
  description = "Fixed NodePort for the internal backend Service, opened only to the gateway cluster's security group."
  type        = number
  default     = 30081
}
