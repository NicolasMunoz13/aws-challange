variable "region" {
  description = "AWS region. Fixed by the challenge constraints."
  type        = string
  default     = "eu-west-1"
}

variable "suffix" {
  description = "Unique suffix appended to shared-account resource names to avoid collisions with other candidates in the same AWS account."
  type        = string
  default     = "juani"
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform remote state."
  type        = string
  default     = "sentinel-tfstate-juani-721500739616"
}

variable "github_org" {
  description = "GitHub organization or user that owns the deploying repository."
  type        = string
  default     = "NicolasMunoz13"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "aws-challange"
}
