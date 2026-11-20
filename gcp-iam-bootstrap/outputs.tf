output "folder_ids" {
  description = "Numeric folder IDs keyed by env (prod, nonprod)."
  value       = { for env, f in google_folder.env : env => f.folder_id }
}

output "project_ids" {
  description = "Project IDs keyed by env (prod, nonprod)."
  value       = { for env, p in google_project.env : env => p.project_id }
}
