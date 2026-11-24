# Foundation (Chapter 1) — Requirements

Related (moved into `stages/`): `stages/2-environments/gcp-iam-bootstrap-*.md`, `stages/3-cicd/github-ci-ar-*.md`.
Source of topics: personal GCP DevOps exam notes, lesson 1 (hierarchy, IAM, service accounts)
and the bootstrap part of lesson 2 (IaC). Only practical items are in scope.

## Goal

Turn the existing hand-applied setup into a foundation that works the way a real small team
operates: one human-run bootstrap (stage 0), after which all infrastructure changes go through a
reviewed and approved pipeline. Define realistic personas and permissions, and record the
concepts, trade-offs (GCP vs third-party, price, maintenance) and permission matrix per stage.

## Context / Constraints

- The GCP organization is a **standalone organization** (auto-created for a Google-account
  Free Trial sign-up; no Cloud Identity, no domain). Verified 2026-11-24: display name is not a
  domain, no directory customer ID. Ref: Resource Manager "Set up standalone organizations".
- Organization Owner (`roles/cloudowner.admin`) is managed outside IAM (Organization details page).
- Members use personal Google accounts; groups are consumer Google Groups.
- `cloud-ops` is a **public** repo: no environment values (org/project IDs, numbers, emails,
  billing account) are committed; plan/apply output must not appear in public logs.
- GitHub org is on the Free plan. Fact (GitHub docs, 2026-11-24): on Free/Pro/Team, environment
  required reviewers are available only for public repos; private repos need Enterprise.
- Assumed scale: 1–2 org owners, 1–2 devops, 3–10 developers.
- IaC tool: OpenTofu.

## Personas and Permissions

| Persona | Permissions | Usage |
|---|---|---|
| Org Owner (non-technical, a) | `cloudowner.admin`; at least 2 owners | Break-glass; may run stage 0 (method A) |
| Approver (non-technical, b) | Cloud Build Approver on the seed project only | Approves infra apply in the Console |
| Billing viewer (non-technical, c) | `billing.viewer` on the billing account; budget alert recipient | Reads cost |
| devops | nonprod: operate; prod: read-only by default + just-in-time elevation (mechanism chosen in design after verification) | Infra changes only via PR |
| developers | existing logs/monitoring read + service-status viewer roles (e.g. Cloud Run, Trace, Error Reporting) | Read-only |
| IaC plan SA | Read-only | Runs `plan` on PR |
| IaC apply SA | Folder/project creation, IAM, etc. | Runs `apply` only after merge to `main` and approval |

## Scope

1. **Stage 0 bootstrap**: seed project, state bucket (versioning), plan SA and apply SA,
   Cloud Build ↔ GitHub connection and triggers (PR → plan; `main` → apply with approval).
   Environment values (tfvars) are stored in the seed project, not in the repo.
   Runbooks for both execution methods:
   - A: Org Owner runs it in Cloud Shell.
   - B: Org Owner grants a devops member a time-bound elevation; devops runs it; grant removed.
2. **Pipeline**:
   - Primary: (a) Cloud Build running OpenTofu; logs stay in GCP.
   - Example only (b1): GitHub Actions in a private repo (Team plan, PR review as approval gate),
     under `examples/`, marked **unverified**, not wired to live state or identities.
   - Infrastructure Manager: recorded as evaluated and not adopted, with reasons.
3. **Restructure**: move `gcp-iam-bootstrap`, `github-ci-wif`, `github-ci-ar` into the `stages/`
   layout; migrate local state to the GCS backend.
4. **Permissions to real operating model**: devops prod access → read-only + JIT elevation;
   developers get service-status viewer roles.
5. **Org Policy baseline**: record which secure-by-default policies the org already enforces,
   then decide which to add.
6. **Identity options document**: no domain (current), domain + Cloud Identity Free
   (requires a new org and project move — inferred: claiming a standalone org only works for orgs
   created by users of that domain), Workforce Identity Federation (needs external IdP).
7. **Per-stage README**: concept, how it works, practical value, GCP vs third-party
   (price with source and date, maintenance), permission matrix.

## Layout

```
cloud-ops/
├─ README.md              # index: chapter/scenario → stage/runbook; role matrix
├─ stages/
│  ├─ foundation-{requirements,design,tasks}.md
│  ├─ 0-bootstrap/        # human, one-time apply
│  ├─ 1-org/              # org policy, group IAM, elevation
│  ├─ 2-environments/     # prod/nonprod folders and projects
│  └─ 3-cicd/             # app WIF and Artifact Registry
├─ runbooks/              # scenario procedures
├─ examples/              # unverified examples (b1)
└─ apps/                  # unchanged (git-ignored)
```

## Known Risks (handled in design)

- The apply SA is highly privileged: only the Cloud Build trigger may use it, only from `main`,
  only after approval.
- Installing the Cloud Build GitHub App requires a GitHub org owner (manual stage 0 step).
- Public repo + Cloud Build triggers: builds from untrusted PRs must not run without control.

## Acceptance (requirement level)

1. Stage 0 runbook (A and B) exists; after stage 0, no human holds standing org-level write
   roles except Org Owners.
2. A PR to `cloud-ops` produces a plan in GCP only. GitHub shows no plan/log content, org ID,
   billing account, project number or email. Accepted exception (2026-11-24): Cloud Build names
   its GitHub checks `<trigger> (<seed project ID>)`, so the seed project ID and trigger/build
   UUIDs are public (not configurable; the ID's prefix equals the public GitHub org name).
   Every PR is checked for anything beyond this (`runbooks/ops/change-via-pr.md`).
3. Merge to `main` does not apply until an approver approves; approval is in audit logs.
4. Restructure and state migration: `tofu plan` shows 0 changes before and after for every stage.
5. devops cannot modify prod without elevation; with elevation it can; elevation expires.
6. developers can view Cloud Run service status, logs, metrics; cannot modify.
7. Plan SA cannot write; apply SA cannot be used outside the Cloud Build trigger.
8. No environment-specific values committed.
