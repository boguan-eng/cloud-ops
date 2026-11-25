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

variable "group_devops" {
  description = "Email of the devops Google Group."
  type        = string
}

variable "group_approvers" {
  description = "Email of the approvers Google Group (approves PAM prod-operator grant requests)."
  type        = string
}

variable "group_developers" {
  description = "Email of the developers Google Group."
  type        = string
}

variable "devops_roles" {
  description = "Role set of the incident-only prod-operator PAM entitlement on the prod folder (temporary, approved; not standing anywhere)."
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

variable "devops_standing_roles" {
  description = "Standing read-only folder-level roles of group_devops on prod and nonprod (viewer cannot read WIF pools). Changes go through PRs; prod writes only via the PAM entitlement."
  type        = list(string)
  default     = ["roles/viewer", "roles/iam.workloadIdentityPoolViewer"]
}

variable "developer_roles" {
  description = "Folder-level roles granted to group_developers on both prod and nonprod folders."
  type        = list(string)
  # serviceUsageConsumer: gcloud sends the current project as quota project by default,
  # which requires serviceusage.services.use (otherwise USER_PROJECT_DENIED).
  default = [
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/serviceusage.serviceUsageConsumer",
    "roles/run.viewer",
    "roles/cloudtrace.user", # can edit trace scopes, cannot change traces or services (accepted)
    "roles/errorreporting.viewer",
  ]
}

variable "project_services" {
  description = "APIs enabled on every env project."
  type        = list(string)
  default     = ["logging.googleapis.com", "monitoring.googleapis.com"]
}

variable "iac_project_plan_sa" {
  description = "Email of the project-tier plan IaC service account (from stage 0 output)."
  type        = string
}

variable "iac_project_apply_sa" {
  description = "Email of the project-tier apply IaC service account (from stage 0 output)."
  type        = string
}

variable "iac_project_plan_roles" {
  description = "Folder-level roles granted to the project-tier plan SA on both prod and nonprod folders."
  type        = list(string)
  default     = ["roles/viewer", "roles/iam.securityReviewer"]
}

variable "iac_project_apply_roles" {
  description = "Folder-level roles granted to the project-tier apply SA on both prod and nonprod folders."
  type        = list(string)
  default = [
    "roles/iam.workloadIdentityPoolAdmin",
    "roles/artifactregistry.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ]
}
