# Organization Policy baseline (T8, decided 2026-11-25). Free; enforced on everything under the org.
#
# imported: defaults of the new Cloud Identity org, read on 2026-11-25;
#   managed here so changes need a PR and the daily 1-org-check detects console edits.
# added:    compute.skipDefaultNetworkCreation, storage.publicAccessPrevention,
#           sql.restrictPublicIp, compute.requireOsLogin.
# Deferred: compute.vmExternalIpAccess (later chapters may need VMs/GKE with external IPs),
#           gcp.resourceLocations (needs a region plan).
# An exception is a project-level policy (in the stage that owns the project), not an edit here.
# Docs: https://cloud.google.com/resource-manager/docs/organization-policy/org-policy-constraints

locals {
  org_policy_imported = toset([
    "iam.managed.disableServiceAccountKeyCreation",
    "iam.disableServiceAccountKeyUpload",
    "iam.automaticIamGrantsForDefaultServiceAccounts",
    "storage.uniformBucketLevelAccess",
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

resource "google_org_policy_policy" "allowed_policy_member_domains" {
  name   = "organizations/${var.org_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_policy_member_customer_ids
      }
    }
  }
}

resource "google_org_policy_policy" "allowed_contact_domains" {
  name   = "organizations/${var.org_id}/policies/essentialcontacts.managed.allowedContactDomains"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce    = "TRUE"
      parameters = jsonencode({ allowedDomains = var.allowed_contact_domains })
    }
  }
}

resource "google_org_policy_policy" "managed_protocol_forwarding_internal_only" {
  name   = "organizations/${var.org_id}/policies/compute.managed.restrictProtocolForwardingCreationForTypes"
  parent = "organizations/${var.org_id}"

  spec {
    rules {
      enforce    = "TRUE"
      parameters = jsonencode({ allowedSchemes = ["INTERNAL"] })
    }
  }
}

import {
  for_each = local.org_policy_imported
  to       = google_org_policy_policy.enforce[each.value]
  id       = "organizations/${var.org_id}/policies/${each.value}"
}

import {
  to = google_org_policy_policy.allowed_policy_member_domains
  id = "organizations/${var.org_id}/policies/iam.allowedPolicyMemberDomains"
}

import {
  to = google_org_policy_policy.allowed_contact_domains
  id = "organizations/${var.org_id}/policies/essentialcontacts.managed.allowedContactDomains"
}

import {
  to = google_org_policy_policy.managed_protocol_forwarding_internal_only
  id = "organizations/${var.org_id}/policies/compute.managed.restrictProtocolForwardingCreationForTypes"
}
