locals {
  envs = {
    nonprod = var.nonprod_project_id
    prod    = var.prod_project_id
  }

  apis = [
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ]

  # Per-env WIF attribute condition: only the org's repos, only the matching
  # GitHub Environment, and only the allowed ref (main branch / v* tags).
  provider_conditions = {
    nonprod = "assertion.repository_owner_id == \"${var.github_org_id}\" && assertion.environment == \"nonprod\" && assertion.ref == \"refs/heads/main\""
    prod    = "assertion.repository_owner_id == \"${var.github_org_id}\" && assertion.environment == \"prod\" && assertion.ref.startsWith(\"refs/tags/v\")"
  }

  # env x api cross product for project services.
  services = merge([
    for env, project in local.envs : {
      for api in local.apis : "${env}/${api}" => {
        project = project
        api     = api
      }
    }
  ]...)
}

resource "google_project_service" "this" {
  for_each = local.services

  project                    = each.value.project
  service                    = each.value.api
  disable_on_destroy         = false
  disable_dependent_services = false
}

# One pool per environment (not one shared pool): devops has projectIamAdmin on
# nonprod and could grant itself pool admin there. A single pool in nonprod would
# let it forge an identity that is accepted by prod. Separate pools keep prod trust
# anchored in the prod project.
resource "google_iam_workload_identity_pool" "github" {
  for_each = local.envs

  project                   = each.value
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"

  depends_on = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  for_each = local.envs

  project                            = each.value
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.environment"         = "assertion.environment"
    "attribute.ref"                 = "assertion.ref"
  }

  attribute_condition = local.provider_conditions[each.key]

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
