# GitHub CI WIF — Runbook (org admin)

Creates one Workload Identity Federation pool + GitHub OIDC provider per env project
(nonprod, prod). Trust rules: only the GitHub org's numeric ID; nonprod = Environment
`nonprod` on `refs/heads/main`; prod = Environment `prod` on `refs/tags/v*`.
Changes here are rare (trust rule changes only). Repo onboarding does NOT need admin;
it is done by devops in `github-ci-ar/RUNBOOK.md`.

Never write real values into tracked files. Session variables only:

```bash
export ADMIN_ACCOUNT=...   # org admin gcloud account (member of the admins group)
```

Authentication: no ADC file. tofu uses a short-lived token (about 1 hour; re-export on 401).

## Apply

Prerequisite: GitHub org numeric ID (`github-org/RUNBOOK.md` step 4).

```bash
cd github-ci-wif
cp terraform.tfvars.example terraform.tfvars   # real values; git-ignored
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account="$ADMIN_ACCOUNT")
tofu init
tofu plan          # review: first apply = only creates
tofu apply
tofu output wif_pool       # → devops: input wif_pool of github-ci-ar
tofu output wif_provider   # → devops: GitHub secret GCP_WIF_PROVIDER
unset GOOGLE_OAUTH_ACCESS_TOKEN
```

- State is local and git-ignored (`terraform.tfstate`); back it up privately.
- Outputs contain project numbers: hand them over privately; do not commit or post publicly.
- A deleted pool is soft-deleted for 30 days; its ID cannot be reused during that time.

## Why admin only

Whoever controls the pool/provider decides which GitHub workflows can obtain a GCP
identity (including prod write). devops intentionally has no `workloadIdentityPoolAdmin`,
and pools live in each env project so nonprod IAM admins cannot affect prod trust.
