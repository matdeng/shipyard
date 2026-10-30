variable "project" {
  description = "Name used for tags and resource names"
  type        = string
  default     = "shipyard"
}

variable "region" {
  description = "AWS region (ap-southeast-1 = Singapore)"
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.20.1.0/24"
}

variable "instance_type" {
  description = "k3s + Prometheus + Grafana need about 4 GB RAM; t3.medium fits"
  type        = string
  default     = "t3.medium"
}

variable "my_ip_cidr" {
  description = "Your public IP as /32, for SSH and the Kubernetes API. Find it with: curl -s ifconfig.me"
  type        = string

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "Use your own IP like 203.0.113.7/32, never 0.0.0.0/0."
  }
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Only written into the Ansible inventory; never uploaded"
  type        = string
  default     = "~/.ssh/id_ed25519"
}
