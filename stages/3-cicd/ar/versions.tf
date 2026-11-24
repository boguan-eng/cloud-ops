terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }

  # Bucket is supplied via -backend-config (pipeline: stages/cloudbuild/*.yaml; local: backend.hcl).
  backend "gcs" {
    prefix = "tfstate/3-cicd-ar"
  }
}

# No project set here: auth is via a short-lived access token
# (GOOGLE_OAUTH_ACCESS_TOKEN). Every resource sets its own project.
provider "google" {}
