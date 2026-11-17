# Copied next to main.tf by scripts/tf-localstack.sh as localstack_override.tf.
# Merges into the aws provider block in versions.tf to point it at LocalStack.
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2 = var.localstack_endpoint
    sts = var.localstack_endpoint
    iam = var.localstack_endpoint
  }
}

# LocalStack only ships old Canonical AMIs, so match one of those instead of Ubuntu 24.04.
data "aws_ami" "ubuntu" {
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-trusty-14.04-amd64-server-*"]
  }
}
