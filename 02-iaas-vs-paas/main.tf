# Demo 2 · IaaS vs PaaS: the same tiny web page, run two ways.
#
#   IaaS  a virtual machine: you choose the size and the operating system, and you patch, secure and scale it.
#   PaaS  Cloud Run: you hand over a container; Google runs, patches and scales everything underneath.
#
# Compare the two files of Terraform and count how many decisions each one makes for you.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
  }
}

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "zone" {
  type    = string
  default = "asia-south1-a"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "apis" {
  for_each           = toset(["compute.googleapis.com", "run.googleapis.com"])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- IaaS: a virtual machine
resource "google_compute_network" "demo" {
  name                    = "demo-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.apis]
}

resource "google_compute_subnetwork" "demo" {
  name          = "demo-subnet"
  region        = var.region
  network       = google_compute_network.demo.id
  ip_cidr_range = "10.10.0.0/24"
}

resource "google_compute_firewall" "http" {
  name          = "demo-allow-http"
  network       = google_compute_network.demo.name
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"] # a demo shortcut: the networking demo shows the right way
  target_tags   = ["web"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_instance" "iaas" {
  name         = "noon-iaas-vm"
  zone         = var.zone
  machine_type = "e2-small" # YOU pick the size
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12" # YOU pick, and patch, the operating system
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.demo.id
    access_config {} # a public address, so the page can be opened
  }

  # YOU install and configure the web server.
  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    apt-get update -y && apt-get install -y nginx
    echo "<h1>Noon App on IaaS</h1><p>This is a virtual machine. We patch it, we scale it.</p>" > /var/www/html/index.html
  SCRIPT

  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }
}

# ---------------------------------------------------------------- PaaS: Cloud Run
resource "google_cloud_run_v2_service" "paas" {
  name                = "noon-paas-service"
  location            = var.region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
  depends_on = [google_project_service.apis]
}

output "iaas_url" {
  value = "http://${google_compute_instance.iaas.network_interface[0].access_config[0].nat_ip}"
}

output "paas_url" {
  value = google_cloud_run_v2_service.paas.uri
}

# New organizations block public access to Cloud Run by default, so a browser shows "403 Forbidden".
# This call proves it works: it sends your own identity token.
output "paas_curl" {
  value = "curl -H \"Authorization: Bearer $(gcloud auth print-identity-token)\" ${google_cloud_run_v2_service.paas.uri}"
}

output "who_manages_what" {
  value = {
    iaas = "You: OS patches, web server, scaling, security of the machine. Google: hardware and data centre."
    paas = "You: your container and its settings. Google: servers, OS, patching, scaling, load balancing."
  }
}
