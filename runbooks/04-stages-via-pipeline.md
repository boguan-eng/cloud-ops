# 04 — Build Stages 1–3 Through the Pipeline (From Zero)

Creates the org IAM, environment folders and projects, WIF pools and Artifact Registry by
running each stage's `<key>-apply` trigger. Every apply waits for the approver.

**Who / which account:**
- GCP **Org Owner**: tfvars, local read-only plans, starts the apply triggers (CLI).
- **Approver** (member of the approvers group): approves each apply in the Console.

**Prerequisites:** runbooks 01–03 done (triggers exist, ruleset requires the plan checks);
group `<prefix>-gcp-approvers` has at least one member; variables from runbook 02 section 0.
**Next:** daily changes via [ops/change-via-pr.md](ops/change-via-pr.md).

Why the apply triggers are started by hand here: the stage code reached `main` (runbook 03)
before the triggers existed, so no push will start them. Later changes start them by merge.
Plan triggers are PR-only and cannot be run by hand (`RunTrigger is not supported for GCB v2
repo PullRequest Triggers`), so the Org Owner runs the plan locally (read-only) and gives the
expected summary to the approver.

Never commit real values. `terraform.tfvars` and `backend.hcl` are git-ignored; the pipeline
reads tfvars from `gs://${STATE_BUCKET}/tfvars/<key>/terraform.tfvars`.

## 0. Common commands (Org Owner)

```bash
cd cloud-ops/stages
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)   # Org Owner account

# per stage <dir> (stage directory) and <key> (trigger / state key):
#   1-org -> 1-org, 2-environments -> 2-environments,
#   3-cicd/wif -> 3-cicd-wif, 3-cicd/ar -> 3-cicd-ar
prepare() {  # $1=<dir> $2=<key>: upload tfvars, local read-only plan
  (cd "$1" && printf 'bucket = "%s"\n' "$STATE_BUCKET" > backend.hcl \
    && gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/$2/terraform.tfvars" \
    && tofu init -input=false -reconfigure -backend-config=backend.hcl \
    && tofu plan -input=false -lock=false | tail -1)
}
run_apply() {  # $1=<key>: start the apply trigger on main; it waits for approval
  gcloud builds triggers run "$1-apply" --branch=main \
    --region="$REGION" --project="$SEED_PROJECT"
}
run_check() {  # $1=<key>: start the manual check trigger on main (plan SA, no approval)
  gcloud builds triggers run "$1-check" --branch=main \
    --region="$REGION" --project="$SEED_PROJECT"
}
```

For each stage below: fill `terraform.tfvars` from `terraform.tfvars.example`, `prepare`,
tell the approver the plan summary, `run_apply`, wait for **Success**, then `run_check` and
require **SUCCESS** as well (see below).
The approver follows [ops/approve-apply.md](ops/approve-apply.md); since there is no PR plan
build, they compare the summary from the Org Owner with step **plan** of the apply build
after it ran, and report a mismatch at once.

Why `run_check` after every apply: the first apply only creates resources, so it does not
prove the plan SA can read what now exists; a failed check (error or diff) means a missing
read role in stage 0 (see `foundation-design.md`, Plan SA Read Coverage). Follow the build in
the Console or with `gcloud builds list` (the command returns once the build has started).

## 1. Stage 1 — org IAM

`1-org/terraform.tfvars`: `org_id`, `group_admins`.

```bash
prepare 1-org 1-org          # expect: Plan: N to add, 0 to change, 0 to destroy
run_apply 1-org
# after SUCCESS + approval:
run_check 1-org   # require SUCCESS
```

## 2. Stage 2 — folders, projects, folder IAM

`2-environments/terraform.tfvars`: `org_id`, `billing_account`, `prefix`, `group_devops`,
`group_developers`, `iac_project_plan_sa` / `iac_project_apply_sa` (stage 0 output
`service_accounts`). Set `project_id_suffix` if the default project IDs were ever used:
deleted project IDs can never be reused.

```bash
prepare 2-environments 2-environments   # only creates (folders, 2 projects, APIs, IAM)
run_apply 2-environments
# after SUCCESS + approval:
run_check 2-environments   # require SUCCESS
```

This also grants the project-tier IaC SAs their roles on the env folders, so stage 3 can
run, and creates the PAM entitlement `prod-operator` on the prod folder. PAM uses the
organization-level service agent, which no IaC resource can create; create it once before
this apply (idempotent; it grants nothing by itself):

```bash
gcloud beta services identity create --service=privilegedaccessmanager.googleapis.com \
  --organization="$ORG_ID"
# expect: Service identity created: service-org-<ORG_ID>@gcp-sa-pam.iam.gserviceaccount.com
```
 If project creation fails on quota: soft-deleted projects count against it for 30 days.

## 3. Stage 3 — WIF pools

`3-cicd/wif/terraform.tfvars`: `nonprod_project_id`, `prod_project_id` (stage 2 project IDs),
`github_org_id`.

```bash
prepare 3-cicd/wif 3-cicd-wif   # expect: 10 to add (2 pools, 2 providers, 6 APIs)
run_apply 3-cicd-wif
# after SUCCESS + approval:
run_check 3-cicd-wif   # require SUCCESS
```

## 4. Stage 3 — Artifact Registry

`3-cicd/ar/terraform.tfvars`: project IDs as above, `region`, `wif_pool` (from
`cd 3-cicd/wif && tofu output wif_pool`), `repos` (GitHub repo name → numeric repo ID).

```bash
prepare 3-cicd/ar 3-cicd-ar     # expect per repo: 2 repos + 2 writer + 1 prod-reads-nonprod, plus 2 APIs
run_apply 3-cicd-ar
# after SUCCESS + approval:
run_check 3-cicd-ar   # require SUCCESS
```

## 5. App repos

Set each app repo's environment secrets from the outputs, as described in
`stages/3-cicd/ar/RUNBOOK.md` section 3 (`wif_provider`, `ar_repo_path`). Push to `main`
(nonprod) and, for a release, a `v*` tag (prod, waits for `devops` approval).

## Verification

```bash
gcloud builds list --region="$REGION" --project="$SEED_PROJECT" \
  --format='table(substitutions.TRIGGER_NAME,status,approval.result.decision)' --limit=12
# expect each <key>-apply: SUCCESS, APPROVED
run_check 1-org; run_check 2-environments; run_check 3-cicd-wif; run_check 3-cicd-ar
# expect each <key>-check: SUCCESS (no approval; re-run the same way to detect drift)
gcloud storage ls "gs://${STATE_BUCKET}/tfstate/"   # 0-bootstrap, 1-org, 2-environments, 3-cicd-wif, 3-cicd-ar
gcloud logging read 'protoPayload.methodName:"ApproveBuild"' --project="$SEED_PROJECT" \
  --freshness=1d --format='value(timestamp,protoPayload.authenticationInfo.principalEmail)'
# expect: approvers-group members only (Org Owner only as break-glass, see approve-apply.md)
```

App: images in `${REGION}-docker.pkg.dev/<nonprod project>/<repo>`; after a release the
same digests in the prod project.

Note: after stage 2, the Org Owner and devops have no read access to the WIF/AR resources
in the env projects (by design), so local plans of stage 3 fail once those resources exist.
Use the plan builds of PRs instead.

**Next:** [ops/change-via-pr.md](ops/change-via-pr.md).
