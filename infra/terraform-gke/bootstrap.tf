# ==============================================================
# Jerney - GKE Bootstrap
#
# Terraform manages ONLY two things here:
#   1. helm_release.argocd    — installs ArgoCD into the cluster
#   2. kubectl_manifest.argocd_root_app — applies root-app.yaml
#                               (kubectl provider instead of kubernetes_manifest
#                                because ArgoCD CRDs don't exist at plan time)
#
# Everything else (Gateway API configs, prometheus, signoz,
# loki, etc.) is deployed by ArgoCD from k8s-gke/apps/ in Git.
#
# GitOps deploy order after terraform apply:
#   ArgoCD wave 1: prometheus-stack, signoz, jerney
#   ArgoCD wave 2: gateway, loki-stack
# ==============================================================

# ---- GCP auth token for helm + kubernetes providers ----
data "google_client_config" "default" {}

# ---- Helm provider — connects directly to GKE via cluster endpoint ----
provider "helm" {
  kubernetes {
    host  = "https://${google_container_cluster.jerney.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      google_container_cluster.jerney.master_auth[0].cluster_ca_certificate
    )
  }
}

# ---- kubectl provider — same GKE auth as helm; skips CRD validation at plan time ----
provider "kubectl" {
  host  = "https://${google_container_cluster.jerney.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.jerney.master_auth[0].cluster_ca_certificate
  )
  load_config_file = false
}

# ---- 1. ArgoCD Helm Release ----
resource "helm_release" "argocd" {
  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.20" # ArgoCD v3.4.3 — K8s 1.35-aware schemas fix StatefulSet SSA diff errors
  namespace        = "argocd"
  create_namespace = true
  wait             = true # blocks until all ArgoCD pods are Running
  timeout          = 300

  set {
    # Runs ArgoCD server without TLS — GKE LB handles TLS termination
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [google_container_node_pool.jerney_nodes]
}

# ---- 2. Root App-of-Apps ----
# kubectl provider skips CRD schema validation at plan time, so the
# argoproj.io/Application CRD absence on a fresh cluster is not a problem.
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body  = file("${path.module}/../../k8s-gke/apps/root-app.yaml")
  depends_on = [helm_release.argocd]
}
