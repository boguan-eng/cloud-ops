# IAM is ADDITIVE ONLY (google_*_iam_member).
# Authoritative IAM resources (full-policy / binding variants) are forbidden here: they overwrite existing bindings.

locals {
  # devops: devops_roles on prod and nonprod folders. Key: "<env>/<role>"
  devops_folder_roles = {
    for p in setproduct(local.envs, toset(var.devops_roles)) :
    "${p[0]}/${p[1]}" => { env = p[0], role = p[1] }
  }

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
}

# admins: org-level roles (organizationAdmin, billing.admin, folderAdmin, projectCreator)
resource "google_organization_iam_member" "admins" {
  for_each = toset(var.admin_org_roles)
  org_id   = var.org_id
  role     = each.key
  member   = "group:${var.group_admins}"
}

# devops: prod + nonprod folders
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
