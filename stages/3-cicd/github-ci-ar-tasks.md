> **Superseded (2026-11-25):** historical record of the pre-restructure work. Current sources: [requirements](../foundation-requirements.md), [design](../foundation-design.md), [tasks](../foundation-tasks.md) and the [stage README](README.md).

# GitHub CI → Artifact Registry — Tasks

Design: `stages/3-cicd/github-ci-ar-design.md`

| # | Owner | Work | Acceptance | Depends |
|---|---|---|---|---|
| T1 | user | Create GitHub org + repos `demo-api`, `demo-web` (public, empty); admin `gcloud auth login` + `gcloud auth application-default login`; give push URLs | org/repo numeric IDs readable via GitHub API | — |
| T2 | main agent | Write runbooks `runbooks/github-org.md`, `stages/3-cicd/wif/`, `stages/3-cicd/ar/RUNBOOK.md` | user completes teams, rulesets, environments, secrets | T3 outputs for secret values |
| T3 | subagent | `stages/3-cicd/ar/` tofu module + `terraform.tfvars.example` | V0 (validate; no env values in files) | — |
| T3b | subagent | Split into `stages/3-cicd/wif/` (admin, local state) + `stages/3-cicd/ar/` (devops, GCS backend); RUNBOOK | V0 for both | T3 |
| T4 | subagent | `apps/demo-api`, `apps/demo-web` (Dockerfiles, `ci.yml`) | local `docker build` of every image passes; no hard-coded GCP values; actions pinned by SHA | — |
| T5 | main + user | admin: plan/apply `github-ci-wif`; devops: create state bucket, plan/apply `github-ci-ar` with demo-api only (V0); set secrets; push demo-api; tag | V1, V2, V3, V5, V6, V7. Direct WIF failure → fallback task to subagent | T1–T4 |
| T6 | main + user | demo-web: push before onboarding (denied), add to `repos`, apply, re-run | V4 | T5 |
| T7 | main | Scan `cloud-ops`, commit only with user approval | V8 | T6 |

## Temporary test procedure (V5 only, not permanent)

1. User: `demo-api` Environment `nonprod` → Deployment branches and tags → add branch rule `wif-deny-test`.
2. Agent pushes branch `wif-deny-test`; the `push` job is skipped by the workflow `if`, so the agent
   pushes a test-only workflow on that branch that runs auth in Environment `nonprod`;
   GCP WIF must deny (ref condition).
3. User removes the `wif-deny-test` rule; agent deletes the branch.

## Execution log

No environment values here (IDs, project numbers, emails stay in git-ignored tfvars / chat).

| Step | Who / identity | What was done | Evidence |
|---|---|---|---|
| T1 | user (GitHub UI) | Created org (Free), public empty repos `demo-api`, `demo-web`; org Actions settings; teams `developers`, `devops`; added self to `devops` via team page → Members → Add a member | GitHub API: org + repos exist, public, owner = org |
| T3/T3b | subagent | Modules `stages/3-cicd/wif/`, `stages/3-cicd/ar/`, RUNBOOK | `tofu validate` both OK; grep no env values |
| T4 | subagent | `apps/demo-api`, `apps/demo-web` | local build/run OK; actionlint clean; pins verified by `git ls-remote` |
| T5a | agent, admin account (short-lived token) | `tofu apply` `github-ci-wif` | plan 10 add / 0 change / 0 destroy; state 10 resources |
| T5b | agent, devops account | Created state bucket in nonprod project (us-central1, UBLA, PAP enforced, versioning) | `gcloud storage buckets describe` |
| T5c | agent, devops account | `tofu apply` `github-ci-ar` with `demo-api` | plan 7 add / 0 change / 0 destroy; AR repos listed, prod immutable |
| T5d | user (GitHub UI) | `demo-api` Environments `nonprod` (branch `main`) and `prod` (tag `v*`, reviewer `devops`, self-review allowed, no admin bypass) + Environment secrets | GitHub environments API matches |
| V1 | agent (git push, noreply author) | Pushed `demo-api` to `main` | run success; nonprod AR `api`,`worker` @ SHA (direct WIF push works) |
| V2 | agent tag `v0.1.0`; user approved `prod` | Promote | prod `v0.1.0` digest == nonprod SHA digest for both images |
| V6 | agent, devops account | Tried to re-point prod `v0.1.0` (gcloud + registry API) | both FAILED_PRECONDITION / MANIFEST_INVALID (tag immutability); test digest deleted |
| V3 | agent tag `v0.0.0-v3test` on unbuilt branch commit; user approved | Promote of unbuilt commit | both promote jobs failed at "Promote by digest" (MANIFEST_UNKNOWN); no `v3test` tag in either AR; project ID shown as `***` in log |
| V3 | agent tag on unbuilt commit (branch `v3-unbuilt-test`); user approved | Promote of unbuilt commit | both promote jobs failed at `crane digest`: MANIFEST_UNKNOWN; branch push triggered no workflow |
| V7 | agent with user's short-lived read-only (Actions) token | Downloaded logs of 3 runs, grep project IDs/numbers incl. partial forms | 0 hits; secrets shown as `***` |
| spike | (from V2 logs) | crane copy nonprod→prod | all blobs `mounted blob` (no download/upload through runner → no egress) |
| V5 | user added nonprod branch rule `wif-deny-test`; agent pushed test-only workflow on that branch | Auth in Environment `nonprod` from non-main ref | job ran in env (secrets available) but WIF token exchange failed: "credential is rejected by the attribute condition"; log leak grep 0; test branch deleted |
| V4 | agent pushed `demo-web` before onboarding; devops plan 5 add / 0 change, apply; agent pushed a README commit | Multi-repo onboarding | before: WIF auth OK, push denied `uploadArtifacts`; after: run success, nonprod AR `web` @ SHA |
