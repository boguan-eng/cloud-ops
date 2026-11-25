# Remove the roles/owner that GCP auto-grants to the creator of a project.
# The stage 2 apply SA (iac-org-apply) creates the env projects, so it is granted roles/owner on
# each of them. That is far more than it needs: it keeps its org-level organizationAdmin /
# serviceUsageAdmin etc., which is enough for later stage 2 applies.
# Only this one member's owner binding is removed; other bindings are untouched.

variable "iac_org_apply_sa" {
  description = "Email of the org-tier apply IaC service account (stage 0 output `service_accounts`, key org-apply). Its auto-granted roles/owner on the env projects is removed."
  type        = string
}

resource "google_project_iam_member_remove" "iac_org_apply_owner" {
  for_each = local.envs

  project = google_project.env[each.key].project_id
  role    = "roles/owner"
  member  = "serviceAccount:${var.iac_org_apply_sa}"
}
