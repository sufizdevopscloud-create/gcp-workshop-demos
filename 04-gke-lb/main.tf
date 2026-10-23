# Demo 4 · A Kubernetes cluster (GKE Autopilot) running a small app behind a load balancer.
#
# The story: the Noon App API runs as containers. Kubernetes keeps three identical copies (pods) running, replaces any that die,
# and a Google load balancer gives them one public address.
#
#   internet -> load balancer (Kubernetes "Service") -> 3 pods of hello-app, spread over the cluster
#
# Autopilot means Google manages the machines: you only say how much CPU and memory each pod needs.
# The cluster takes about 8 to 10 minutes to create, so start this demo first and talk while it builds.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google     = { source = "hashicorp/google", version = ">= 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.30" }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "replicas" {
  description = "How many copies (pods) of the app to run."
  type        = number
  default     = 3
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each           = toset(["compute.googleapis.com", "container.googleapis.com"])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- network the cluster lives in
resource "google_compute_network" "gke" {
  name                    = "gke-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "gke" {
  name                     = "gke-subnet"
  region                   = var.region
  network                  = google_compute_network.gke.id
  ip_cidr_range            = "10.40.0.0/20"
  private_ip_google_access = true # private nodes can pull images from Google's registry without a public address

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.44.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.48.0.0/20"
  }
}

# ---------------------------------------------------------------- identity for the machines (nodes)
# Some organizations stop Google granting roles to the default account automatically, so we give the nodes their own account
# with the single role they need: write logs and metrics, and pull images.
resource "google_service_account" "nodes" {
  account_id   = "gke-nodes"
  display_name = "GKE nodes for the Noon demo"
}

resource "google_project_iam_member" "nodes" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

# ---------------------------------------------------------------- the cluster
resource "google_container_cluster" "noon" {
  name                = "noon-autopilot"
  location            = var.region
  enable_autopilot    = true # Google runs the nodes, patches them and scales them
  deletion_protection = false
  network             = google_compute_network.gke.id
  subnetwork          = google_compute_subnetwork.gke.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  private_cluster_config {
    enable_private_nodes    = true  # the machines have no public addresses
    enable_private_endpoint = false # you can still reach the Kubernetes API from your laptop
    master_ipv4_cidr_block  = "172.16.0.32/28"
  }

  cluster_autoscaling {
    auto_provisioning_defaults {
      service_account = google_service_account.nodes.email
      oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  depends_on = [google_project_service.apis, google_project_iam_member.nodes]
}

# ---------------------------------------------------------------- the app: this part is Kubernetes, not Google Cloud
data "google_client_config" "me" {}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.noon.endpoint}"
  token                  = data.google_client_config.me.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.noon.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_deployment_v1" "hello" {
  metadata {
    name   = "hello-app"
    labels = { app = "hello-app" }
  }

  spec {
    replicas = var.replicas # Kubernetes keeps exactly this many pods running

    selector {
      match_labels = { app = "hello-app" }
    }

    template {
      metadata {
        labels = { app = "hello-app" }
      }
      spec {
        container {
          name  = "hello"
          image = "us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0" # prints its own pod name
          port {
            container_port = 8080
          }
          resources {
            requests = { cpu = "250m", memory = "256Mi" } # Autopilot bills for what the pods request
            limits   = { cpu = "250m", memory = "256Mi" }
          }
        }
      }
    }
  }
}

# type = LoadBalancer is the whole trick: Kubernetes asks Google Cloud for a load balancer and a public address.
resource "kubernetes_service_v1" "hello" {
  metadata {
    name = "hello-lb"
  }

  spec {
    type     = "LoadBalancer"
    selector = { app = "hello-app" }
    port {
      port        = 80
      target_port = 8080
    }
  }

  wait_for_load_balancer = true
}

output "app_url" {
  value = "http://${kubernetes_service_v1.hello.status[0].load_balancer[0].ingress[0].ip}"
}

output "try_it" {
  value = "for i in 1 2 3 4 5 6; do curl -s http://${kubernetes_service_v1.hello.status[0].load_balancer[0].ingress[0].ip} | grep Hostname; done"
}

output "connect_kubectl" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.noon.name} --region ${var.region} --project ${var.project_id}"
}

output "kubectl_to_try" {
  value = ["kubectl get pods -o wide", "kubectl get service hello-lb", "kubectl delete pod -l app=hello-app --wait=false   # then kubectl get pods: they come back"]
}
