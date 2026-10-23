# Demo 1 · Cloud computing: a "pop-up page" for a sale, live in about two minutes.
#
# The story: Noon App wants a landing page for the National Day sale. With cloud computing there is nothing to buy,
# nothing to install and nothing to pay while nobody visits: Cloud Run scales to zero, and bills only for request time.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
  }
}

variable "project_id" {
  description = "A sandbox project you can freely create and destroy things in."
  type        = string
}

variable "region" {
  description = "Mumbai, India (the Dammam region is not available to this billing account)."
  type        = string
  default     = "asia-south1"
}

variable "allow_public" {
  description = "true lets anyone on the internet open the page (needs an org that allows allUsers). false keeps it private: call it with an identity token."
  type        = bool
  default     = false
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Turn on the services we use. Nothing is billed until something is created.
resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# 2. The "web server": a ready-made sample container. No servers, no operating system, no patching.
resource "google_cloud_run_v2_service" "popup" {
  name                = "noon-sale-popup"
  location            = var.region
  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0 # nobody visiting = nothing running = nothing to pay
      max_instance_count = 5 # a ceiling, so a surprise cannot become a surprise bill
    }
    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }
    }
  }

  depends_on = [google_project_service.run]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_public ? 1 : 0
  name     = google_cloud_run_v2_service.popup.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# 3. Somewhere to keep the sale images: object storage that grows as you add files.
resource "google_storage_bucket" "assets" {
  name                        = "${var.project_id}-noon-sale-assets"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  lifecycle_rule {
    condition { age = 30 }
    action { type = "Delete" } # the sale is over: stop paying for its files
  }
}

output "page_url" {
  value = google_cloud_run_v2_service.popup.uri
}

output "try_it" {
  value = var.allow_public ? "curl ${google_cloud_run_v2_service.popup.uri}" : "curl -H \"Authorization: Bearer $(gcloud auth print-identity-token)\" ${google_cloud_run_v2_service.popup.uri}"
}

output "bucket" {
  value = google_storage_bucket.assets.url
}
