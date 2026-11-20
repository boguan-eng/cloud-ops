# GitHub CI → Artifact Registry — Design

Requirements: `docs/github-ci-ar-requirements.md`

## 1. GCP: two OpenTofu root modules

Split by who applies and how often. Project IDs are inputs (no cross-state reads).

| Module | Applied by | Changes | State |
|---|---|---|---|
| `github-ci-wif/` | org admin | rarely (trust rules) | local, git-ignored |
| `github-ci-ar/` | devops | each repo onboarding | GCS backend (shared by devops members) |

Why split: devops cannot read WIF pools (verified: `workloadIdentityPools.list` denied), so a
single state would force admin for every onboarding. devops already holds
`artifactregistry.admin` (incl. `repositories.create`, `setIamPolicy`, verified), so
onboarding by devops grants it nothing new.

### 1a. `github-ci-wif/` (admin)

Inputs: `nonprod_project_id`, `prod_project_id`, `github_org_id` (numeric).

Per env in `{nonprod, prod}`:
- `google_project_service`: `iam`, `iamcredentials`, `sts` (`disable_on_destroy = false`).
- `google_iam_workload_identity_pool` `github` in the env project.
  One pool per env: devops has `projectIamAdmin` on nonprod and could grant itself pool admin;
  a single pool in nonprod would let it forge a prod-capable identity.
- `google_iam_workload_identity_pool_provider` `github` (OIDC, issuer
  `https://token.actions.githubusercontent.com`):
  - mapping: `google.subject = assertion.sub`, `attribute.repository_id`,
    `attribute.repository_owner_id`, `attribute.environment`, `attribute.ref`.
  - condition nonprod: `assertion.repository_owner_id == "<org_id>" && assertion.environment == "nonprod" && assertion.ref == "refs/heads/main"`
  - condition prod: `assertion.repository_owner_id == "<org_id>" && assertion.environment == "prod" && assertion.ref.startsWith("refs/tags/v")`

Outputs (handed to devops, not committed): `wif_pool` (env => pool resource name),
`wif_provider` (env => provider resource name).

### 1b. `github-ci-ar/` (devops)

Inputs: `nonprod_project_id`, `prod_project_id`, `region` (default `us-central1`),
`wif_pool` (map: nonprod/prod => pool resource name from 1a),
`repos` (map: repo name => numeric repo ID; name `^[a-z]([a-z0-9-]*[a-z0-9])?$`).

- Backend: `backend "gcs" { prefix = "github-ci-ar" }`; bucket passed with
  `-backend-config=backend.hcl` (git-ignored; `backend.hcl.example` committed).
- State bucket (created once by devops with gcloud, see RUNBOOK): in nonprod project,
  `us-central1`, uniform bucket-level access, public access prevention, object versioning.
- `google_project_service`: `artifactregistry` on both projects.
- `google_artifact_registry_repository` per env per repo: ID = repo name, DOCKER,
  `location = region`; prod: `docker_config { immutable_tags = true }`.
- IAM (additive `google_artifact_registry_repository_iam_member` only), member
  `principalSet://iam.googleapis.com/<wif_pool[env]>/attribute.repository_id/<repo_id>`:

| Pool | AR repository | Role |
|---|---|---|
| nonprod | nonprod `<repo>` | `roles/artifactregistry.writer` |
| prod | prod `<repo>` | `roles/artifactregistry.writer` |
| prod | nonprod `<repo>` | `roles/artifactregistry.reader` (promote source) |

Outputs: `ar_repo_path` (env => repo => `<region>-docker.pkg.dev/<project>/<repo>`).

### Auth for tofu (no ADC file)

`GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account=<acct>) tofu ...`
(admin account for 1a, devops member for 1b; also used by the GCS backend).

## 2. App repos (`apps/demo-api`, `apps/demo-web`)

Each is its own git repo (default branch `main`); `apps/` is git-ignored in `cloud-ops`.

```
apps/<repo>/
├─ images/<image>/Dockerfile (+ minimal source)   # one dir per image
├─ .github/workflows/ci.yml
└─ README.md
```

demo-api: images `api`, `worker`. demo-web: image `web`. Minimal, tiny images.

### Workflow `ci.yml`

- Triggers: `pull_request`; `push` branches `[main]`, tags `['v*']`.
- Top-level `permissions: contents: read`. `id-token: write` only on push/promote jobs.
- No `pull_request_target`. All third-party actions pinned to full commit SHA (comment with version).
- Jobs:
  1. `discover`: output JSON list of `images/*/` dir names (matrix source).
  2. `build` (PR only): matrix; `docker build`, no GCP auth.
  3. `push` (push to `refs/heads/main`): `environment: nonprod`; matrix; mask → auth →
     `gcloud auth configure-docker <host>` → build → push `<AR>/<image>:<GITHUB_SHA>`.
  4. `promote` (push of `refs/tags/v*`): `environment: prod`; matrix; mask → auth →
     configure-docker → `crane digest <SRC>/<image>:<GITHUB_SHA>` (fails if missing) →
     `crane copy <SRC>/<image>@<digest> <AR>/<image>:<GITHUB_REF_NAME>`.
- Auth: `google-github-actions/auth` with `workload_identity_provider` only (direct WIF,
  no service account), then `google-github-actions/setup-gcloud`.
- Environment secrets (set per GitHub Environment, never in files):

| Environment | Secret | Value |
|---|---|---|
| nonprod | `GCP_WIF_PROVIDER` | nonprod `wif_provider` |
| nonprod | `GCP_AR_REPO` | nonprod `ar_repo_path` of this repo |
| prod | `GCP_WIF_PROVIDER` | prod `wif_provider` |
| prod | `GCP_AR_REPO` | prod `ar_repo_path` of this repo |
| prod | `GCP_AR_REPO_SOURCE` | nonprod `ar_repo_path` of this repo |

- Masking: first step of push/promote jobs derives project number (field 2 of provider path)
  and project ID(s) (field 2 of AR paths) and emits `::add-mask::` for each; secrets are
  masked by GitHub automatically.

## 3. GitHub manual setup

Permanent runbooks (next to the code, by operator role):

| Runbook | Operator | Content |
|---|---|---|
| `github-org/RUNBOOK.md` | GitHub org owner | org, Actions settings, teams, org ID |
| `github-ci-wif/RUNBOOK.md` | GCP org admin | WIF pools/providers, output hand-off |
| `github-ci-ar/RUNBOOK.md` | devops | state bucket, AR apply, repo onboarding (GCP + GitHub environments/secrets/rulesets), release |

`docs/` holds only this implementation's requirements/design/tasks.

## 4. Fallback (only if spike fails)

If direct WIF cannot push or promote: per env per repo service account, WIF principalSet
gets `roles/iam.workloadIdentityUser` on it, AR roles move to the SA, workflow passes
`service_account` to the auth action. Same pools/conditions.

## 5. Operator identities

Admin is used only where required; everything else uses role accounts.

| Operation | Identity | Reason |
|---|---|---|
| `tofu apply` `github-ci-wif/` | org admin | devops lacks `workloadIdentityPoolAdmin` by design (pool decides who can write prod) |
| `tofu apply` `github-ci-ar/` (onboarding) | devops group member | `artifactregistry.admin` on both folders; no new privilege |
| Read AR images / digests during verification | devops group member | `artifactregistry.admin` on both folders |
| Push / promote images | CI (WIF) | no human identity |

On a shared machine select the identity per command with `--account=<acct>` (gcloud) and
`GOOGLE_OAUTH_ACCESS_TOKEN` (tofu). No ADC file is kept.

## 6. Verification

| # | Check | Requirement |
|---|---|---|
| V0 | `tofu validate` both modules; each `plan` only creates | protect existing resources |
| V1 | main push of demo-api → nonprod AR has `api`,`worker` @ SHA | 1 |
| V2 | tag `v*` → prod digest == nonprod digest | 2 |
| V3 | tag on commit not built on main → promote fails at `crane digest` | 3 |
| V4 | demo-web not onboarded → push denied; onboard + apply → succeeds | 4 |
| V5 | nonprod env temporarily allows branch `wif-deny-test`; push there → auth denied by WIF; revert env rule | 5 |
| V6 | devops (artifactregistry.admin) tries to point prod `v*` tag at another digest (gcloud tags add + registry PUT) → denied; test digest deleted | 6 |
| V7 | download run logs, grep project ID and number → 0 hits | 7 |
| V8 | grep tracked files of `cloud-ops` for env values → 0 hits | 8 |

## Notes

- Deleted WIF pools are soft-deleted for 30 days; their IDs cannot be reused meanwhile.
- AR cleanup policies and vulnerability scanning are out of scope.
