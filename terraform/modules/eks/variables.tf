variable "cluster_name" {
  type = string
}

variable "kubernetes_version" {
  type = string
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for both the control plane ENIs and the managed node group."
  type        = list(string)
}

variable "instance_types" {
  type = list(string)
}

variable "capacity_type" {
  type = string
}

variable "desired_size" {
  type = number
}

variable "min_size" {
  type = number
}

variable "max_size" {
  type = number
}

variable "admin_principal_arns" {
  description = "IAM principals (users/roles) granted EKS cluster-admin API access via access entries. Explicit list rather than \"whoever runs terraform\", so repeated applies from different identities (local dev user vs. the CI role) stay deterministic."
  type        = list(string)
}
