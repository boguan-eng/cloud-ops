# Cloud Build repository link + per-stage plan/apply triggers (2nd gen, GitHub).
# The GitHub connection itself is created MANUALLY in the Console (interactive GitHub App
# install/OAuth) and referenced by name. Everything here is gated by var.enable_github.
#
# include_build_logs is deliberately NOT set: build logs stay in Cloud Logging and are
# not sent to GitHub (the repo is public).

locals {
  # key -> stage directory and SA tier (org: stages 1-2, project: stage 3).
  stages = {
    "1-org"          = { dir = "stages/1-org", tier = "org" }
    "2-environments" = { dir = "stages/2-environments", tier = "org" }
    "3-cicd-wif"     = { dir = "stages/3-cicd/wif", tier = "project" }
    "3-cicd-ar"      = { dir = "stages/3-cicd/ar", tier = "project" }
  }

  stage_triggers = var.enable_github ? local.stages : {}
}

resource "google_cloudbuildv2_repository" "cloud_ops" {
  count = var.enable_github ? 1 : 0

  project           = google_project.seed.project_id
  location          = var.region
  name              = "cloud-ops"
  parent_connection = "projects/${google_project.seed.project_id}/locations/${var.region}/connections/${var.github_connection_name}"
  remote_uri        = var.github_repo_uri

  depends_on = [google_project_service.seed]
}

resource "google_cloudbuild_trigger" "plan" {
  for_each = local.stage_triggers

  project         = google_project.seed.project_id
  location        = var.region
  name            = "${each.key}-plan"
  description     = "tofu plan for ${each.value.dir} on pull requests to main"
  filename        = "stages/cloudbuild/plan.yaml"
  service_account = google_service_account.iac["${each.value.tier}-plan"].id
  included_files  = ["${each.value.dir}/**", "stages/cloudbuild/**"]

  repository_event_config {
    repository = google_cloudbuildv2_repository.cloud_ops[0].id

    pull_request {
      branch          = "^main$"
      comment_control = "COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY"
    }
  }

  substitutions = {
    _STAGE_DIR     = each.value.dir
    _STAGE_KEY     = each.key
    _STATE_BUCKET  = google_storage_bucket.state.name
    _BUILDER_IMAGE = var.builder_image
  }
}

resource "google_cloudbuild_trigger" "apply" {
  for_each = local.stage_triggers

  project         = google_project.seed.project_id
  location        = var.region
  name            = "${each.key}-apply"
  description     = "tofu apply for ${each.value.dir} on push to main (approval required)"
  filename        = "stages/cloudbuild/apply.yaml"
  service_account = google_service_account.iac["${each.value.tier}-apply"].id
  included_files  = ["${each.value.dir}/**", "stages/cloudbuild/**"]

  repository_event_config {
    repository = google_cloudbuildv2_repository.cloud_ops[0].id

    push {
      branch = "^main$"
    }
  }

  approval_config {
    approval_required = true
  }

  substitutions = {
    _STAGE_DIR     = each.value.dir
    _STAGE_KEY     = each.key
    _STATE_BUCKET  = google_storage_bucket.state.name
    _BUILDER_IMAGE = var.builder_image
  }
}
