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

variable "seed_project_id_suffix" {
  description = "Optional suffix appended to the seed project ID (<prefix>-iac-seed<suffix>). Use only when the derived ID is already taken globally."
  type        = string
  default     = ""
}

variable "region" {
  description = "Region for the state bucket, Artifact Registry repo, Cloud Build connection and triggers."
  type        = string
  default     = "us-central1"
}

variable "state_bucket_name" {
  description = "Name of the GCS bucket for OpenTofu state and tfvars. Must be globally unique."
  type        = string
}

variable "devops_principal" {
  description = "IAM member of the devops team, with type prefix (e.g. 'group:acme-gcp-devops@googlegroups.com'). Gets Cloud Build viewer + logging viewer on the seed project."
  type        = string
}

variable "approver_principals" {
  description = "IAM members (with type prefix, e.g. 'user:...' or 'group:...') allowed to approve apply builds on the seed project."
  type        = list(string)
}

variable "billing_viewer_principals" {
  description = "IAM members (with type prefix, normally one group, e.g. 'group:acme-gcp-billing@googlegroups.com') granted roles/billing.viewer on the billing account."
  type        = list(string)
  default     = []
}

variable "trigger_admin_principals" {
  description = "IAM members allowed to actAs the IaC service accounts, which is required to create/update Cloud Build triggers that run as them. Normally the Org Owner user(s) only."
  type        = list(string)
}

variable "builder_image" {
  description = "Full Artifact Registry reference (with tag) of the OpenTofu builder image, used in trigger substitutions. May be empty while enable_github is false."
  type        = string
  default     = ""
}

variable "enable_github" {
  description = "Create the Cloud Build repository link and the plan/apply triggers. Requires the GitHub connection to exist (created manually in the Console)."
  type        = bool
  default     = false

  validation {
    condition = !var.enable_github || (
      var.github_connection_name != "" &&
      var.github_repo_uri != "" &&
      var.builder_image != ""
    )
    error_message = "When enable_github is true, github_connection_name, github_repo_uri and builder_image must be non-empty."
  }
}

variable "github_connection_name" {
  description = "Name of the Cloud Build 2nd-gen GitHub connection in the seed project/region. Created MANUALLY in the Console (needs interactive GitHub App install/OAuth)."
  type        = string
  default     = ""
}

variable "github_repo_uri" {
  description = "Clone URL of the GitHub repo to link, e.g. https://github.com/<org>/cloud-ops.git."
  type        = string
  default     = ""
}

variable "check_schedule" {
  description = "Cron schedule (unix-cron) of the Cloud Scheduler jobs that start the <stage>-check triggers."
  type        = string
  default     = "0 3 * * *"
}

variable "check_time_zone" {
  description = "IANA time zone for check_schedule."
  type        = string
  default     = "Asia/Taipei"
}
