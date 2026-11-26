variable "nonprod_project_id" {
  type        = string
  description = "GCP project ID for the nonprod environment."
}

variable "prod_project_id" {
  type        = string
  description = "GCP project ID for the prod environment."
}

variable "region" {
  type        = string
  description = "Artifact Registry location."
  default     = "us-central1"
}

variable "wif_pool" {
  type        = map(string)
  description = "Env (nonprod, prod) => WIF pool resource name, from `tofu output wif_pool` in github-ci-wif."

  validation {
    condition     = toset(keys(var.wif_pool)) == toset(["nonprod", "prod"])
    error_message = "wif_pool must have exactly the keys nonprod and prod."
  }

  validation {
    condition     = alltrue([for v in values(var.wif_pool) : can(regex("^projects/[0-9]+/locations/global/workloadIdentityPools/[a-z0-9-]+$", v))])
    error_message = "wif_pool values must match ^projects/[0-9]+/locations/global/workloadIdentityPools/[a-z0-9-]+$."
  }
}

variable "repos" {
  type        = map(string)
  description = "GitHub repo name => numeric GitHub repo ID. The name is used as the Artifact Registry repository ID. Set here (reviewed in a PR), not in tfvars; both values are public on GitHub."
  default = {
    demo-api = "1465693741"
    demo-web = "1465694056"
  }

  validation {
    condition     = alltrue([for name in keys(var.repos) : can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", name))])
    error_message = "Repo names must match ^[a-z]([a-z0-9-]*[a-z0-9])?$."
  }

  validation {
    condition     = alltrue([for id in values(var.repos) : can(regex("^[0-9]+$", id))])
    error_message = "Repo IDs must be numeric."
  }
}
