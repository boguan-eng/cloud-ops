locals {
  seed_project_id = "${var.prefix}-iac-seed${var.seed_project_id_suffix}"

  # Seed project APIs.
  seed_services = [
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudbilling.googleapis.com",
    "billingbudgets.googleapis.com",
    "orgpolicy.googleapis.com",
    "privilegedaccessmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com",
  ]

  # IaC service accounts: key -> account_id. "org" tier runs stages 1-2, "project" tier stage 3.
  service_accounts = {
    org-plan      = "iac-org-plan"
    org-apply     = "iac-org-apply"
    project-plan  = "iac-project-plan"
    project-apply = "iac-project-apply"
  }
}

resource "google_project" "seed" {
  project_id          = local.seed_project_id
  name                = local.seed_project_id
  org_id              = var.org_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

resource "google_project_service" "seed" {
  for_each = toset(local.seed_services)

  project            = google_project.seed.project_id
  service            = each.key
  disable_on_destroy = false
}

# Objects: tfstate/<stage>/ (state) and tfvars/<stage-key>/terraform.tfvars (real input values,
# fetched by Cloud Build at run time; tfvars never live in git).
resource "google_storage_bucket" "state" {
  project                     = google_project.seed.project_id
  name                        = var.state_bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.seed]
}

resource "google_artifact_registry_repository" "builder" {
  project       = google_project.seed.project_id
  location      = var.region
  repository_id = "iac-builder"
  format        = "DOCKER"
  description   = "OpenTofu builder image used by the IaC pipeline."

  docker_config {
    immutable_tags = true
  }

  depends_on = [google_project_service.seed]
}

resource "google_service_account" "iac" {
  for_each = local.service_accounts

  project      = google_project.seed.project_id
  account_id   = each.value
  display_name = each.value

  depends_on = [google_project_service.seed]
}
