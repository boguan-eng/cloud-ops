# Runbooks — Start Here

First-time setup is linear: do the numbered runbooks in order. Each one starts with
*who / which account / prerequisites* and ends with *verification* and *next*.
Never commit real values (IDs, emails); fill them in shell variables or git-ignored files.

```
 01 GitHub org            02 Stage 0 bootstrap        03 cloud-ops repo + pipeline      04 Stages 1–3 (last
 (GitHub org owner)  ──▶  (GCP admin, or         ──▶  (GitHub org owner +          ──▶  bootstrap step, once)
                           devops w/ temp grant)       GCP admin)                        (admin starts,
 org, 2FA, teams          seed project, state         push repo, ruleset,              no approval step)
                          bucket, IaC SAs,            Cloud Build connection,          org IAM, folders,
                          builder image               triggers, check jobs,            projects, WIF, AR
                                                      required checks                  via apply triggers
```

| # | Runbook | Who (account) | Result |
|---|---|---|---|
| 00 | [00-identity.md](00-identity.md) | Domain owner / first super admin | Mail forwarding, Cloud Identity, accounts, groups, organization, bootstrap roles to `gcp-admins` |
| 01 | [01-github-org.md](01-github-org.md) | GitHub org owner | Org with 2FA, owner-only repo creation, teams `devops` / `iac-reviewers` / `developers` |
| 02 | [02-stage0-bootstrap.md](02-stage0-bootstrap.md) | GCP admin (method A) or a devops member with temporary elevation (method B) | Seed project, state bucket, builder image, 4 IaC service accounts |
| 03 | [03-cloud-ops-repo.md](03-cloud-ops-repo.md) | GitHub org owner (browser) + GCP admin (CLI) | Public `cloud-ops` with protected `main`; Cloud Build connection; 12 triggers, check runner SA, 4 daily check jobs |
| 04 | [04-stages-via-pipeline.md](04-stages-via-pipeline.md) | GCP admin (CLI) | Org IAM, env folders/projects, WIF, AR built by the pipeline; last bootstrap step, run once. Afterwards all changes go through PR → plan → code owner review → merge → apply |

After setup, all changes are pull requests to `cloud-ops`; the admins only operate stage 0,
tfvars-only changes and break-glass. Day-to-day runbooks:

| Runbook | Who | Purpose |
|---|---|---|
| [ops/change-via-pr.md](ops/change-via-pr.md) | devops (author) + `iac-reviewers` (reviewer) | Branch, PR, code owner review (Org Owner emergency bypass only), merge → apply |
| [ops/change-approver.md](ops/change-approver.md) | admin | Add or remove PAM approvers |
| [ops/run-checks.md](ops/run-checks.md) | devops (or admin) | Daily/on-demand `<stage>-check` for drift and plan-SA read coverage |
| [ops/approve-pam-grant.md](ops/approve-pam-grant.md) | devops (requester) + approver | Incident-only prod write elevation (PAM), then reconcile by PR |

Per-stage details are in `stages/<stage>/README.md` (stage 3 app setup: `stages/3-cicd/{wif,ar}/RUNBOOK.md`).

## Roles at a glance

| Persona | GitHub | GCP |
|---|---|---|
| Admin (`admin1`/`admin2`, super admin, break-glass) | org Owner | Through `gcp-admins`: Organization Administrator, Project Creator, seed owner, Billing Account Administrator; runs stage 0 |
| PAM approver (member of `gcp-approvers`) | none | PAM approver on the prod folder (incident access only) |
| IaC reviewer | `iac-reviewers` team (code owner) | none needed; the review releases the apply |
| Billing viewer (non-technical) | none | Billing Account Viewer |
| devops | `devops` team (Write on `cloud-ops`) | read-only on prod and nonprod (no standing write); runs checks; prod PAM elevation for incidents only |
| developers | `developers` team (app repos) | logs / monitoring / service status, read-only |
