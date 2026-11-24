# Bucket is supplied via -backend-config (pipeline: stages/cloudbuild/*.yaml; local: backend.hcl).
terraform {
  backend "gcs" {
    prefix = "tfstate/3-cicd-wif"
  }
}
