variable "name_prefix" {
  description = "Must start with \"eks-\" or \"sentinel-\", the only prefixes this account's guardrail policy allows for IAM role create/attach/pass/delete."
  type        = string

  validation {
    condition     = can(regex("^(eks-|sentinel-)", var.name_prefix))
    error_message = "name_prefix must start with \"eks-\" or \"sentinel-\"."
  }
}
