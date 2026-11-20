terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# No project set here: auth is via a short-lived access token
# (GOOGLE_OAUTH_ACCESS_TOKEN). Every resource sets its own project.
# State is local and git-ignored (applied by the org admin only).
provider "google" {}
