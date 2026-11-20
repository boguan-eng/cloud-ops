# Hand these values to devops (contain project numbers): do not commit values.
output "wif_pool" {
  description = "Per env: WIF pool resource name (input wif_pool of github-ci-ar)."
  value       = { for env, p in google_iam_workload_identity_pool.github : env => p.name }
}

output "wif_provider" {
  description = "Per env: full WIF provider resource name (GitHub secret GCP_WIF_PROVIDER)."
  value       = { for env, p in google_iam_workload_identity_pool_provider.github : env => p.name }
}
