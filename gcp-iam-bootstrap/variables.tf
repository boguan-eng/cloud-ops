variable "org_id" {
  description = "Numeric GCP organization ID (without the 'organizations/' prefix)."
  type        = string
}

variable "billing_account" {
  description = "Billing account ID (format XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "prefix" {
  description = "Name prefix for folders, projects and groups. Lowercase letters, digits, hyphens; starts with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,15}$", var.prefix))
    error_message = "prefix must match ^[a-z][a-z0-9-]{1,15}$ (lowercase letters, digits, hyphens; starts with a letter)."
  }
}

variable "project_id_suffix" {
  description = "Optional suffix appended to project IDs. Use only when the derived project ID is already taken globally."
  type        = string
  default     = ""
}

variable "group_admins" {
  description = "Email of the admins Google Group, e.g. <prefix>-gcp-admins@googlegroups.com."
  type        = string
}

variable "group_devops" {
  description = "Email of the devops Google Group."
  type        = string
}

variable "group_developers" {
  description = "Email of the developers Google Group."
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

variable "devops_roles" {
  description = "Folder-level roles granted to group_devops on both prod and nonprod folders."
  type        = list(string)
  default = [
    "roles/compute.admin",
    "roles/container.admin",
    "roles/run.admin",
    "roles/dns.admin",
    "roles/cloudsql.admin",
    "roles/storage.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/logging.admin",
    "roles/monitoring.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}

variable "devops_nonprod_extra_roles" {
  description = "Extra folder-level roles granted to group_devops on the nonprod folder only."
  type        = list(string)
  default     = ["roles/resourcemanager.projectIamAdmin"]
}

variable "developer_roles" {
  description = "Folder-level roles granted to group_developers on both prod and nonprod folders."
  type        = list(string)
  # serviceUsageConsumer: gcloud sends the current project as quota project by default,
  # which requires serviceusage.services.use (otherwise USER_PROJECT_DENIED).
  default = ["roles/logging.viewer", "roles/monitoring.viewer", "roles/serviceusage.serviceUsageConsumer"]
}

variable "project_services" {
  description = "APIs enabled on every env project."
  type        = list(string)
  default     = ["logging.googleapis.com", "monitoring.googleapis.com"]
}
