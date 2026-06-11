# ==============================================================
# Jerney - GKE versions.tf
# Standard file: terraform block + provider block live here
# ==============================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }

  backend "gcs" {
    bucket = "jerney-tfstate"
    prefix = "jerney-gke/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
