locals {
  envs = {
    nonprod = var.nonprod_project_id
    prod    = var.prod_project_id
  }

  # env x repo cross product for Artifact Registry repositories.
  ar_repos = merge([
    for env, project in local.envs : {
      for repo in keys(var.repos) : "${env}/${repo}" => {
        env     = env
        project = project
        repo    = repo
      }
    }
  ]...)
}

resource "google_project_service" "artifactregistry" {
  for_each = local.envs

  project                    = each.value
  service                    = "artifactregistry.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_artifact_registry_repository" "this" {
  for_each = local.ar_repos

  project       = each.value.project
  location      = var.region
  repository_id = each.value.repo
  format        = "DOCKER"

  # Prod tags are immutable so a released tag cannot be overwritten.
  dynamic "docker_config" {
    for_each = each.value.env == "prod" ? [1] : []
    content {
      immutable_tags = true
    }
  }

  depends_on = [google_project_service.artifactregistry]
}
