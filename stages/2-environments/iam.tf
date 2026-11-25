# IAM is ADDITIVE ONLY (google_*_iam_member).
# Authoritative IAM resources (full-policy / binding variants) are forbidden here: they overwrite existing bindings.

locals {
  # devops: standing roles per folder. nonprod: devops_roles; prod: devops_prod_roles only
  # (the full devops_roles set on prod is gated by the PAM entitlement in pam.tf).
  # Key: "<env>/<role>"
  devops_env_roles = {
    nonprod = var.devops_roles
    prod    = var.devops_prod_roles
  }
  devops_folder_roles = merge([
    for env, roles in local.devops_env_roles : {
      for role in toset(roles) : "${env}/${role}" => { env = env, role = role }
    }
  ]...)

  # devops: extra roles on nonprod folder only. Key: "nonprod/<role>"
  devops_nonprod_extra = {
    for role in toset(var.devops_nonprod_extra_roles) :
    "nonprod/${role}" => { env = "nonprod", role = role }
  }

  # developers: developer_roles on prod and nonprod folders. Key: "<env>/<role>"
  developer_folder_roles = {
    for p in setproduct(local.envs, toset(var.developer_roles)) :
    "${p[0]}/${p[1]}" => { env = p[0], role = p[1] }
  }

  # project-tier IaC SAs: plan/apply roles on prod and nonprod folders. Key: "<env>/<role>"
  iac_project_plan_folder_roles = {
    for p in setproduct(local.envs, toset(var.iac_project_plan_roles)) :
    "${p[0]}/${p[1]}" => { env = p[0], role = p[1] }
  }
  iac_project_apply_folder_roles = {
    for p in setproduct(local.envs, toset(var.iac_project_apply_roles)) :
    "${p[0]}/${p[1]}" => { env = p[0], role = p[1] }
  }
}

# devops: nonprod (devops_roles) + prod (devops_prod_roles)
resource "google_folder_iam_member" "devops" {
  for_each = local.devops_folder_roles
  folder   = google_folder.env[each.value.env].name
  role     = each.value.role
  member   = "group:${var.group_devops}"
}

# devops: nonprod folder only
resource "google_folder_iam_member" "devops_nonprod_extra" {
  for_each = local.devops_nonprod_extra
  folder   = google_folder.env[each.value.env].name
  role     = each.value.role
  member   = "group:${var.group_devops}"
}

# developers: prod + nonprod folders (read-only logs/monitoring by default)
resource "google_folder_iam_member" "developers" {
  for_each = local.developer_folder_roles
  folder   = google_folder.env[each.value.env].name
  role     = each.value.role
  member   = "group:${var.group_developers}"
}

# Project-tier IaC SAs (stage 3 pipeline). These let the stage 3 pipeline run (WIF pools,
# AR repos + repo IAM, project APIs). Stage 2 runs before stage 3, so no human apply is needed.
resource "google_folder_iam_member" "iac_project_plan" {
  for_each = local.iac_project_plan_folder_roles
  folder   = google_folder.env[each.value.env].name
  role     = each.value.role
  member   = "serviceAccount:${var.iac_project_plan_sa}"
}

resource "google_folder_iam_member" "iac_project_apply" {
  for_each = local.iac_project_apply_folder_roles
  folder   = google_folder.env[each.value.env].name
  role     = each.value.role
  member   = "serviceAccount:${var.iac_project_apply_sa}"
}
