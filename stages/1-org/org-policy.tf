# Organization Policy baseline (T8, decided 2026-11-25). Free; enforced on everything under the org.
#
# imported: Google's secure-by-default policies already enforced on this org when it was created;
#   managed here so changes need a PR and the daily 1-org-check detects console edits.
# added:    compute.skipDefaultNetworkCreation, storage.publicAccessPrevention,
#           sql.restrictPublicIp, compute.requireOsLogin.
# Deferred: compute.vmExternalIpAccess (later chapters may need VMs/GKE with external IPs),
#           gcp.resourceLocations (needs a region plan). Not applicable without a domain:
#           iam.allowedPolicyMemberDomains.
# An exception is a project-level policy (in the stage that owns the project), not an edit here.
# Docs: https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints

locals {
  org_policy_imported = toset([
    "iam.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.uniformBucketLevelAccess",
    "compute.setNewProjectDefaultToZonalDNSOnly",
  ])
  org_policy_added = toset([
    "compute.skipDefaultNetworkCreation",
    "storage.publicAccessPrevention",
    "sql.restrictPublicIp",
    "compute.requireOsLogin",
  ])
}

# Boolean constraints: enforced.
resource "google_org_policy_policy" "enforce" {
  for_each = setunion(local.org_policy_imported, local.org_policy_added)

  name   = "organizations/${var.org_id}/policies/${each.value}"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

# List constraint: only internal protocol forwarding rules.
resource "google_org_policy_policy" "protocol_forwarding_internal_only" {
  name   = "organizations/${var.org_id}/policies/compute.restrictProtocolForwardingCreationForTypes"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = ["INTERNAL"]
      }
    }
  }
}

import {
  for_each = local.org_policy_imported
  to       = google_org_policy_policy.enforce[each.value]
  id       = "organizations/${var.org_id}/policies/${each.value}"
}

import {
  to = google_org_policy_policy.protocol_forwarding_internal_only
  id = "organizations/${var.org_id}/policies/compute.restrictProtocolForwardingCreationForTypes"
}
