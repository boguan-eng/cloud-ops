# GitHub CI WIF — Runbook

Creates one Workload Identity Federation pool + GitHub OIDC provider per env project
(nonprod, prod). Trust rules: only the GitHub org's numeric ID; nonprod = Environment
`nonprod` on `refs/heads/main`; prod = Environment `prod` on `refs/tags/v*`.
Changes here are rare (trust rule changes only). Repo onboarding does NOT need admin;
it is a devops PR (`stages/3-cicd/ar/RUNBOOK.md`).

Applied by the pipeline (first build: `runbooks/04-stages-via-pipeline.md` section 3; later
changes: `runbooks/ops/change-via-pr.md`). Nobody runs `tofu apply` for it locally.
Prerequisite: GitHub org numeric ID (`runbooks/01-github-org.md` section 4), in tfvars.

- Outputs (`wif_pool`, `wif_provider`) are at the end of the `3-cicd-wif-apply` build log; they
  contain project numbers: hand them over privately; do not commit or post publicly.
- A deleted pool is soft-deleted for 30 days; its ID cannot be reused during that time.

## Why only through the pipeline

Whoever controls the pool/provider decides which GitHub workflows can obtain a GCP
identity (including prod write). devops intentionally has no `workloadIdentityPoolAdmin`,
and pools live in each env project so nonprod IAM admins cannot affect prod trust. Changes
are applied by `iac-project-apply` only after an `iac-reviewers` approval.
