# one-time manual bootstrap, state bucket + CI role that ../terraform needs to actually run

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "sentinel-tfstate-juani-721500739616"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-west-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project = "sentinel-split-architecture"
    Purpose = "terraform-remote-state"
    Owner   = var.suffix
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3, not KMS: kms:* is denied for this account
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate_tls_only" {
  bucket = aws_s3_bucket.tfstate.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}

# provider already exists in the account and we can't create one, so just reference it
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # the real scoping: repository claim has no embedded ids, unlike sub
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:repository"
      values   = ["${var.github_org}/${var.github_repo}"]
    }

    # AWS also requires a sub condition, wildcarded since GitHub embeds ids into it now (repo:owner@id/repo@id:...)
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}@*/${var.github_repo}@*:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  # -v2: original role's trust policy was wrong and can't be fixed or deleted, left orphaned on purpose
  name                 = "sentinel-github-actions-${var.suffix}-v2"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600
  # no tags, CreateRole is allowed but TagRole isn't, and IAM checks that even for inline tags
}

# same permissions as Candidates_Policy, CI shouldn't be able to do more than I can
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid    = "AllowRequiredServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "eks:*",
      "elasticloadbalancing:*",
      "ecr:*",
      "iam:Get*",
      "iam:List*",
      "iam:Simulate*",
      "iam:CreateServiceLinkedRole",
      "s3:*",
      "cloudwatch:*",
      "logs:*",
      "route53:*",
      "autoscaling:*",
      "ec2messages:*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowEKSRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePolicy",
      "iam:AttachRolePolicy",
      "iam:PassRole",
      "iam:DetachRolePolicy",
      "iam:DeleteRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eks-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sentinel-*",
    ]
  }

  statement {
    sid    = "DenySensitiveServices"
    effect = "Deny"
    actions = [
      "kms:*",
      "secretsmanager:*",
      "rds:*",
      "lambda:*",
      "organizations:*",
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "sentinel-github-actions-${var.suffix}-v2-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}
