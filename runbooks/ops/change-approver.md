# Add or Remove a PAM Approver

Approvers only approve prod `prod-operator` PAM requests (incident access). Infrastructure
changes are approved in GitHub by the `iac-reviewers` team ([change-via-pr.md](change-via-pr.md)).

- **Who:** an admin (member of `gcp-admins`), in the Google Admin console (admin.google.com).
- **Why a group:** the PAM entitlement names `group:gcp-approvers@<domain>` as approver and
  gives it `resourcemanager.folderViewer` on the prod folder (stage 2). Changing people is a
  group membership change; no apply is needed for the permission.
- **Notifications:** group addresses receive no mail in this domain (spike S1), so PAM emails
  go to the individual addresses in `pam_approver_emails` (stage 2 tfvars). Changing them is a
  stage 2 PR.

An approver must not be in `gcp-devops` or `gcp-developers` (the person who requests prod
access must not approve it; PAM also blocks self-approval).

## 1. Add an approver

1. The person has a user account in `<domain>` with 2-Step Verification on.
2. Admin console → Directory → Groups → `gcp-approvers` → **Add members** → the user → Add.
3. Add the user's address to `pam_approver_emails`. Real values are not in the public repo,
   so this is a tfvars-only change done by the admin: edit `stages/2-environments/terraform.tfvars`,
   upload it and start `2-environments-apply` with `prepare` / `run_apply` from
   [runbook 04](../04-stages-via-pipeline.md), then run `2-environments-check`
   ([run-checks.md](run-checks.md)): expect No changes.
4. Verify: the approver opens <https://console.cloud.google.com/iam-admin/pam/grants/approvals>
   and can select the prod folder. IAM may take a few minutes.
5. Give them [approve-pam-grant.md](approve-pam-grant.md).

## 2. Remove an approver

1. Admin console → Directory → Groups → `gcp-approvers` → select the member → **Remove**.
2. Remove the address from `pam_approver_emails` (step 1.3 in reverse).
3. Verify: the account can no longer select the prod folder on the approvals page.
4. Keep at least one approver who is not in `gcp-devops`, or no prod elevation can be approved.

Next: nothing.
