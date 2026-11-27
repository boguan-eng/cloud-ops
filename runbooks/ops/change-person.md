# People Change: Join, Leave, Role Change

All GCP access is group membership (R4), so a person change is a group change, never an IAM or
code change. Accounts are named after the person and are not reused: a leaver's account is
deleted, not handed over (audit logs stay attributable).

- **Who:** an admin (`gcp-admins`, super admin) in the Google Admin console
  (admin.google.com); a GitHub org Owner for GitHub; a Cloudflare Super Administrator for
  Cloudflare.
- **Order (handover):** add and verify the new person first, then remove the old one. Never
  drop below 2 super admins, 2 GitHub org Owners, 2 Cloudflare Super Administrators, or 1
  approver outside `gcp-devops`.
- **Prerequisites:** runbook 00 done (domain, Cloudflare Email Routing, Cloud Identity, groups).
- IAM follows group changes within minutes (observed 2026-11-27: about 2 min; allow up to
  ~10 min before verifying).

## 1. Role to memberships

| Role | Groups (Admin console) | GitHub (`<ORG>`) | Other |
|---|---|---|---|
| developer | `gcp-developers` | member, team `developers` | — |
| devops | `gcp-devops` | member, teams `devops` and `iac-reviewers` if they review | address in `pam_admin_emails` |
| approver | `gcp-approvers` (never also devops/developer) | — | address in `pam_approver_emails`; see [change-approver.md](change-approver.md) |
| admin (super admin, Org Owner) | `gcp-admins`, `gcp-billing`; Admin roles → Super Admin | Owner (never a PR author, R10-3) | Cloudflare Super Administrator; address in `billing_alert_email` if they own billing alerts |

Addresses in `pam_*_emails` and `billing_alert_email` are stage 1/2 tfvars values (not in
the public repo): the admin edits the tfvars, uploads it and starts the apply with `prepare` /
`run_apply` from [runbook 04](../04-stages-via-pipeline.md), then runs the stage check
([run-checks.md](run-checks.md)): expect SUCCESS.

## 2. Join

1. Cloudflare → Email → Email Routing: add a rule `<person>@<domain>` → the person's mailbox
   (they verify the destination).
2. Admin console → Directory → Users → **Add new user** `<person>@<domain>`, recovery email =
   their own mailbox. They sign in and turn on 2-Step Verification.
3. Add the memberships of the role (section 1).
4. Verify with the person's own gcloud configuration (expect the role's permissions):

```bash
T=$(gcloud auth print-access-token --configuration=<cfg-person>)
curl -s -X POST -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project>:testIamPermissions" \
  -d '{"permissions":["resourcemanager.projects.get","run.services.get","run.services.update"]}'
# developer / devops: get permissions only; approver: none (prod folder viewer only)
```

## 3. Leave

1. Hand over first (section "Order"): the role's other holders are in place and verified.
2. Remove the memberships of the role (section 1), including GitHub teams/org and Cloudflare.
3. Verify with step 2.4 (while the account still signs in): `{}` (no permissions).
4. Admin console → Users → the user → **Suspend user**. Sign-in stops at once and existing
   tokens are revoked (verified 2026-11-27: API calls return `UNAUTHENTICATED`, gcloud refresh
   fails with `invalid_grant`). Delete the user after any data transfer; suspension alone keeps
   the account and any direct grant.
5. Remove the Email Routing rule.

## 4. Role change

Join the new role (section 2, step 3), verify, then remove the old role's memberships.

## 5. Billing and payment

Billing access is `gcp-admins` (admin) and `gcp-billing` (viewer); no person holds a direct
grant (runbook 00 section 5). The payment method and invoices belong to the payments profile,
which is managed separately (Billing → Payment settings); add the new payments user before the
old one leaves.

Next: nothing.
