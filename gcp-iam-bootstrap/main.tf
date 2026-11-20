locals {
  envs = toset(["prod", "nonprod"])

  project_ids = { for env in local.envs : env => "${var.prefix}-app-${env}${var.project_id_suffix}" }

  project_services = {
    for pair in setproduct(local.envs, toset(var.project_services)) :
    "${pair[0]}/${pair[1]}" => { env = pair[0], service = pair[1] }
  }
}

resource "google_folder" "env" {
  for_each            = local.envs
  display_name        = each.key
  parent              = "organizations/${var.org_id}"
  deletion_protection = true
}

resource "google_project" "env" {
  for_each            = local.envs
  name                = local.project_ids[each.key]
  project_id          = local.project_ids[each.key]
  folder_id           = google_folder.env[each.key].folder_id
  billing_account     = var.billing_account
  auto_create_network = false
  deletion_policy     = "PREVENT"
}

resource "google_project_service" "env" {
  for_each                   = local.project_services
  project                    = google_project.env[each.value.env].project_id
  service                    = each.value.service
  disable_on_destroy         = false
  disable_dependent_services = false
}
