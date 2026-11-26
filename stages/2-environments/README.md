# Stage 2 — Environments

## What it manages

| Area | Resources |
|---|---|
| Hierarchy | Deletion-protected `prod` and `nonprod` folders under the organization, each with one billed, deletion-protected project. The projects have no default network; logging and monitoring APIs are enabled by default. |
| IAM | Additive folder grants for devops, developers, and the project-tier IaC SAs. Removes only the project creator's automatic `roles/owner` binding from each environment project. |
| Incident access | Enables the PAM API on the prod project, grants the organization PAM service agent access on the prod folder, and creates `prod-operator` there. Approvers get folder metadata access to open requests in the Console. No nonprod entitlement. |

## Concept and how it works

- Cloud Build plans the devops PR as `iac-org-plan`; after code owner review and merge to `main`, `iac-org-apply` plans again and applies. Logs stay in GCP. From zero, an admin starts the first apply trigger once. Stage 2 gives stage 3 its environment access.
- State key: `tfstate/2-environments`. Cloud Build fetches `terraform.tfvars` from `gs://<prefix>-iac-tfstate/tfvars/2-environments/`. Run `2-environments-check` after the first apply and for drift/read coverage thereafter.
- **Prod incidents only:** a devops member requests `prod-operator` with a justification. A separate approver opens the request under the prod folder in the Console and approves with a justification. A grant lasts up to four hours and expires automatically. There is no standing human revoke role; the admins handle emergencies via break-glass.
- PAM emails go to individual addresses (`pam_approver_emails`, `pam_admin_emails`): group addresses get no mail in this domain (spike S1). Until delivery is verified (spike S4), the requester also contacts an approver directly. When the incident is over, reconcile the change by PR and verify a no-diff check for each affected stage. Nonprod changes always go through PRs.

## Practical value

Separating prod from nonprod limits the blast radius. Devops can investigate both, developers can see service health, and routine writes require review. A broken pipeline need not block an urgent prod fix, but emergency privileges expire.

## GCP vs third-party

| Option | Price with source | Maintenance effort | Why chosen / not |
|---|---|---|---|
| GCP Privileged Access Manager (PAM) | PAM-specific price: not stated by the vendor (checked 2026-11-25) ([PAM overview](https://docs.cloud.google.com/iam/docs/pam-overview), [PAM API](https://docs.cloud.google.com/iam/docs/reference/pam/rest)). Google Cloud IAM has no additional per-user or per-identity cost — [IAM](https://cloud.google.com/products/iam) (read 2026-11-25) and [IAM pricing](https://cloud.google.com/iam/pricing) (read 2026-11-25); this is not a PAM-specific price. | Maintain the entitlement, approver membership and notification workaround; no separate JIT service to operate. | Chosen: folder-scoped, approved, expiring incident access with GCP audit records. |
| Third-party JIT tools | not compared | — | — |

## Permissions matrix

Role IDs omit `roles/`. Folder roles inherit into projects.

| Who | Role | Scope | Why |
|---|---|---|---|
| Admins group | Org roles from stage 0 | Organization | Bootstrap and emergency response only; no routine environment changes. |
| Approvers group | `resourcemanager.folderViewer` and named PAM approver | Prod folder | Approve incident grants only; folder metadata, not prod write access. |
| Devops group (standing) | `viewer`, `iam.workloadIdentityPoolViewer`; `cloudscheduler.jobRunner` | Both environment folders; seed project, respectively | Inspect resources and WIF pools and run checks; no standing environment write. |
| Devops member (active PAM grant only) | `prod-operator` role set: `compute.admin`, `container.admin`, `run.admin`, `dns.admin`, `cloudsql.admin`, `storage.admin`, `artifactregistry.admin`, `secretmanager.admin`, `iam.serviceAccountAdmin`, `iam.serviceAccountUser`, `logging.admin`, `monitoring.admin`, `serviceusage.serviceUsageAdmin` | Prod folder | Temporary incident work only; no nonprod elevation. |
| Developers group | `logging.viewer`, `monitoring.viewer`, `serviceusage.serviceUsageConsumer`, `run.viewer`, `cloudtrace.user`, `errorreporting.viewer` | Both environment folders | See logs, metrics and service status; `cloudtrace.user` can edit trace scopes, not traces or services. |
| `iac-org-plan` | `resourcemanager.folderViewer`, `viewer`, `iam.securityReviewer`, `privilegedaccessmanager.viewer`; `billing.viewer` | Organization; billing account, respectively | Refresh folders, projects, enabled APIs, IAM, billing info and PAM entitlements. `viewer` alone cannot read folder metadata. |
| `iac-org-apply` | `resourcemanager.organizationAdmin`, `resourcemanager.folderAdmin`, `resourcemanager.projectCreator`, `serviceusage.serviceUsageAdmin`, `privilegedaccessmanager.admin`; `billing.user` | Organization; billing account, respectively | Create and configure environments after merge, including PAM. Keeps scoped roles rather than project `owner`. |
| `iac-project-plan` | `viewer`, `iam.securityReviewer` | Both environment folders | Read stage 3 resources, enabled APIs and repo IAM. |
| `iac-project-apply` | `iam.workloadIdentityPoolAdmin`, `artifactregistry.admin`, `serviceusage.serviceUsageAdmin` | Both environment folders | Manage stage 3 providers/pools, repositories/repo IAM and APIs after merge. |
| `iac-check-runner` | `buildTriggerRunner`; `iam.serviceAccountUser` | Seed project; plan SAs only | Starts check builds, not applies. |
| PAM service agent | `privilegedaccessmanager.serviceAgent` | Prod folder | Activate and expire approved IAM grants. |

Billing viewers retain billing-account visibility only; see the [stage 0 matrix](../0-bootstrap/README.md#permissions-matrix) for seed and shared pipeline roles.

## Verify effective permissions and pitfalls

Check what a principal can actually do (read-only, nothing changes), signed in as that account:

```bash
curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H 'Content-Type: application/json' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project>:testIamPermissions" \
  -d '{"permissions":["run.services.get","run.services.update","storage.buckets.create"]}'
# returns only the permissions the caller holds
```

Pitfalls found (2026-11):
- A user account without a quota project uses gcloud's shared quota and can get HTTP 429; retry later.
- `gcloud compute instances list` (aggregated) prints `Listed 0 items` instead of an error when
  permission is missing; use `testIamPermissions` to prove a denial.
- gcloud sends the current project as quota project; without `serviceusage.services.use` calls
  fail with `USER_PROJECT_DENIED` (why developers hold `serviceusage.serviceUsageConsumer`).
- The linked billing account ID is visible to anyone with `resourcemanager.projects.get`; costs are not.
- Creating a folder or project grants the creator folderAdmin/folderEditor or `roles/owner`;
  stage 2 removes the project owner grant (`owner-cleanup.tf`).

## Related runbooks

[First applies](../../runbooks/04-stages-via-pipeline.md) · [Change by PR](../../runbooks/ops/change-via-pr.md) · [Request or approve a prod incident grant](../../runbooks/ops/approve-pam-grant.md) · [Run checks](../../runbooks/ops/run-checks.md)
