# Jerney — GKE Infrastructure (Terraform)

This directory provisions a **GKE Standard cluster** on Google Cloud Platform to run the Jerney 3-tier blog application.  
It replaces the `terraform-ec2/` kubeadm setup with a fully managed Kubernetes control plane.

---

## What This Creates

| Resource | Type | Purpose |
|---|---|---|
| `jerney-gke-vpc` | VPC Network | Isolated network for the cluster |
| `jerney-gke-subnet` | Subnetwork | Node subnet + secondary ranges for pods/services |
| `jerney-gke-allow-web` | Firewall Rule | Opens 80/443/30080/30443 to the internet |
| `jerney-gke-nodes` SA | Service Account | Least-privilege identity for node VMs |
| `jerney-gke` | GKE Standard Cluster | Single-zone managed Kubernetes |
| `jerney-gke-nodes` | Node Pool | Spot e2-medium nodes, autoscales 2–5 |

### IP Ranges

| Range | CIDR | Use |
|---|---|---|
| Node subnet | `10.0.0.0/24` | GCE VM IPs for nodes |
| Pod range | `10.100.0.0/14` | Pod IPs (VPC-native) |
| Service range | `10.104.0.0/20` | ClusterIP service IPs |

---

## Cost Strategy (Free Tier)

This config is designed to stay as cheap as possible while still running the full stack:

- **Single-zone cluster** (`us-central1-a`) — regional clusters run 3 control planes, ~3× the cost
- **Spot VMs** on node pool — ~70% cheaper than on-demand; GCP can reclaim with 30s notice (acceptable for dev)
- **e2-medium** (2 vCPU, 4 GB) — minimum practical size for running the full observability stack
- **2 node minimum** — keeps a spare node so a spot preemption doesn't take the cluster down while a replacement provisions
- **pd-standard disk** — cheapest disk type, vs pd-ssd

> **Note:** GKE Standard has a cluster management fee of ~$0.10/hr (~$72/month). GCP's $300 free trial credit covers this for several months. If you want zero management fee, GKE Autopilot charges per pod instead.

---

## Project Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────┐
│  GCP (us-central1-a)                                │
│                                                     │
│  ┌─────────────── jerney-gke-vpc ────────────────┐  │
│  │                                               │  │
│  │  GKE Standard Cluster: jerney-gke             │  │
│  │  ┌───────────────────────────────────────┐    │  │
│  │  │  Node Pool (Spot e2-medium, 1–3)      │    │  │
│  │  │                                       │    │  │
│  │  │  ┌─────────────────────────────────┐  │    │  │
│  │  │  │  Namespace: gateway             │  │    │  │
│  │  │  │  GKE Gateway API (HTTPRoute)    │  │    │  │
│  │  │  │  :80  :443                      │  │    │  │
│  │  │  └────────────┬────────────────────┘  │    │  │
│  │  │               │                       │    │  │
│  │  │  ┌────────────▼────────────────────┐  │    │  │
│  │  │  │  Namespace: jerney              │  │    │  │
│  │  │  │                                 │  │    │  │
│  │  │  │  frontend (React)               │  │    │  │
│  │  │  │  backend  (Node.js + /metrics)  │  │    │  │
│  │  │  │  postgresql (Bitnami chart)     │  │    │  │
│  │  │  └─────────────────────────────────┘  │    │  │
│  │  │                                       │    │  │
│  │  │  ┌─────────────────────────────────┐  │    │  │
│  │  │  │  Namespace: argocd              │  │    │  │
│  │  │  │  ArgoCD (GitOps controller)     │  │    │  │
│  │  │  │  watches: k8s/helm/jerney/      │  │    │  │
│  │  │  └─────────────────────────────────┘  │    │  │
│  │  │                                       │    │  │
│  │  │  ┌─────────────────────────────────┐  │    │  │
│  │  │  │  Namespace: monitoring          │  │    │  │
│  │  │  │  Prometheus (scrapes /metrics)  │  │    │  │
│  │  │  │  Grafana    (dashboards + Loki) │  │    │  │
│  │  │  │  Loki       (log aggregation)   │  │    │  │
│  │  │  │  Promtail   (log shipping)      │  │    │  │
│  │  │  └─────────────────────────────────┘  │    │  │
│  │  │                                       │    │  │

│  │  └───────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

---

## Full Deployment Flow

```
1. terraform apply          ← provisions GKE cluster + VPC (main.tf)
         │                    installs ArgoCD via Helm (bootstrap.tf)
         │                    applies root-app.yaml via kubectl_manifest (bootstrap.tf)
         ▼
2. ArgoCD syncs             ← deploys frontend, backend, PostgreSQL,
   helm chart                  Gateway API configs, Prometheus, Grafana,
                               Loki, SigNoz from k8s-gke/apps/ in Git
         │
         ▼
3. CircleCI pipeline        ← on every git push to main:
   (on code push)              lint → sca → build → image-scan
                               → update-manifest (bumps image tag in values.yaml)
         │
         ▼
4. ArgoCD detects diff      ← polls GitHub every 3min, sees new image tag
   in values.yaml              in values.yaml, triggers rolling update
         │
         ▼
5. Prometheus scrapes       ← reads pod annotations:
   /metrics                    prometheus.io/scrape: "true"
                               prometheus.io/port: "5000"
         │
         ▼
6. Grafana shows            ← kube-prometheus-stack dashboards +
   metrics + logs              Loki data source for log queries
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | >= 1.5 | `brew install terraform` |
| gcloud CLI | latest | [cloud.google.com/sdk](https://cloud.google.com/sdk/docs/install) |
| kubectl | >= 1.28 | `gcloud components install kubectl` |
| helm | >= 3.12 | `brew install helm` |

---

## Usage

### 1. Authenticate with GCP

```bash
gcloud auth login
gcloud auth application-default login
```

### 2. Create the Terraform state bucket

```bash
gcloud storage buckets create gs://my-tf-state-bucket \
  --location=us-central1 \
  --uniform-bucket-level-access
```

Update the bucket name in `versions.tf` backend block to match.

### 3. Create the TLS certificate map (manual — one time)

The Gateway uses a single wildcard cert (`*.nilkanthprojects.site`) via GCP Certificate Manager:

```bash
# 1. Create the wildcard managed certificate
gcloud certificate-manager certificates create nilkanthprojects-wildcard \
  --domains="*.nilkanthprojects.site" --global

# 2. Create a cert map
gcloud certificate-manager maps create jerney-cert-map

# 3. Create a single wildcard cert map entry
gcloud certificate-manager maps entries create wildcard-entry \
  --map=jerney-cert-map \
  --certificates=nilkanthprojects-wildcard \
  --hostname="*.nilkanthprojects.site"
```

> Certs provision asynchronously. Check status with:
> `gcloud certificate-manager certificates describe nilkanthprojects-wildcard`
> Wait until it shows `ACTIVE` before pointing DNS at the Gateway IP.

### 4. Set your project ID

Edit `terraform.tfvars` (copy from `terraform.tfvars.example`):
```hcl
project_id = "your-actual-project-id"
```

### 5. Apply

```bash
cd terraform-gke/

terraform init
terraform plan
terraform apply
```

Apply takes ~5–10 minutes (mostly GKE control plane provisioning).

### 6. Configure kubectl (optional — for manual inspection)

Copy the command from Terraform output:
```bash
terraform output kubectl_config_command
# → gcloud container clusters get-credentials jerney-gke --zone us-central1-a --project <your-project>
```

Run it, then verify:
```bash
kubectl get nodes
```

> ArgoCD and the root app-of-apps are applied automatically by `terraform apply` via `bootstrap.tf` — no post-setup script needed.

---

## Differences vs terraform-ec2

| | terraform-ec2 | terraform-gke |
|---|---|---|
| Kubernetes | kubeadm (self-managed) | GKE Standard (managed control plane) |
| Nodes | Single EC2 t3.large | Spot e2-medium, autoscales 2–5 |
| Control plane | Your responsibility | Google's responsibility |
| Cluster upgrades | Manual kubeadm upgrade | GKE auto-upgrade |
| Setup time | ~20 min (userdata.sh) | ~10 min (terraform apply) |
| Node failure | Manual intervention | GKE auto-repair replaces node |
| Cost | ~$50–60/month (t3.large) | ~$15–25/month (spot e2-medium + mgmt fee) |

---

## Tear Down

```bash
terraform destroy
```

This deletes the cluster, VPC, firewall rules, and service account.  
**Warning:** All workloads and persistent volumes will be deleted.

---

## File Structure

```
terraform-gke/
├── versions.tf       # terraform block, required_providers (google, helm, kubectl)
├── main.tf           # VPC, subnet, firewall, service account, GKE cluster + node pool
├── bootstrap.tf      # ArgoCD Helm release + root app-of-apps (kubectl_manifest)
├── variables.tf      # all input variables with descriptions
├── outputs.tf        # cluster endpoint, kubectl command, service account
├── terraform.tfvars  # your values (set project_id here)
└── README.md         # this file
```
