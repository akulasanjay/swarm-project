# Backend config for the S3 remote state.
# Usage: terraform init -backend-config=backend.hcl
#
# These must match the resources created by the bootstrap config.
bucket         = "docker-swarm-tfstate-CHANGE-ME"   # set to your unique S3 state bucket
region         = "us-east-1"
dynamodb_table = "terraform-locks"
