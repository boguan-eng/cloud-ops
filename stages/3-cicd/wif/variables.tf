variable "nonprod_project_id" {
  type        = string
  description = "GCP project ID for the nonprod environment."
}

variable "prod_project_id" {
  type        = string
  description = "GCP project ID for the prod environment."
}

variable "github_org_id" {
  type        = string
  description = "Numeric GitHub organization ID (immutable, unlike the org name)."

  validation {
    condition     = can(regex("^[0-9]+$", var.github_org_id))
    error_message = "github_org_id must be numeric."
  }
}
