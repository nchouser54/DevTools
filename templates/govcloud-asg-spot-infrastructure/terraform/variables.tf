terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Load variables from .env.example formatted files
# Usage: terraform -chdir=terraform apply -var-file=../terraform.tfvars
