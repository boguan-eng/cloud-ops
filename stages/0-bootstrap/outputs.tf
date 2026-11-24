output "seed_project_id" {
  description = "Seed project ID."
  value       = google_project.seed.project_id
}

output "state_bucket" {
  description = "GCS bucket for state (tfstate/<stage>/) and tfvars (tfvars/<stage-key>/)."
  value       = google_storage_bucket.state.name
}

output "builder_repo" {
  description = "Artifact Registry path for the builder image (append /<image>:<tag>)."
  value       = "${google_artifact_registry_repository.builder.location}-docker.pkg.dev/${google_project.seed.project_id}/${google_artifact_registry_repository.builder.repository_id}"
}

output "service_accounts" {
  description = "IaC service account emails by key (org-plan, org-apply, project-plan, project-apply)."
  value       = { for k, sa in google_service_account.iac : k => sa.email }
}
