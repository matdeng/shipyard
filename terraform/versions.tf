terraform {
  required_version = ">= 1.6"

  required_providers {
    aws   = { source = "hashicorp/aws", version = "~> 5.60" }
    local = { source = "hashicorp/local", version = "~> 2.5" }
  }

  # Recommended once you're comfortable: keep state in S3 instead of on your laptop.
  # Create the bucket first, then uncomment and run `terraform init -migrate-state`.
  # backend "s3" {
  #   bucket       = "YOUR-tf-state-bucket"
  #   key          = "shipyard/terraform.tfstate"
  #   region       = "ap-southeast-1"
  #   use_lockfile = true   # needs Terraform 1.10+
  # }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
