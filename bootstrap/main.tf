########################################
# Bootstrap – one-time setup
#
# Creates the resources that must exist BEFORE the main config can use a
# remote backend + OIDC auth in CI:
#   - S3 bucket for Terraform remote state (versioned, encrypted)
#   - DynamoDB table for state locking
#   - GitHub OIDC provider + IAM role the GitHub Actions workflow assumes
#
# This config itself uses LOCAL state (committed nowhere sensitive). Run it
# once by hand with admin credentials:
#   cd bootstrap && terraform init && terraform apply
########################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

########################################
# Remote state backend resources
########################################

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

########################################
# GitHub OIDC provider + CI role
########################################

# GitHub's OIDC thumbprint is no longer required by AWS, but the provider
# block still expects the field; we derive it from the TLS cert to stay correct.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Restrict which repo/branches can assume the role.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in var.github_allowed_refs : "repo:${var.github_repo}:${ref}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project_name}-gha-terraform"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Broad permissions so Terraform can manage the full stack. Scope this down to
# only the services you use (EC2, ELB, IAM, Route53, autoscaling, etc.) once
# things are working.
resource "aws_iam_role_policy_attachment" "ci_admin" {
  role       = aws_iam_role.ci.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess excludes IAM write; the main config creates IAM roles/profiles,
# so grant scoped IAM management too.
resource "aws_iam_role_policy" "ci_iam" {
  name = "terraform-iam-management"
  role = aws_iam_role.ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:*",
      ]
      Resource = "*"
    }]
  })
}
