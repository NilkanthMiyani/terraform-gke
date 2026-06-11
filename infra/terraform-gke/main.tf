# ==============================================================
# Jerney - GKE Standard Cluster (Free-Tier Optimized)
#
# Cost strategy:
#   - Single-zone cluster (not regional) → avoids 3x node cost
#   - Spot VMs on node pool → ~70% cheaper than on-demand
#   - e2-medium nodes → cheapest machine type viable for this stack
#   - 1 node minimum → scales to zero compute when idle
#   - pd-standard disk → cheapest disk type
# ==============================================================

# ---- Enable required GCP APIs ----
# These take ~1-2 minutes on first apply in a new project
resource "google_project_service" "container" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ---- VPC Network ----
# Custom VPC (not default) — required for GKE best practices
resource "google_compute_network" "jerney_vpc" {
  name                    = "${var.cluster_name}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

# ---- Subnet ----
# Secondary ranges are required by GKE VPC-native clusters.
# VPC-native = pods get real VPC IPs (better performance + network policy support)
resource "google_compute_subnetwork" "jerney_nodes" {
  name          = "${var.cluster_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.jerney_vpc.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.100.0.0/14" # /14 = 262,144 pod IPs
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.104.0.0/20" # /20 = 4,096 service IPs
  }
}

# ---- Firewall: allow HTTP/HTTPS from internet ----
resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.cluster_name}-allow-web"
  network = google_compute_network.jerney_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["gke-${var.cluster_name}"]
}

# ---- Firewall: allow GCP Load Balancer health checks ----
# GKE native ingress (Cloud Load Balancer) probes nodes from these GCP-owned ranges.
# Without this rule health checks fail → backends marked unhealthy → 502 errors.
resource "google_compute_firewall" "allow_gke_health_checks" {
  name    = "${var.cluster_name}-allow-health-checks"
  network = google_compute_network.jerney_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443", "8080", "10256"]
  }
  # GCP Load Balancer and health check prober source ranges (documented by Google)
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["gke-${var.cluster_name}"]
}

# ---- Service Account for GKE nodes ----
# Principle of least privilege — nodes only get what they need
resource "google_service_account" "gke_nodes" {
  account_id   = "${var.cluster_name}-nodes"
  display_name = "Jerney GKE Node SA"
}

locals {
  node_sa_roles = [
    "roles/logging.logWriter",       # write logs to Cloud Logging
    "roles/monitoring.metricWriter", # write metrics to Cloud Monitoring
    "roles/monitoring.viewer",       # read monitoring data
    "roles/artifactregistry.reader", # pull images from Artifact Registry (if used)
  ]
}

resource "google_project_iam_member" "gke_node_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# ---- GKE Standard Cluster ----
resource "google_container_cluster" "jerney" {
  name     = var.cluster_name
  location = var.zone # single zone → ~3x cheaper than regional (which runs 3 control planes)

  # Best practice: create empty cluster, manage node pool separately.
  # This allows upgrading/replacing the node pool without recreating the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.jerney_vpc.id
  subnetwork = google_compute_subnetwork.jerney_nodes.id

  # VPC-native cluster — pods get real VPC IPs, enables NetworkPolicy
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Workload Identity — lets k8s ServiceAccounts impersonate GCP ServiceAccounts
  # Avoids storing GCP credentials as k8s secrets
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false # required for GKE Gateway API (Cloud Load Balancer integration)
    }
    horizontal_pod_autoscaling {
      disabled = false # matches HPA config in k8s/helm/jerney/values.yaml
    }
  }

  gateway_api_config {
    channel = "CHANNEL_STANDARD" # enables GKE Gateway API controller
  }

  # Allow `terraform destroy` to work — set true in prod
  deletion_protection = false

  depends_on = [google_project_service.container]
}

# ---- Node Pool ----
resource "google_container_node_pool" "jerney_nodes" {
  name     = "${var.cluster_name}-nodes"
  location = var.zone
  cluster  = google_container_cluster.jerney.name

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard" # cheapest; use pd-ssd for better I/O in prod

    # Spot VMs: ~70% discount vs on-demand
    # Trade-off: GCP can reclaim with 30s notice — acceptable for dev/learning
    spot = true

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only",
    ]

    workload_metadata_config {
      mode = "GKE_METADATA" # required for Workload Identity on nodes
    }

    tags = ["gke-${var.cluster_name}"] # matches firewall rule target

    labels = {
      env     = var.environment
      project = "jerney"
    }
  }

  management {
    auto_repair  = true # GCP replaces unhealthy nodes automatically
    auto_upgrade = true # keeps nodes on latest GKE patch
  }
}
