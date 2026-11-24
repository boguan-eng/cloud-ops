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
| `0-bootstrap` | seed project, state bucket, builder AR + image, IaC SAs, Cloud Build connection + triggers | Human, once (runbook A or B) | local → migrated to GCS after creation |
| `1-org` | org-level IAM, org policies, billing IAM + budget, elevation (PAM or fallback) | pipeline, org tier SA | GCS `tfstate/1-org` |
| `2-environments` | prod/nonprod folders, projects, folder IAM for groups | pipeline, org tier SA | GCS `tfstate/2-environments` |
| `3-cicd/wif`, `3-cicd/ar` | GitHub WIF pools, per-repo AR | pipeline, project tier SA | GCS `tfstate/3-cicd-wif`, `tfstate/3-cicd-ar` |

`gcp-iam-bootstrap` is split into `1-org` (org-level IAM) and `2-environments` (folders, projects,
folder IAM) by copying the local state and `tofu state rm` on each side.

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
| iac-org-plan | org: read roles (viewer-level, IAM/org policy/billing read); bucket read |
| iac-org-apply | org: folder admin, project creator, org IAM admin, org policy admin; billing account user/costs manager; bucket write |
| iac-project-plan | prod/nonprod projects: read roles; bucket read |
| iac-project-apply | prod/nonprod projects: WIF pool admin, AR admin, project IAM admin, service usage admin; bucket write |

Seed project IAM (humans): devops = Cloud Build viewer + logging viewer (to read plans);
approver = Cloud Build approver + viewer; nobody has `actAs` on IaC SAs except via Org Owner.
Build logs: `CLOUD_LOGGING_ONLY`; `includeBuildLogs` unset (no logs on GitHub).

## Pipeline Flow

1. PR touching `stages/<stage>/` → plan trigger → plan visible in Cloud Build (GCP only);
   GitHub check shows status + build ID only.
2. Branch protection on `main`: PR review by devops required.
3. Merge → apply trigger → waits for approval → approver approves (audit logged) → `tofu apply`.
4. tfvars fetched from `gs://<bucket>/tfvars/<stage>/` at build time.

Risk: HCL in a PR can execute code during plan (e.g. `external` data source) with the plan SA.
Controls: repo write access = devops only; external PRs need `/gcbrun` by a writer after review;
plan SAs are read-only.

## Permission Changes (via pipeline, after migration)

- devops on prod: viewer; elevation entitlement "prod-operator" (roles from current devops set),
  requester = devops group, approver = approver persona, max 4h.
  Mechanism: PAM (T1 passed 2026-11-24). Expiring IAM condition kept only as documented fallback.
- developers: + `run.viewer`, `cloudtrace.user`, `errorreporting.viewer`.
- billing viewer: `billing.viewer` on billing account; budget + alert channel by IaC.
- `admins` group: org roles removed after a second Org Owner exists.
- Lockout prevention: human permissions are removed only after pipeline zero-diff is verified;
  Org Owner can always restore Organization Administrator.

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
