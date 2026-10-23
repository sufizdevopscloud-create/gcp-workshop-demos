# Demo 3 · Security: lock down a data bucket in layers.
#
# The story: Noon App stores customer invoices. Who can read them, how are they encrypted, where do secrets live,
# and how would we know if somebody tried something? Each resource below is one layer of defence.
#
#   identity    a service account with exactly one permission (read this bucket), nothing else
#   encryption  our own key (CMEK) from Cloud KMS, rotated every 90 days
#   exposure    the bucket can never be made public, even by mistake
#   secrets     the app password lives in Secret Manager, not in code
#   detection   audit logs record every read and write of the data

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = ">= 6.0" }
    random = { source = "hashicorp/random", version = ">= 3.5" }
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

resource "google_project_service" "apis" {
  for_each           = toset(["storage.googleapis.com", "cloudkms.googleapis.com", "secretmanager.googleapis.com", "iam.googleapis.com"])
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------- identity: least privilege
resource "google_service_account" "invoice_reader" {
  account_id   = "invoice-reader"
  display_name = "Reads invoices, nothing else"
  depends_on   = [google_project_service.apis]
}

# ---------------------------------------------------------------- encryption: our own key
# Key rings can never be deleted in Google Cloud, so a random suffix lets you run this demo again and again.
resource "random_id" "suffix" {
  byte_length = 2
}

resource "google_kms_key_ring" "ring" {
  name       = "noon-keys-${random_id.suffix.hex}"
  location   = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "invoices" {
  name            = "invoices-key"
  key_ring        = google_kms_key_ring.ring.id
  rotation_period = "7776000s" # 90 days
  lifecycle {
    prevent_destroy = false
  }
}

# Cloud Storage must be allowed to use the key on our behalf.
data "google_storage_project_service_account" "gcs" {
  depends_on = [google_project_service.apis] # the Storage API is switched on in this same run
}

resource "google_kms_crypto_key_iam_member" "gcs_uses_key" {
  crypto_key_id = google_kms_crypto_key.invoices.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

# ---------------------------------------------------------------- exposure: a bucket that cannot be made public
resource "google_storage_bucket" "invoices" {
  name                        = "${var.project_id}-noon-invoices"
  location                    = var.region
  uniform_bucket_level_access = true       # access by IAM only, no per-object ACL surprises
  public_access_prevention    = "enforced" # cannot be made public, even by an Owner
  force_destroy               = true

  versioning {
    enabled = true # an overwritten or deleted invoice can be recovered
  }

  encryption {
    default_kms_key_name = google_kms_crypto_key.invoices.id
  }

  depends_on = [google_kms_crypto_key_iam_member.gcs_uses_key]
}

resource "google_storage_bucket_iam_member" "reader_only" {
  bucket = google_storage_bucket.invoices.name
  role   = "roles/storage.objectViewer" # read objects. Not write, not delete, not change permissions.
  member = "serviceAccount:${google_service_account.invoice_reader.email}"
}

# ---------------------------------------------------------------- secrets: not in code
resource "random_password" "db" {
  length  = 24
  special = false
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "noon-db-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db.result
}

resource "google_secret_manager_secret_iam_member" "app_reads_secret" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.invoice_reader.email}"
}

# ---------------------------------------------------------------- detection: who read what, and when
resource "google_project_iam_audit_config" "all" {
  project = var.project_id
  service = "allServices"
  audit_log_config { log_type = "ADMIN_READ" }
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
}

output "bucket" {
  value = google_storage_bucket.invoices.url
}

output "service_account" {
  value = google_service_account.invoice_reader.email
}

output "try_to_break_it" {
  value = {
    make_it_public  = "gcloud storage buckets add-iam-policy-binding ${google_storage_bucket.invoices.url} --member=allUsers --role=roles/storage.objectViewer    # refused: public access prevention"
    see_the_key     = "gcloud kms keys describe invoices-key --keyring ${google_kms_key_ring.ring.name} --location ${var.region}"
    read_the_secret = "gcloud secrets versions access latest --secret noon-db-password    # allowed for you as owner; the app uses its own identity"
    who_did_what    = "gcloud logging read 'protoPayload.serviceName=\"storage.googleapis.com\"' --limit 5 --format='value(protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)'"
  }
}
