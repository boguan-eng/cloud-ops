output "ar_repo_path" {
  description = "Per env, per repo: Artifact Registry docker path."
  value = {
    for env, project in local.envs : env => {
      for repo in keys(var.repos) : repo => "${var.region}-docker.pkg.dev/${project}/${repo}"
    }
  }
}
