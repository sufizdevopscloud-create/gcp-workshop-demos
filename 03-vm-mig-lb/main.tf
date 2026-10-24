# Demo 3 · Virtual machines in a managed instance group behind a load balancer.
#
# The story: the Noon App web tier cannot be one server. If it dies the shop is down, and on sale day one server is too small.
# So we run identical copies in a managed instance group (MIG), spread over zones, and put ONE address in front of them.
#
#   internet -> load balancer (one address) -> health check -> 2 to 4 identical VMs, in different zones
#
# The VMs have NO public address. They reach the internet through Cloud NAT (to install nginx) and are reached only by the load balancer.

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

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------- network: private subnet, NAT, and the doors the load balancer needs
resource "google_compute_network" "web" {
  name                    = "mig-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

resource "google_compute_subnetwork" "web" {
  name                     = "mig-subnet"
  region                   = var.region
  network                  = google_compute_network.web.id
  ip_cidr_range            = "10.30.0.0/24"
  private_ip_google_access = true
}

resource "google_compute_router" "web" {
  name    = "mig-router"
  region  = var.region
  network = google_compute_network.web.id
}

resource "google_compute_router_nat" "web" {
  name                               = "mig-nat"
  router                             = google_compute_router.web.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Only Google's load balancer and health-check machines may reach the VMs, on port 80.
resource "google_compute_firewall" "lb_and_health_checks" {
  name          = "mig-allow-lb-and-health-checks"
  network       = google_compute_network.web.name
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

# ---------------------------------------------------------------- the recipe for one VM (the instance template)
resource "google_service_account" "web" {
  account_id   = "mig-web"
  display_name = "Noon web tier VMs (no permissions on purpose)"
}

resource "google_compute_instance_template" "web" {
  name_prefix  = "noon-web-"
  machine_type = "e2-small"
  tags         = ["web"]

  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.web.id # no access_config block = no public IP
  }

  service_account {
    email  = google_service_account.web.email
    scopes = ["cloud-platform"]
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }

  # Every new VM runs this on first boot. The page shows the VM's own name, so you can see the load balancer rotating.
  metadata = {
    startup-script = <<-SCRIPT
      #!/bin/bash
      apt-get update -y && apt-get install -y nginx
      echo "<h1>Noon App web tier</h1><p>Served by <b>$(hostname)</b> in zone <b>$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print $NF}')</b></p>" > /var/www/html/index.html
    SCRIPT
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------- the managed instance group: copies, healing, scaling
resource "google_compute_health_check" "web" {
  name                = "mig-health-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3
  http_health_check {
    port         = 80
    request_path = "/"
  }
  depends_on = [google_project_service.compute]
}

resource "google_compute_region_instance_group_manager" "web" {
  name               = "noon-web-mig"
  region             = var.region
  base_instance_name = "noon-web"

  version {
    instance_template = google_compute_instance_template.web.id
  }

  named_port {
    name = "http"
    port = 80
  }

  # Auto-healing: a VM that fails the health check is deleted and replaced. Nobody gets paged.
  auto_healing_policies {
    health_check      = google_compute_health_check.web.id
    initial_delay_sec = 180
  }

  depends_on = [google_compute_router_nat.web]
}

# Auto-scaling: between 2 and 4 VMs, adding more when the average CPU passes 60%.
resource "google_compute_region_autoscaler" "web" {
  name   = "noon-web-autoscaler"
  region = var.region
  target = google_compute_region_instance_group_manager.web.id

  autoscaling_policy {
    min_replicas    = 2
    max_replicas    = 4
    cooldown_period = 90
    cpu_utilization {
      target = 0.6
    }
  }
}

# ---------------------------------------------------------------- the load balancer: one address in front of all the VMs
resource "google_compute_global_address" "lb" {
  name       = "noon-web-ip"
  depends_on = [google_project_service.compute]
}

resource "google_compute_backend_service" "web" {
  name                  = "noon-web-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.web.id]

  backend {
    group           = google_compute_region_instance_group_manager.web.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "web" {
  name            = "noon-web-url-map"
  default_service = google_compute_backend_service.web.id
}

resource "google_compute_target_http_proxy" "web" {
  name    = "noon-web-proxy"
  url_map = google_compute_url_map.web.id
}

resource "google_compute_global_forwarding_rule" "web" {
  name                  = "noon-web-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.lb.id
  port_range            = "80"
  target                = google_compute_target_http_proxy.web.id
}

output "load_balancer_url" {
  value = "http://${google_compute_global_address.lb.address}"
}

output "wait_first" {
  value = "The load balancer takes 3 to 5 minutes to start answering (a 502 error or a timeout first). That is normal."
}

output "try_it" {
  value = "for i in 1 2 3 4 5 6 7 8; do curl -s http://${google_compute_global_address.lb.address} | grep -o 'noon-web-[a-z0-9-]*'; done"
}

output "see_it_in_the_console" {
  value = "Compute Engine > Instance groups > noon-web-mig, and Network services > Load balancing > noon-web-url-map"
}
