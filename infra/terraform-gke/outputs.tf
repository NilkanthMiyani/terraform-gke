output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.jerney.name
}

output "cluster_endpoint" {
  description = "GKE cluster API endpoint"
  value       = google_container_cluster.jerney.endpoint
  sensitive   = true
}

output "region" {
  description = "GCP region"
  value       = var.region
}

output "zone" {
  description = "GCP zone"
  value       = var.zone
}

output "node_pool_name" {
  description = "Name of the managed node pool"
  value       = google_container_node_pool.jerney_nodes.name
}

output "node_service_account" {
  description = "Service account email attached to GKE nodes"
  value       = google_service_account.gke_nodes.email
}

output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.jerney_vpc.name
}

output "kubectl_config_command" {
  description = "Run this after `terraform apply` to configure kubectl"
  value       = "gcloud container clusters get-credentials ${var.cluster_name} --zone ${var.zone} --project ${var.project_id}"
}
