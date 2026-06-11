# ==============================================================
# Bootstrap — creates the GCS bucket used as the Terraform
# remote backend for infra/terraform-gke.
#
# Uses local state intentionally — this module is the
# prerequisite that makes remote state possible.
# Run once before working in terraform-gke:
#   terraform init && terraform apply
# ==============================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the state bucket"
  type        = string
  default     = "us-central1"
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket for Terraform remote state"
  type        = string
}

resource "google_storage_bucket" "tf_state" {
  name          = var.state_bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}

output "state_bucket_name" {
  description = "Set this as the bucket in infra/terraform-gke/versions.tf backend block"
  value       = google_storage_bucket.tf_state.name
}
