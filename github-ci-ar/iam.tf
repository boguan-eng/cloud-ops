# Additive IAM only (iam_member): never iam_policy / iam_binding, so existing
# bindings on these repositories are never overwritten.

# Each env's pool can push to that env's repos.
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each = local.ar_repos

  project    = each.value.project
  location   = var.region
  repository = google_artifact_registry_repository.this[each.key].repository_id
  role       = "roles/artifactregistry.writer"
  member     = "principalSet://iam.googleapis.com/${var.wif_pool[each.value.env]}/attribute.repository_id/${var.repos[each.value.repo]}"
}

# Prod pool can read nonprod repos (promote source).
resource "google_artifact_registry_repository_iam_member" "prod_reads_nonprod" {
  for_each = var.repos

  project    = var.nonprod_project_id
  location   = var.region
  repository = google_artifact_registry_repository.this["nonprod/${each.key}"].repository_id
  role       = "roles/artifactregistry.reader"
  member     = "principalSet://iam.googleapis.com/${var.wif_pool["prod"]}/attribute.repository_id/${each.value}"
}
