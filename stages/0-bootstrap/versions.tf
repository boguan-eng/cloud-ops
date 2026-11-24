terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# No project set here: auth is via Application Default Credentials
# (gcloud auth application-default login, or Cloud Shell credentials).
# Every project-scoped resource passes its project explicitly.
provider "google" {}
