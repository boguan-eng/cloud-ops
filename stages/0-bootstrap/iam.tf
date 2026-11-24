# IAM is ADDITIVE ONLY (google_*_iam_member).
# Authoritative IAM resources (full-policy / binding variants) are forbidden here: they overwrite existing bindings.

locals {
  org_plan_roles = [
    "roles/viewer",
    "roles/iam.securityReviewer",
    "roles/orgpolicy.policyViewer",
    "roles/privilegedaccessmanager.viewer",
  ]

  org_apply_roles = [
    "roles/resourcemanager.organizationAdmin",
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
    "roles/orgpolicy.policyAdmin",
    "roles/privilegedaccessmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ]

  billing_plan_roles  = ["roles/billing.viewer"]
  billing_apply_roles = ["roles/billing.user", "roles/billing.costsManager"]

  # role -> role maps (for_each needs a map or set of strings).
  org_plan_bindings     = { for r in local.org_plan_roles : r => r }
  org_apply_bindings    = { for r in local.org_apply_roles : r => r }
  billing_plan_bindings = { for r in local.billing_plan_roles : r => r }
  billing_apply_bind    = { for r in local.billing_apply_roles : r => r }

  approver_roles = [
    "roles/cloudbuild.builds.approver",
    "roles/cloudbuild.builds.viewer",
    "roles/logging.viewer",
  ]
  devops_roles = [
    "roles/cloudbuild.builds.viewer",
    "roles/logging.viewer",
  ]

  approver_bindings = {
    for pair in setproduct(var.approver_principals, local.approver_roles) :
    "${pair[0]}|${pair[1]}" => { member = pair[0], role = pair[1] }
  }
}

# ---------------------------------------------------------------------------
# Organization / billing account (tier: org)
# ---------------------------------------------------------------------------

resource "google_organization_iam_member" "org_plan" {
  for_each = local.org_plan_bindings

  org_id = var.org_id
  role   = each.key
  member = "serviceAccount:${google_service_account.iac["org-plan"].email}"
}

resource "google_organization_iam_member" "org_apply" {
  for_each = local.org_apply_bindings

  org_id = var.org_id
  role   = each.key
  member = "serviceAccount:${google_service_account.iac["org-apply"].email}"
}

resource "google_billing_account_iam_member" "org_plan" {
  for_each = local.billing_plan_bindings

  billing_account_id = var.billing_account
  role               = each.key
  member             = "serviceAccount:${google_service_account.iac["org-plan"].email}"
}

resource "google_billing_account_iam_member" "org_apply" {
  for_each = local.billing_apply_bind

  billing_account_id = var.billing_account
  role               = each.key
  member             = "serviceAccount:${google_service_account.iac["org-apply"].email}"
}

# ---------------------------------------------------------------------------
# State bucket (all four SAs). The project-tier SAs get ONLY bucket access here:
# their roles on env folders/projects are granted by stages/2-environments
# (the folders do not exist at stage 0).
# ---------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "plan_reader" {
  for_each = toset(["org-plan", "project-plan"])

  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.iac[each.key].email}"
}

resource "google_storage_bucket_iam_member" "apply_admin" {
  for_each = toset(["org-apply", "project-apply"])

  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.iac[each.key].email}"
}

# ---------------------------------------------------------------------------
# Seed project / builder repo (all four SAs)
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "sa_log_writer" {
  for_each = google_service_account.iac

  project = google_project.seed.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${each.value.email}"
}

resource "google_artifact_registry_repository_iam_member" "sa_builder_reader" {
  for_each = google_service_account.iac

  project    = google_project.seed.project_id
  location   = google_artifact_registry_repository.builder.location
  repository = google_artifact_registry_repository.builder.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value.email}"
}

# ---------------------------------------------------------------------------
# Humans on the seed project
# ---------------------------------------------------------------------------

resource "google_project_iam_member" "devops" {
  for_each = toset(local.devops_roles)

  project = google_project.seed.project_id
  role    = each.key
  member  = var.devops_principal
}

resource "google_project_iam_member" "approver" {
  for_each = local.approver_bindings

  project = google_project.seed.project_id
  role    = each.value.role
  member  = each.value.member
}

# Cloud Build service agent: creating the 2nd-gen GitHub connection stores the GitHub OAuth
# token as a Secret Manager secret in this project; the API requires the agent to have
# secretmanager.secrets.create and secretmanager.secrets.setIamPolicy (error seen with gcloud;
# the Console flow grants this automatically). Scoped to the seed project only.
resource "google_project_iam_member" "cloudbuild_agent_secret_admin" {
  project = google_project.seed.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:service-${google_project.seed.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  depends_on = [google_project_service.seed]
}

# Creating/updating a Cloud Build trigger that runs as a user-specified service account
# requires iam.serviceAccounts.actAs on that account. Only the trigger admins (normally the
# Org Owner) get it; devops and approvers cannot run code as the IaC SAs.
resource "google_service_account_iam_member" "trigger_admin_act_as" {
  for_each = {
    for pair in setproduct(var.trigger_admin_principals, keys(local.service_accounts)) :
    "${pair[0]}|${pair[1]}" => { member = pair[0], sa = pair[1] }
  }

  service_account_id = google_service_account.iac[each.value.sa].name
  role               = "roles/iam.serviceAccountUser"
  member             = each.value.member
}
