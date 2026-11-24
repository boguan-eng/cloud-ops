# GitHub CI → Artifact Registry — Runbook (devops)

Per-repo setup so a GitHub repo's Actions can push images to nonprod AR (on `main`) and
promote them to prod AR (on `v*` tags). Prerequisites: GitHub org (`runbooks/01-github-org.md`)
and WIF pools (`stages/3-cicd/wif/RUNBOOK.md`, outputs handed over by the admin).

Never write real values into tracked files. Session variables only:

```bash
export DEVOPS_ACCOUNT=...    # devops group member gcloud account
export NONPROD_PROJECT=...   # nonprod project ID
export STATE_BUCKET=...      # GCS bucket for tofu state (globally unique)
export ORG=...               # GitHub org name
export REPO=...              # GitHub repo name (also the AR repository ID)
```

Authentication: no ADC file. tofu (incl. the `gcs` backend, which reads
`GOOGLE_OAUTH_ACCESS_TOKEN`) uses a short-lived token (about 1 hour; re-export on 401).

## 1. State bucket (one time)

```bash
gcloud storage buckets create "gs://$STATE_BUCKET" \
  --project="$NONPROD_PROJECT" --location=us-central1 \
  --uniform-bucket-level-access --public-access-prevention \
  --account="$DEVOPS_ACCOUNT"
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning --account="$DEVOPS_ACCOUNT"
```

## 2. First apply

```bash
cd stages/3-cicd/ar
cp backend.hcl.example backend.hcl             # bucket = "$STATE_BUCKET"; git-ignored
cp terraform.tfvars.example terraform.tfvars   # projects, wif_pool (from admin), repos; git-ignored
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token --account="$DEVOPS_ACCOUNT")
tofu init -backend-config=backend.hcl
tofu plan
tofu apply
tofu output ar_repo_path
unset GOOGLE_OAUTH_ACCESS_TOKEN
```

## 3. Onboard a repo

Order matters: Environments + secrets must exist before the first push to `main`
(it triggers the `push` job); rulesets come after the first push (they block direct pushes).

### 3.1 GitHub repo (org owner / repo admin)

1. Create `<REPO>` in `<ORG>`: **Public**, empty for a new app.
2. Repo → Settings → Collaborators and teams: `developers` = **Write**, `devops` = **Maintain**.

### 3.2 GCP (devops)

```bash
curl -s "https://api.github.com/repos/$ORG/$REPO" | jq .id    # numeric repo ID
```

Add `<repo> = "<repo_id>"` to `repos` in `terraform.tfvars`, then with the devops token:

```bash
tofu plan     # expect only creates: 2 AR repos + 3 IAM members per new repo
tofu apply
tofu output ar_repo_path
```

### 3.3 GitHub Environments + secrets (repo admin)

| Environment | Deployment branches and tags | Protection | Secrets |
|---|---|---|---|
| `nonprod` | Branch `main` | — | `GCP_WIF_PROVIDER` = `wif_provider.nonprod`; `GCP_AR_REPO` = `ar_repo_path.nonprod.<REPO>` |
| `prod` | Tag `v*` | Required reviewers `devops`; *Prevent self-review* off if only one reviewer; *Allow administrators to bypass* off | `GCP_WIF_PROVIDER` = `wif_provider.prod`; `GCP_AR_REPO` = `ar_repo_path.prod.<REPO>`; `GCP_AR_REPO_SOURCE` = `ar_repo_path.nonprod.<REPO>` |

`wif_provider` comes from the admin (`github-ci-wif`), `ar_repo_path` from step 3.2.
Use **Environment secrets** only (masked in public logs; readable only by that environment's jobs).

UI (repo must be public on Free; requires repo admin):
1. `https://github.com/<ORG>/<REPO>/settings/environments` → **New environment** → name →
   **Configure environment** (or click an existing environment).
2. Page order: Required reviewers → Wait timer → Allow administrators to bypass →
   **Deployment branches and tags** → Environment secrets → Environment variables.
3. `prod` only: tick **Required reviewers**, add team `devops`, untick **Prevent self-review**,
   untick **Allow administrators to bypass…**, **Save protection rules**.
4. *Deployment branches and tags* is a **dropdown** (default *No restriction*) →
   **Selected branches and tags** → **Add deployment branch or tag rule** →
   Ref type **Branch** + `main` (nonprod) / **Tag** + `v*` (prod) → **Add rule**.
5. **Environment secrets** → **Add environment secret** for each row.

Check:
```bash
curl -s "https://api.github.com/repos/$ORG/$REPO/environments" \
  | jq '[.environments[] | {name, can_admins_bypass, protection_rules}]'
for e in nonprod prod; do
  curl -s "https://api.github.com/repos/$ORG/$REPO/environments/$e/deployment-branch-policies" \
    | jq -c '[.branch_policies[] | {name, type}]'
done
```

### 3.4 Code

Copy `.github/workflows/ci.yml` from an existing app repo; put each image in
`images/<name>/Dockerfile` (one directory per image; no GCP change needed to add an image).
Push to `main` → images appear in nonprod AR tagged with the commit SHA.

### 3.5 Rulesets (repo admin, after the first push)

Repo → Settings → Rules → Rulesets → **New ruleset**:
- Branch ruleset `protect-main`: Enforcement **Active**; target **Default branch**;
  Restrict deletions, Block force pushes, Require a pull request before merging.
- Tag ruleset `release-tags`: Enforcement **Active**; target pattern `v*`;
  Restrict creations, Restrict updates, Restrict deletions, Block force pushes;
  Bypass list: team `devops`.

## 4. Release

Tag a commit on `main` that was already built (`git tag v1.2.3 <sha> && git push origin v1.2.3`)
→ `prod` environment waits for `devops` approval → images are copied by digest from nonprod AR
to prod AR with tag `v1.2.3`. Prod tags are immutable.
