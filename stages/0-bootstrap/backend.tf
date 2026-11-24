# The state bucket is supplied via `-backend-config=backend.hcl` (git-ignored; see
# backend.hcl.example).
#
# On the very first run the bucket does not exist yet (this stage creates it), so this
# file is temporarily renamed to backend.tf.off to use local state. After the first apply
# it is renamed back and the state is migrated (see runbooks/02-stage0-bootstrap.md).
terraform {
  backend "gcs" {
    prefix = "tfstate/0-bootstrap"
  }
}
