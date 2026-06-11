variable "project_id" {
  description = "GCP project ID (find it in GCP Console → Project Info)"
  type        = string
  nullable    = false

  validation {
    condition     = length(var.project_id) > 0 && var.project_id != "YOUR_GCP_PROJECT_ID"
    error_message = "project_id must be set to your real GCP project ID in terraform.tfvars."
  }
}

variable "region" {
  description = "GCP region — us-central1 has the cheapest compute in GCP"
  type        = string
  default     = "us-central1"
  nullable    = false
}

variable "zone" {
  description = "Single GCP zone — single-zone cluster is ~3x cheaper than regional"
  type        = string
  default     = "us-central1-a"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.zone))
    error_message = "zone must be a valid GCP zone, e.g. us-central1-a."
  }
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "jerney-gke"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,38}[a-z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 3–40 chars, lowercase alphanumeric and hyphens, start with a letter."
  }
}

variable "environment" {
  description = "Environment name — controls resource labels"
  type        = string
  default     = "dev"
  nullable    = false

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "node_machine_type" {
  description = "GCE machine type — e2-medium (2 vCPU, 4GB) is the minimum practical for this stack"
  type        = string
  default     = "e2-medium"
  nullable    = false
}

variable "min_node_count" {
  description = "Minimum nodes in pool — 1 keeps cost minimal when idle"
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.min_node_count >= 1
    error_message = "min_node_count must be at least 1."
  }
}

variable "max_node_count" {
  description = "Maximum nodes in pool under load"
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.max_node_count >= var.min_node_count
    error_message = "max_node_count must be greater than or equal to min_node_count."
  }
}

variable "disk_size_gb" {
  description = "Node boot disk size in GB — 30 GB is the minimum for the full observability stack"
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.disk_size_gb >= 20
    error_message = "disk_size_gb must be at least 20 GB."
  }
}
