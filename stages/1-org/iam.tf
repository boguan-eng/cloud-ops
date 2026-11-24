# IAM is ADDITIVE ONLY (google_*_iam_member).
# Authoritative IAM resources (full-policy / binding variants) are forbidden here: they overwrite existing bindings.

# admins: org-level roles (organizationAdmin, billing.admin, folderAdmin, projectCreator)
resource "google_organization_iam_member" "admins" {
  for_each = toset(var.admin_org_roles)
  org_id   = var.org_id
  role     = each.key
  member   = "group:${var.group_admins}"
}
