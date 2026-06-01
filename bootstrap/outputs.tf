output "state_bucket_name" {
  description = "S3 bucket holding remote state — put this in backend.hcl"
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "DynamoDB lock table — put this in backend.hcl"
  value       = aws_dynamodb_table.locks.id
}

output "ci_role_arn" {
  description = "IAM role ARN for GitHub Actions — set as the AWS_ROLE_ARN secret"
  value       = aws_iam_role.ci.arn
}
