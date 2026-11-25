# Foundation (Chapter 1) — Design

Requirements: `stages/foundation-requirements.md`.

## Verified Facts (2026-11-24, official docs / read-only queries)

| Topic | Fact | Design impact |
|---|---|---|
| Org policies (live) | Enforced: SA key creation/upload disabled, uniform bucket access, no auto IAM grants for default SAs, protocol forwarding restriction, zonal DNS. `iam.allowedPolicyMemberDomains` NOT enforced | Gmail principals work; domain restriction unavailable without a domain |
| PAM | Base flow (single-level approval) needs no SCC tier; scopes org/folder/project; max 7 days; groups as requesters/approvers; no-approval option. Pricing NOT FOUND; consumer accounts not mentioned; email notifications only to Cloud Identity users | Spike (T1) before adoption |
| IAM Conditions | `request.time < timestamp("...")` expiring grants; not allowed on legacy basic roles | Fallback for elevation |
| Cloud Build | PR comment control (`COMMENTS_ENABLED_FOR_EXTERNAL_CONTRIBUTORS_ONLY`); logs not sent to GitHub by default; approval via `roles/cloudbuild.builds.approver`, `ApproveBuild` in Admin Activity audit log; user-specified SA requires `CLOUD_LOGGING_ONLY` or user bucket; creator needs `actAs` on the SA | Fits pipeline (a) |
| Cloud Build price | e2-standard-2 default pool $0.006/min; 2,500 free min/month per billing account (promotional) | ~$0/month |
| Infrastructure Manager | Terraform ≤1.5.7 free, ≥1.16.5 paid by RUM; OpenTofu not mentioned | Not adopted |
| OpenTofu image | Since 1.10 official image cannot be used directly; build own image (copy binary from `-minimal`) | Builder image in seed AR |
| Viewer roles | `run.viewer`, `errorreporting.viewer` read-only; `cloudtrace.user` reads traces but can edit trace scopes | Accepted, documented |
| Billing | `billing.viewer` reads costs, cannot create budgets; budget alerts to any email via Monitoring channels | Budgets by IaC |
| GitHub Free | Protected branches only for public repos | `cloud-ops` stays public |

## Stages

| Stage | Content | Applied by | State |
|---|---|---|---|
| `0-bootstrap` | seed project, state bucket, builder AR + image, IaC SAs, Cloud Build connection + triggers | Human, once (runbook 02/03) | local → migrated to GCS after creation |
| `1-org` | org-level IAM, org policies, budget + alert channel | pipeline, org tier SA | GCS `tfstate/1-org` |
| `2-environments` | prod/nonprod folders, projects, folder IAM for groups | pipeline, org tier SA | GCS `tfstate/2-environments` |
| `3-cicd/wif`, `3-cicd/ar` | GitHub WIF pools, per-repo AR | pipeline, project tier SA | GCS `tfstate/3-cicd-wif`, `tfstate/3-cicd-ar` |

Rebuild instead of migration (decided 2026-11-24): stages 1–3 were first applied by hand
before stage 0 existed. Instead of splitting/migrating that state, the pipeline builds stages
1–3 from zero (this also verifies the documented from-zero path), then the legacy resources are
deleted. Facts: a deleted project's ID can never be reused (new projects use
`project_id_suffix`); soft-deleted projects count against project quota for 30 days.
Order to limit risk: rename legacy folders → pipeline creates new stages → switch demo apps →
delete legacy projects/folders. If project creation hits quota, nothing legacy is lost yet.
Stage 2 grants the project-tier IaC SAs their folder roles, so stage 3 needs no human apply.
One PR per stage, in order (all apply triggers would otherwise start at once).

## Seed Project

```
Org
├─ seed project (directly under org)
│  ├─ GCS state bucket (versioning, uniform access, public access prevention)
│  │    tfstate/<stage>/ , tfvars/<stage>/terraform.tfvars
│  ├─ AR repo: tofu builder image
│  ├─ SA iac-org-plan / iac-org-apply        (stages 1, 2)
│  ├─ SA iac-project-plan / iac-project-apply (stage 3)
│  └─ Cloud Build 2nd-gen connection → GitHub repo cloud-ops
│       per stage (includedFiles = stages/<stage>/**):
│         PR trigger   → plan  (plan SA, -lock=false), comment control: external contributors
│         main trigger → apply (apply SA), approval required
└─ prod / nonprod folders (2-environments)
```

| SA | Roles |
|---|---|
| iac-org-plan | org: `viewer`, `resourcemanager.folderViewer`, `iam.securityReviewer`, `orgpolicy.policyViewer`, `privilegedaccessmanager.viewer`; billing: `billing.viewer`; bucket read (see Plan SA Read Coverage) |
| iac-org-apply | org: folder admin, project creator, org IAM admin, org policy admin; billing account user/costs manager; bucket write |
| iac-project-plan | prod/nonprod folders: `viewer`, `iam.securityReviewer`; bucket read |
| iac-project-apply | prod/nonprod projects: WIF pool admin, AR admin, project IAM admin, service usage admin; bucket write |

Seed project IAM (humans): devops = Cloud Build viewer + logging viewer (to read plans);
approver = Cloud Build approver + viewer; nobody has `actAs` on IaC SAs except via Org Owner.
Build logs: `CLOUD_LOGGING_ONLY`; `includeBuildLogs` unset (no logs on GitHub).

### Plan SA Read Coverage

A plan refreshes every resource in state, so each plan SA needs read access to every managed
resource type. Gap found 2026-11-24: org `roles/viewer` lacks `resourcemanager.folders.get`, so
the first stage 2 change PR failed (the first stage 2 plan only created folders, so nothing was
read). Role existence was verified in T3, coverage was not; T6 verified zero-diff only as the
Org Owner, whose access is wider than the plan SA's.

| Stage | Read in plan | Permission source (plan SA) |
|---|---|---|
| 1-org | org IAM policy; budgets, notification channels (T7-5) | `iam.securityReviewer`; `billing.viewer`; `monitoring.viewer` on seed |
| 2-environments | folders; projects + billing info; project services; folder/project IAM; PAM entitlement | `resourcemanager.folderViewer`; `viewer`; `viewer`; `iam.securityReviewer`; `privilegedaccessmanager.viewer` |
| 3-cicd/wif | project services; WIF pools/providers | folder `viewer` (inherited) |
| 3-cicd/ar | project services; AR repos + repo IAM | folder `viewer`; `iam.securityReviewer` |

Control: manual `<stage>-check` triggers (stage 0) run `tofu plan -detailed-exitcode` on `main`
as the plan SA; the build fails on any error or diff. Run each after a stage's first apply
(runbook 04) and to detect drift. PR plan triggers cannot be run by hand.

## Pipeline Flow

1. PR touching `stages/<stage>/` → plan trigger → plan visible in Cloud Build (GCP only);
   GitHub check shows status + build ID only.
2. Branch protection on `main`: PR review by devops required.
3. Merge → apply trigger → waits for approval → approver approves (audit logged) → `tofu apply`.
4. tfvars fetched from `gs://<bucket>/tfvars/<stage>/` at build time.

Risk: HCL in a PR can execute code during plan (e.g. `external` data source) with the plan SA.
Controls: repo write access = devops only; external PRs need `/gcbrun` by a writer after review;
plan SAs are read-only.

## Permission Changes (T7, decided 2026-11-24)

Facts (official docs, 2026-11-24): Organization Owner of a standalone org is added only in the
Console (Organization details → invite, accept within 30 days); PAM supports org/folder/project
entitlements, groups as requesters/approvers, 30 min–7 days; the project creator is granted
`roles/owner` (removed with `google_project_iam_member_remove`); budgets need
`billing.costsManager` (apply SA has it); email alerts need Monitoring email channels (≤5) in a
project with `billingbudgets` API on the quota project; billing-account IAM needs
`billing.admin` (not given to any SA).

| Change | Where | Applied by |
|---|---|---|
| Second Org Owner (dedicated break-glass Gmail) | Console | Org Owner (manual) |
| `<prefix>-gcp-billing` group → `billing.viewer` on the billing account | stage 0 | Org Owner (local) |
| Seed: enable `billingbudgets`, `monitoring` APIs; `iac-org-apply` → `monitoring.notificationChannelEditor`, `serviceusage.serviceUsageConsumer`; `iac-org-plan` → `monitoring.viewer`, `serviceusage.serviceUsageConsumer` | stage 0 | Org Owner (local) |
| devops on prod folder: `viewer` only; PAM entitlement `prod-operator` on the prod folder (previous devops role set, max 4h, requester devops group, approver approvers group, justification required); PAM service agent role on the prod folder | stage 2 | pipeline |
| developers (both folders): + `run.viewer`, `cloudtrace.user` (accepted: can edit trace scopes, cannot change traces or services), `errorreporting.viewer` | stage 2 | pipeline |
| devops on nonprod: + `iam.workloadIdentityPoolViewer` | stage 2 | pipeline |
| Remove `roles/owner` of `iac-org-apply` on env projects | stage 2 | pipeline |
| Budget on the billing account (TWD, alerts 50/90/100 %), email channel to the billing group, channel in the seed project | stage 1 | pipeline |
| Remove `admins` group org roles (after the second Org Owner accepted) | stage 1 | pipeline |

Kept: the Org Owner user's direct, manually granted org roles (break-glass; Org Owner is
allowed standing access by acceptance 1). Lockout prevention: the Org Owner can always restore
Organization Administrator from the Organization details page.

PAM approval path (gap found in T7-7, 2026-11-25): the design said who approves, not how an
approver learns of a request or where they act. With consumer Google Groups, PAM sent no email
(docs: it auto-notifies Cloud Identity users/groups only), and the approver could not open the
grant in the Console ("You need additional access to the folder"). Fix in stage 2:
`approver_email_recipients` = approvers group, `admin_email_recipients` = devops group (notified
when a grant becomes active), approvers group → `resourcemanager.folderViewer` on the prod
folder (folder metadata only; Console chosen over CLI-only approval for usability). Normal path:
request → email to approvers → link → approve in the Console (`runbooks/ops/approve-pam-grant.md`).
Revoke (same gap, 2026-11-25): only `roles/privilegedaccessmanager.admin` holds
`privilegedaccessmanager.grants.revoke`, and the Org Owner was denied. It also edits
entitlements, so it is granted on the prod folder to the Org Owner only (`pam_admin_principals`;
no added risk, the Org Owner can grant it to themselves), never to approvers (they could make
themselves eligible).

Acceptance 5 uses `selfuse-operator` (devops) with a PAM grant, ended early by revoke.
Acceptance 6 uses the approver account temporarily added to the developers group (removed
after the test: an approver must not stay in developers). Acceptance 7 by IAM inspection.

## Documentation

- `README.md`: index (chapter/scenario → stage/runbook), role matrix.
- `stages/<stage>/README.md`: concept, how it works, practical value, GCP vs third-party
  (price with source/date, maintenance), permissions.
- `runbooks/`: stage-0 method A, method B, elevation, onboarding repo/person, offboarding.
- `docs/identity-options.md` → placed at `stages/1-org/identity-options.md`: no domain /
  domain + Cloud Identity Free / Workforce Identity Federation.
- `examples/github-private-pipeline/`: b1, marked unverified.

## Non-functional

- Cost ≈ $0/month (Cloud Build free tier, cents for GCS/AR).
- Maintenance: second CI tool (Cloud Build); builder image OpenTofu upgrades.
