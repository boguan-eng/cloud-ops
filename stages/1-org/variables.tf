variable "org_id" {
  description = "Numeric GCP organization ID (without the 'organizations/' prefix)."
  type        = string
}

variable "group_admins" {
  description = "Email of the admins Google Group, e.g. <prefix>-gcp-admins@googlegroups.com."
  type        = string
}

variable "admin_org_roles" {
  description = "Org-level roles granted to group_admins."
  type        = list(string)
  default = [
    "roles/resourcemanager.organizationAdmin",
    "roles/billing.admin",
    "roles/resourcemanager.folderAdmin",
    "roles/resourcemanager.projectCreator",
  ]
}
