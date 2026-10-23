# Demo 2 · Networking: a private network where only the right things can talk.
#
# The story: Noon App has a web server and a database server. Neither has a public IP address.
#   - admins reach them through Identity-Aware Proxy (no open SSH port to the internet)
#   - the web server may call the database on one port; nothing else may
#   - both can reach the internet only through Cloud NAT, which gives us one fixed address to give a partner
#
# Things to show live: the four building blocks (VPC, subnets, routes, firewall rules), north-south vs east-west.

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

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# 1. VPC: a private network. Custom mode, so we decide every range.
resource "google_compute_network" "vpc" {
  name                    = "noon-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

# 2. Subnets: one slice of address space per tier, in one region.
resource "google_compute_subnetwork" "web" {
  name                     = "web"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.1.0/24"
  private_ip_google_access = true
}

resource "google_compute_subnetwork" "db" {
  name                     = "db"
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.0.2.0/24"
  private_ip_google_access = true
}

# 3. Firewall rules. Everything inbound is denied until a rule allows it.
resource "google_compute_firewall" "iap_ssh" {
  name          = "allow-iap-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"] # Identity-Aware Proxy's own range
  target_tags   = ["admin-ssh"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "web_to_db" {
  name        = "allow-web-to-db"
  network     = google_compute_network.vpc.name
  direction   = "INGRESS"
  source_tags = ["web"] # east-west: only machines tagged "web"...
  target_tags = ["db"]  # ...may reach machines tagged "db"...
  allow {
    protocol = "tcp"
    ports    = ["8080"] # ...and only on this port
  }
}

# 4. Routes: Google created the subnet routes and the default route for us. List them with:
#    gcloud compute routes list --filter="network:noon-vpc"

# 5. Egress: no public IPs on the servers, so Cloud NAT gives them one shared, fixed address to the internet.
resource "google_compute_address" "nat_ip" {
  name   = "noon-nat-ip"
  region = var.region
}

resource "google_compute_router" "router" {
  name    = "noon-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "noon-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 6. Two private servers (no external IP).
resource "google_compute_instance" "db" {
  name         = "db-vm"
  zone         = var.zone
  machine_type = "e2-small"
  tags         = ["db", "admin-ssh"]

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.db.id # no access_config block = no public IP
  }
  metadata                = { enable-oslogin = "TRUE" }
  metadata_startup_script = <<-SCRIPT
    #!/bin/bash
    mkdir -p /srv/db && echo "hello from the database tier" > /srv/db/index.html
    cd /srv/db && nohup python3 -m http.server 8080 >/var/log/fake-db.log 2>&1 &
  SCRIPT
  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }
  depends_on = [google_compute_router_nat.nat]
}

resource "google_compute_instance" "web" {
  name         = "web-vm"
  zone         = var.zone
  machine_type = "e2-small"
  tags         = ["web", "admin-ssh"]

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }
  network_interface {
    subnetwork = google_compute_subnetwork.web.id
  }
  metadata = { enable-oslogin = "TRUE" }
  shielded_instance_config {
    enable_secure_boot          = true
    enable_integrity_monitoring = true
  }
  depends_on = [google_compute_router_nat.nat]
}

output "nat_ip_partners_allow_list" {
  value = google_compute_address.nat_ip.address
}

output "db_private_ip" {
  value = google_compute_instance.db.network_interface[0].network_ip
}

output "ssh_to_web_through_iap" {
  value = "gcloud compute ssh web-vm --zone ${var.zone} --tunnel-through-iap"
}

output "try_from_web_vm" {
  value = {
    east_west_allowed  = "curl -s http://${google_compute_instance.db.network_interface[0].network_ip}:8080     # works: rule allow-web-to-db"
    east_west_blocked  = "curl -s -m 5 http://${google_compute_instance.db.network_interface[0].network_ip}:22   # times out: no rule for that port"
    north_south_egress = "curl -s https://ifconfig.me   # prints the NAT address above"
  }
}
