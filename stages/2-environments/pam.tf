# Privileged Access Manager (PAM): temporary, approved elevation of group_devops on the prod
# folder. Standing prod access of devops is only devops_prod_roles (iam.tf).
# Docs: https://cloud.google.com/iam/docs/pam-permissions-and-setup
#       https://cloud.google.com/iam/docs/pam-create-entitlements

# PAM API on the prod project only (nonprod has no entitlement).
resource "google_project_service" "pam_prod" {
  project            = google_project.env["prod"].project_id
  service            = "privilegedaccessmanager.googleapis.com"
  disable_on_destroy = false
}

# PAM always uses the ORGANIZATION-level service agent, even for folder entitlements; the role
# is inherited by everything under the prod folder. Additive member binding.
resource "google_folder_iam_member" "pam_service_agent" {
  folder = google_folder.env["prod"].name
  role   = "roles/privilegedaccessmanager.serviceAgent"
  member = "serviceAccount:service-org-${var.org_id}@gcp-sa-pam.iam.gserviceaccount.com"
}

resource "google_privileged_access_manager_entitlement" "prod_operator" {
  entitlement_id       = "prod-operator"
  location             = "global"
  parent               = "folders/${google_folder.env["prod"].folder_id}"
  max_request_duration = "14400s" # 4 h

  eligible_users {
    principals = ["group:${var.group_devops}"]
  }

  privileged_access {
    gcp_iam_access {
      resource_type = "cloudresourcemanager.googleapis.com/Folder"
      resource      = "//cloudresourcemanager.googleapis.com/folders/${google_folder.env["prod"].folder_id}"

      # The previous (full) devops role set.
      dynamic "role_bindings" {
        for_each = toset(var.devops_roles)
        content {
          role = role_bindings.value
        }
      }
    }
  }

  approval_workflow {
    manual_approvals {
      require_approver_justification = true
      steps {
        approvals_needed = 1
        approvers {
          principals = ["group:${var.group_approvers}"]
        }
      }
    }
  }

  requester_justification_config {
    unstructured {}
  }

  depends_on = [
    google_folder_iam_member.pam_service_agent,
    google_project_service.pam_prod,
  ]
}
