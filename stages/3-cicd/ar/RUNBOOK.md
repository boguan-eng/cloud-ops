# GitHub CI → Artifact Registry — Runbook

Per-repo setup so a GitHub repo's Actions can push images to nonprod AR (on `main`) and
promote them to prod AR (on `v*` tags). The AR repos and their IAM are stage `3-cicd/ar`,
applied by the pipeline (first build: `runbooks/04-stages-via-pipeline.md` section 4; later
changes: `runbooks/ops/change-via-pr.md`). Nobody runs `tofu apply` for it locally.

Never write real values into tracked files. Session variables only:

```bash
export ORG=...               # GitHub org name
export REPO=...              # GitHub repo name (also the AR repository ID)
```

## 3. Onboard a repo

Order matters: Environments + secrets must exist before the first push to `main`
(it triggers the `push` job); rulesets come after the first push (they block direct pushes).

### 3.1 GitHub repo (org owner / repo admin)

1. Create `<REPO>` in `<ORG>`: **Public**, empty for a new app.
2. Repo → Settings → Collaborators and teams: `developers` = **Write**, `devops` = **Maintain**.

### 3.2 GCP (devops, by PR)

```bash
curl -s "https://api.github.com/repos/$ORG/$REPO" | jq .id    # numeric repo ID
```

Add `<repo> = "<repo_id>"` to the `repos` default in `stages/3-cicd/ar/variables.tf` and open a
PR (`Expected plan: 5 to add` per new repo: 2 AR repos + 3 IAM members). After review and
merge, the `3-cicd-ar-apply` build applies it. Its log (seed project → Cloud Build → History)
ends with the outputs; take `ar_repo_path` from there and hand it to the repo admin privately
(it contains project IDs).

### 3.3 GitHub Environments + secrets (repo admin)

| Environment | Deployment branches and tags | Protection | Secrets |
|---|---|---|---|
| `nonprod` | Branch `main` | — | `GCP_WIF_PROVIDER` = `wif_provider.nonprod`; `GCP_AR_REPO` = `ar_repo_path.nonprod.<REPO>` |
| `prod` | Tag `v*` | Required reviewers `devops`; *Prevent self-review* off if only one reviewer; *Allow administrators to bypass* off | `GCP_WIF_PROVIDER` = `wif_provider.prod`; `GCP_AR_REPO` = `ar_repo_path.prod.<REPO>`; `GCP_AR_REPO_SOURCE` = `ar_repo_path.nonprod.<REPO>` |

`wif_provider` comes from the `3-cicd-wif-apply` build log, `ar_repo_path` from step 3.2.
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
