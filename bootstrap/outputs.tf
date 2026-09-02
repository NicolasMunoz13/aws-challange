output "state_bucket_name" {
  description = "S3 bucket holding Terraform remote state. Put this in terraform/backend.tf."
  value       = aws_s3_bucket.tfstate.id
}

output "github_actions_role_arn" {
  description = "Role ARN for GitHub Actions to assume via OIDC. Set as the AWS_ROLE_ARN repository/environment variable."
  value       = aws_iam_role.github_actions.arn
}
