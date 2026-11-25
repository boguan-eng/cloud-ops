# Stage 1 — Organization

## What it manages

| Area | Resources |
|---|---|
| Existing Organization Policy baseline | Imports six secure-by-default constraints: `iam.disableServiceAccountKeyCreation`, `iam.disableServiceAccountKeyUpload`, `iam.automaticIamGrantsForDefaultServiceAccounts`, `storage.uniformBucketLevelAccess`, `compute.setNewProjectDefaultToZonalDNSOnly`, and `compute.restrictProtocolForwardingCreationForTypes` (`INTERNAL` only). |
| Additional constraints | Enforces `compute.skipDefaultNetworkCreation`, `storage.publicAccessPrevention`, `sql.restrictPublicIp`, and `compute.requireOsLogin`. Deferred: `compute.vmExternalIpAccess` and `gcp.resourceLocations`. `iam.allowedPolicyMemberDomains` is not used without a domain. Put any exception in the stage that owns the affected project. |
| Cost visibility | One monthly budget for the whole billing account and one Monitoring email channel in the seed project for the billing group. The default current-spend thresholds are 50%, 90%, and 100%; default billing IAM recipients remain enabled. The budget alerts; it does not cap spend. |
| IAM boundary | No standing org IAM binding for an `admins` group (removed after the second Org Owner accepted). Billing/approver group bindings are in stage 0, environment group bindings in stage 2; group membership is not an OpenTofu resource here. |

## Concept and how it works

- Devops opens a PR; Cloud Build plans as `iac-org-plan`. After devops review and merge to `main`, the approvers group authorizes the build and `iac-org-apply` plans again and applies. Logs stay in GCP. On a from-zero setup the Org Owner starts the first apply trigger once; it still requires approval.
- State key: `tfstate/1-org`. Cloud Build fetches `terraform.tfvars` from `gs://<prefix>-iac-tfstate/tfvars/1-org/`. The seed project hosts the alert channel and is the Budget API quota project.
- Run `1-org-check` after the first apply and use the daily/on-demand check for drift and plan read coverage. Budget email delivery to the consumer group is unverified (T7-12); billing viewers use the Console in the meantime.

## Practical value

One policy baseline protects even new projects; imports make changes to existing defaults visible in reviews and drift checks. A shared budget gives the team an early signal without giving cost reviewers permission to change infrastructure or billing IAM.

## GCP vs third-party

| Option | Price with source | Maintenance effort | Why chosen / not |
|---|---|---|---|
| GCP Organization Policy | Included in IAM with no additional cost per user or identity [IAM pricing](https://cloud.google.com/products/iam) (read 2026-11-25). Separate price: not stated by the vendor (checked 2026-11-25) ([Organization Policy](https://docs.cloud.google.com/organization-policy/overview)). | Review constraints and keep exceptions at project scope. | Chosen: native hierarchy enforcement rather than relying on reviewers to catch every unsafe setting. |
| Cloud Billing budgets + Monitoring email channel | Budgets and alerts have no additional charge [Cost Management](https://cloud.google.com/cost-management) (read 2026-11-25). Separate email channel price: not stated by the vendor (checked 2026-11-25) ([budget docs](https://docs.cloud.google.com/billing/docs/how-to/budgets), [Monitoring pricing](https://cloud.google.com/products/observability/pricing)). | Tune thresholds and verify delivery. | Chosen: account-wide cost visibility without a separate cost tool. |
| Consumer Google Groups | not stated by the vendor (checked 2026-11-25) | Maintain membership outside GCP; no GCP audit log for membership changes. | Current: works without a domain, but notification and domain-policy limitations remain. |
| Cloud Identity Free | No charge; initial 50-user cap for a new tenant starting at zero [editions](https://docs.cloud.google.com/identity/docs/editions) (read 2026-11-25) and [licensing](https://docs.cloud.google.com/identity/docs/how-to/how-licensing-works-for-cloud-identity) (read 2026-11-25). | Verify a domain, manage the directory and plan migration. | Adopt when a domain exists. See [identity options](identity-options.md) for the trade-offs and external IdPs. |

## Permissions matrix

Role IDs omit `roles/`.

| Who | Role | Scope | Why |
|---|---|---|---|
| Org Owners (at least two) | `cloudowner.admin` (outside IAM); retained direct break-glass roles | Organization | Own stage 0 and start this stage's first pipeline apply; no routine stage 1 writes. |
| Approvers group | `cloudbuild.builds.approver`, `cloudbuild.builds.viewer`, `logging.viewer` | Seed project | Inspect and approve the apply, not change policies or budgets. |
| Billing group | `billing.viewer`; configured email recipient | Billing account; seed Monitoring channel | Read costs and budgets; cannot edit them. |
| Devops group / `iac-check-runner` | `cloudscheduler.jobRunner` (devops); `buildTriggerRunner` + `iam.serviceAccountUser` on plan SAs only (runner) | Seed project and plan SAs | Devops reviews via PR and can run `1-org-check` without write access or SA impersonation. |
| `iac-org-plan` | `orgpolicy.policyViewer`, `iam.securityReviewer`; `billing.viewer`; `monitoring.viewer`, `serviceusage.serviceUsageConsumer` | Organization; billing account; seed project, respectively | Refresh policy, org IAM where applicable, budget and channel without editing them. |
| `iac-org-apply` | `orgpolicy.policyAdmin`; `billing.costsManager`; `monitoring.notificationChannelEditor`, `serviceusage.serviceUsageConsumer` | Organization; billing account; seed project, respectively | Import/manage policies and configure the budget and channel after approval. No billing IAM admin. |

The [stage 0 matrix](../0-bootstrap/README.md#permissions-matrix) lists the shared state, builder and logging roles. Developers and project-tier SAs have no stage 1 duties.

## Related runbooks

[First applies](../../runbooks/04-stages-via-pipeline.md) · [Change by PR](../../runbooks/ops/change-via-pr.md) · [Approve an apply](../../runbooks/ops/approve-apply.md) · [Run checks](../../runbooks/ops/run-checks.md) · [Manage approvers](../../runbooks/ops/change-approver.md)
