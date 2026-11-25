# 03 — cloud-ops Repository and Pipeline

Publishes `cloud-ops`, protects `main`, connects it to Cloud Build and creates the per-stage
triggers (PR → plan; merge to `main` → apply after approval; manual check) and the daily
check jobs.

**Who:** GitHub org **Owner** (browser, sections 1–3 and the browser part of 4) and the GCP
**Org Owner** (CLI, sections 4–5).
**Prerequisites:** runbooks 01 and 02 done; variables from runbook 02 section 0.
**Next:** `04-stages-via-pipeline.md`.

```bash
export GITHUB_ORG="acme"           # FAKE
export CONNECTION="github"         # Cloud Build connection name
```

## 1. Create and push the repository (GitHub org Owner)

1. Org → **New repository** → name `cloud-ops`, **Public**, no README/license.
   Created private by mistake: repo → **Settings** → **General** → **Danger Zone** →
   **Change repository visibility** → **Make public**.
2. Before the first push, run the public-repo checks in `AGENTS.md` (secrets, personal data,
   real IDs) on the whole history.
3. Push:
   ```bash
   git remote add origin "https://github.com/${GITHUB_ORG}/cloud-ops.git"
   git push -u origin main          # the branch must be named main (triggers match ^main$)
   ```

## 2. Repository access (GitHub org Owner)

Repo → **Settings** → left menu *Access* → **Collaborators and teams** → **Add teams** →
`devops` → role **Write** → **Add selection**. Do not add `developers`.

## 3. Protect `main` (GitHub org Owner)

Repo → **Settings** → **Rules** → **Rulesets** → **New ruleset** → **New branch ruleset**:
- Name `protect-main`, Enforcement status **Active**, Target branches → **Add target** →
  **Include default branch**.
- Check **Restrict deletions**, **Block force pushes**.
- Check **Require a pull request before merging**: required approvals **1**,
  **Dismiss stale pull request approvals when new commits are pushed**.
- Bypass list: **Organization admin** only. Use only per `ops/change-via-pr.md` "Review bypass" (docs-only or practice PRs, reason stated; never `stages/` changes).
- **Create**.

With a single devops member, the PR author cannot approve their own PR: merging needs another
member's review or the owner bypass.

## 4. Cloud Build ↔ GitHub connection (GCP Org Owner CLI + GitHub org Owner browser)

Two identities are involved:
- **GCP side** (CLI): the Org Owner creates the connection in the seed project. Stage 0 already
  gave the Cloud Build service agent the Secret Manager permission it needs; without it the
  command fails with "could not assert Secret Manager permissions".
- **GitHub side** (browser, cannot be scripted): a GitHub org **Owner** authorizes the Cloud
  Build GitHub App and installs it on the org, **Only select repositories → `cloud-ops`**.
  The resulting OAuth token is stored in Secret Manager in the seed project and is tied to
  that GitHub account. Google recommends a shared robot account; if the person leaves or
  revokes the app, the pipeline stops.

```bash
gcloud builds connections create github "$CONNECTION" --region="$REGION" --project="$SEED_PROJECT"
# prints PENDING_USER_OAUTH and a URL
gcloud builds connections describe "$CONNECTION" --region="$REGION" --project="$SEED_PROJECT" \
  --format='value(installationState.actionUri)'
```

Open the URL in a browser: choose the Google account of the Org Owner, then on GitHub
authorize and install the app as above. The page ends with "Connection configured
successfully".

```bash
gcloud builds connections describe "$CONNECTION" --region="$REGION" --project="$SEED_PROJECT" \
  --format='value(installationState.stage)'      # expect COMPLETE
```

## 5. Create the triggers (GCP Org Owner)

In `stages/0-bootstrap/terraform.tfvars` set:

```hcl
enable_github          = true
builder_image          = "<BUILDER_IMAGE from runbook 02>"
github_connection_name = "github"
github_repo_uri        = "https://github.com/<GITHUB_ORG>/cloud-ops.git"
```

```bash
cd stages/0-bootstrap
tofu init -backend-config=backend.hcl
tofu apply            # expect: repository link + 12 triggers (4 plan, 4 apply, 4 check),
                      # SA iac-check-runner + its role/bindings, 4 Scheduler jobs; no destroy
gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/0-bootstrap/terraform.tfvars"
```

## 6. Require the plan checks (GitHub org Owner)

A failed plan must block the merge. Cloud Build reports one check per plan trigger on every
PR, named `<stage>-plan (<SEED_PROJECT>)`; triggers whose paths the PR does not touch report
*neutral* ("Changed files did not match file filter"), which counts as passing.

The names appear in the search box only after the triggers have reported once (open any PR).
Ruleset `protect-main` → check **Require status checks to pass** → **Add checks** → add the
4 `*-plan` checks, each with source **Google Cloud Build** (not *Any source*: anyone with Write
could post a fake status with the same name) → **Save changes**.

Keep the list in sync with the triggers:
- New stage: add its trigger in stage 0 **and** its check here, or its failed plan will not
  block merges.
- Renamed or deleted trigger: update the list at the same time, or every PR waits forever on
  "Expected — Waiting for status".

## Verification

```bash
gcloud builds triggers list --region="$REGION" --project="$SEED_PROJECT" --format=json | python3 -c '
import json,sys
for t in json.load(sys.stdin):
  r=t.get("repositoryEventConfig",{})
  print(t["name"], "PR" if "pullRequest" in r else "PUSH" if "push" in r else "MANUAL",
        "approval="+str(t.get("approvalConfig",{}).get("approvalRequired",False)),
        "logsToGitHub="+t.get("includeBuildLogs","UNSET"),
        t.get("serviceAccount","").split("/")[-1].split("@")[0])'
```

Expected: 12 triggers. `*-plan`: PR, approval False, plan SA. `*-apply`: PUSH, approval True,
apply SA. `*-check`: manual, approval False, plan SA (started by the Scheduler jobs, see runbook 04
and [ops/run-checks.md](ops/run-checks.md)). All `logsToGitHub=UNSET` (build logs stay in Cloud Logging).

Check runner (stage 0): the SA exists, its seed custom role is `buildTriggerRunner`, and it may
act as the two **plan** SAs only (never an apply SA):

```bash
gcloud iam service-accounts describe "iac-check-runner@${SEED_PROJECT}.iam.gserviceaccount.com" \
  --project="$SEED_PROJECT" --format='value(email,disabled)'      # expect the email, empty/False
for sa in iac-org-plan iac-project-plan iac-org-apply iac-project-apply; do
  echo "== $sa"
  gcloud iam service-accounts get-iam-policy "${sa}@${SEED_PROJECT}.iam.gserviceaccount.com" \
    --project="$SEED_PROJECT" --flatten='bindings[].members' \
    --filter='bindings.role=roles/iam.serviceAccountUser' --format='value(bindings.members)'
done
# expect: iac-check-runner listed under iac-org-plan and iac-project-plan ONLY;
# under the two apply SAs only the trigger admins (Org Owner), never iac-check-runner
gcloud scheduler jobs list --location="$REGION" --project="$SEED_PROJECT" \
  --format='table(name.basename(),state,schedule,timeZone)'
# expect 4 jobs <key>-check, ENABLED, schedule "0 3 * * *", Asia/Taipei
```

```bash
curl -s "https://api.github.com/repos/${GITHUB_ORG}/cloud-ops/rules/branches/main"
# expect rule types: deletion, non_fast_forward, pull_request (required_approving_review_count 1),
# required_status_checks (4 *-plan contexts, integration_id 10529 = Google Cloud Build)
```

**Next:** `04-stages-via-pipeline.md`.
