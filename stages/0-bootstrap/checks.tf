# Scheduled drift/coverage checks: Cloud Scheduler starts the <stage>-check triggers daily.
# Gated by var.enable_github like the triggers themselves.
#
# Why: starting a trigger needs cloudbuild.builds.create AND actAs on the trigger's SA. actAs on
# a plan SA would let a human run any build as it (org-wide read, state, tfvars), so humans do
# NOT get it. Instead the dedicated SA iac-check-runner holds actAs on the two PLAN SAs only,
# so it cannot start an apply trigger (apply SAs are never granted). The devops group only
# gets roles/cloudscheduler.jobRunner on the seed, to run the jobs on demand.
#
# Cost: Cloud Scheduler gives 3 free jobs per billing account, then USD 0.10/job/month
# (Cloud Scheduler pricing, checked 2026-11-25). 4 jobs here.
#
# Cloud Scheduler's own service agent mints the OAuth token (roles/cloudscheduler.serviceAgent,
# which includes iam.serviceAccounts.getAccessToken); it is created when the API is enabled.
# The principal applying stage 0 needs actAs on iac-check-runner to create the jobs.

resource "google_service_account" "check_runner" {
  count = var.enable_github ? 1 : 0

  project      = google_project.seed.project_id
  account_id   = "iac-check-runner"
  display_name = "iac-check-runner"
  description  = "Only starts the <stage>-check Cloud Build triggers (actAs on the plan SAs only; cannot start applies)."

  depends_on = [google_project_service.seed]
}

# Minimal custom role: create + read builds. cloudbuild.builds.create is what RunBuildTrigger needs.
resource "google_project_iam_custom_role" "build_trigger_runner" {
  count = var.enable_github ? 1 : 0

  project     = google_project.seed.project_id
  role_id     = "buildTriggerRunner"
  title       = "Build Trigger Runner"
  description = "Start Cloud Build trigger runs and read builds; nothing else."
  permissions = [
    "cloudbuild.builds.create",
    "cloudbuild.builds.get",
    "cloudbuild.builds.list",
  ]

  depends_on = [google_project_service.seed]
}

resource "google_project_iam_member" "check_runner" {
  count = var.enable_github ? 1 : 0

  project = google_project.seed.project_id
  role    = google_project_iam_custom_role.build_trigger_runner[0].id
  member  = "serviceAccount:${google_service_account.check_runner[0].email}"
}

# actAs on the PLAN SAs only (check triggers run as them). Never the apply SAs.
resource "google_service_account_iam_member" "check_runner_act_as" {
  for_each = var.enable_github ? toset(["org-plan", "project-plan"]) : toset([])

  service_account_id = google_service_account.iac[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.check_runner[0].email}"
}

# Same request as `gcloud builds triggers run <key>-check --branch=main --region=<region>`:
# POST v1/projects/<p>/locations/<r>/triggers/<trigger>:run with RunBuildTriggerRequest.
resource "google_cloud_scheduler_job" "check" {
  for_each = local.stage_triggers

  project     = google_project.seed.project_id
  region      = var.region
  name        = "${each.key}-check"
  description = "Starts the ${each.key}-check Cloud Build trigger (tofu plan -detailed-exitcode on main)."
  schedule    = var.check_schedule
  time_zone   = var.check_time_zone

  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/projects/${google_project.seed.project_id}/locations/${var.region}/triggers/${google_cloudbuild_trigger.check[each.key].name}:run"
    headers     = { "Content-Type" = "application/json" }
    body = base64encode(jsonencode({
      source = { branchName = "main" }
    }))

    oauth_token {
      service_account_email = google_service_account.check_runner[0].email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.seed,
    google_project_iam_member.check_runner,
    google_service_account_iam_member.check_runner_act_as,
  ]
}

# devops can run the jobs on demand (the runner SA, not the human, holds actAs).
resource "google_project_iam_member" "devops_job_runner" {
  count = var.enable_github ? 1 : 0

  project = google_project.seed.project_id
  role    = "roles/cloudscheduler.jobRunner"
  member  = var.devops_principal
}
