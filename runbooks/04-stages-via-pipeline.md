# 04 — Build Stages 1–3 Through the Pipeline (Last Bootstrap Step)

Last step of the from-zero bootstrap, run **once** by an admin (`admin1`, member of
`gcp-admins`): creates the org IAM, environment folders and projects, WIF pools and Artifact
Registry by running each stage's `<key>-apply` trigger. Applies run without an approval step
(approval is the GitHub PR review). These first applies have no PR: the admin's review is the
local plan, compared with step **plan** of each apply build. Afterwards the
admins operate only stage 0, tfvars-only changes and break-glass.

**Who / which account:**
- **Admin** (`gcp-admins`): tfvars, local read-only plans, starts the apply triggers and the
  check jobs (CLI). The admins group holds actAs on the IaC SAs, so it can start triggers.
- **GitHub org Owner** (repo admin): app repo environment secrets in section 5.

**Prerequisites:** runbooks 00–03 done (triggers exist, ruleset requires the plan checks);
group `gcp-approvers` has at least one member (PAM approver); variables from runbook 02
section 0.
**Next:** all later changes via [ops/change-via-pr.md](ops/change-via-pr.md); checks via
[ops/run-checks.md](ops/run-checks.md).

Why the apply triggers are started by hand here: the stage code reached `main` (runbook 03)
before the triggers existed, so no push will start them. Later changes start them by merge.
Plan triggers are PR-only and cannot be run by hand (`RunTrigger is not supported for GCB v2
repo PullRequest Triggers`), so the admin runs the plan locally (read-only) and compares it with
step **plan** of the apply build.

Never commit real values. `terraform.tfvars` and `backend.hcl` are git-ignored; the pipeline
reads tfvars from `gs://${STATE_BUCKET}/tfvars/<key>/terraform.tfvars`.

## 0. Common commands (admin)

```bash
cd cloud-ops/stages
export GOOGLE_OAUTH_ACCESS_TOKEN=$(gcloud auth print-access-token)   # admin account

# per stage <dir> (stage directory) and <key> (trigger / state key):
#   1-org -> 1-org, 2-environments -> 2-environments,
#   3-cicd/wif -> 3-cicd-wif, 3-cicd/ar -> 3-cicd-ar
prepare() {  # $1=<dir> $2=<key>: upload tfvars, local read-only plan
  (cd "$1" && printf 'bucket = "%s"\n' "$STATE_BUCKET" > backend.hcl \
    && gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/$2/terraform.tfvars" \
    && tofu init -input=false -reconfigure -backend-config=backend.hcl \
    && tofu plan -input=false -lock=false -no-color | grep -E '^(Plan:|No changes)')
}
run_apply() {  # $1=<key>: start the apply trigger on main (no approval step)
  gcloud builds triggers run "$1-apply" --branch=main \
    --region="$REGION" --project="$SEED_PROJECT"
}
run_check() {  # $1=<key>: run the Scheduler job <key>-check (starts the check build as iac-check-runner)
  gcloud scheduler jobs run "$1-check" --location="$REGION" --project="$SEED_PROJECT"
}
check_result() {  # $1=<key>: status and start time of the latest check build
  gcloud builds list --region="$REGION" --project="$SEED_PROJECT" \
    --filter="substitutions.TRIGGER_NAME=$1-check" --limit=1 --format='value(status,createTime)'
}
```

`run_check` prints nothing and returns at once; the build appears **1–4 minutes later**.
Wait, then `check_result <key>`: the `createTime` must be after the job run, and the status
**SUCCESS** (`WORKING` or `QUEUED` = not finished, repeat). Do not use
`gcloud builds triggers run …-check`: it also works for the admin, but checks are meant to
run the same way devops runs them ([ops/run-checks.md](ops/run-checks.md)).

For each stage below: fill `terraform.tfvars` from `terraform.tfvars.example`, `prepare`
(note the plan summary), `run_apply`, wait for **Success**, compare step **plan** of the apply
build with the noted summary (a mismatch: stop and investigate), then `run_check`, wait
1–4 minutes and require `check_result` = **SUCCESS** as well (see below).

Why `run_check` after every apply: the first apply only creates resources, so it does not
prove the plan SA can read what now exists; a failed check (error or diff) means a missing
read role in stage 0 (see `foundation-design.md`, Plan SA Read Coverage). On FAILURE open the
build log in the Console (seed project → Cloud Build → History → `<key>-check`).

## 1. Stage 1 — org IAM

`1-org/terraform.tfvars`: `org_id`, `allowed_policy_member_customer_ids`,
`allowed_contact_domains` (the live values: `gcloud org-policies describe
iam.allowedPolicyMemberDomains --organization=$ORG_ID` and `...
essentialcontacts.managed.allowedContactDomains`), `billing_account`, `seed_project_id`,
`budget_amount` (in the billing account currency: `gcloud billing accounts describe
$BILLING_ACCOUNT --format='value(currencyCode)'`; set `budget_currency` if it is not TWD),
`billing_alert_email` (a user address; group addresses get no mail) (see
`stages/1-org/terraform.tfvars.example`).

```bash
prepare 1-org 1-org          # expect: 7 to import, N to add, 0 to change, 0 to destroy
run_apply 1-org
# after SUCCESS:
run_check 1-org; sleep 240; check_result 1-org   # require SUCCESS
```

## 2. Stage 2 — folders, projects, folder IAM

`2-environments/terraform.tfvars`: `org_id`, `billing_account`, `prefix`, `group_devops`,
`group_developers`, `group_approvers`, `pam_approver_emails` / `pam_admin_emails` (user
addresses), `iac_project_plan_sa` / `iac_project_apply_sa` / `iac_org_apply_sa` (stage 0 output
`service_accounts`). Set `project_id_suffix` if the default project IDs were ever used:
deleted project IDs can never be reused.

This stage also grants the project-tier IaC SAs their roles on the env folders, so stage 3 can
run, and creates the PAM entitlement `prod-operator` on the prod folder. PAM uses the
organization-level service agent, which no IaC resource can create; create it first
(idempotent; it grants nothing by itself):

```bash
gcloud beta services identity create --service=privilegedaccessmanager.googleapis.com \
  --organization="$ORG_ID"
# expect: Service identity created: service-org-<ORG_ID>@gcp-sa-pam.iam.gserviceaccount.com
prepare 2-environments 2-environments   # only creates (folders, 2 projects, APIs, IAM)
run_apply 2-environments
# after SUCCESS:
run_check 2-environments; sleep 240; check_result 2-environments   # require SUCCESS
```

If project creation fails on quota: soft-deleted projects count against it for 30 days.

## 3. Stage 3 — WIF pools

`3-cicd/wif/terraform.tfvars`: `nonprod_project_id`, `prod_project_id` (stage 2 project IDs),
`github_org_id`.

```bash
prepare 3-cicd/wif 3-cicd-wif   # expect: 10 to add (2 pools, 2 providers, 6 APIs)
run_apply 3-cicd-wif
# after SUCCESS:
run_check 3-cicd-wif; sleep 240; check_result 3-cicd-wif   # require SUCCESS
```

## 4. Stage 3 — Artifact Registry

`3-cicd/ar/terraform.tfvars`: project IDs as above, `region`, `wif_pool` (from
`cd 3-cicd/wif && tofu output wif_pool`). The app repos (`repos`) are in `3-cicd/ar/variables.tf`,
changed by PR.

```bash
prepare 3-cicd/ar 3-cicd-ar     # expect per repo: 2 repos + 2 writer + 1 prod-reads-nonprod, plus 2 APIs
run_apply 3-cicd-ar
# after SUCCESS:
run_check 3-cicd-ar; sleep 240; check_result 3-cicd-ar   # require SUCCESS
```

## 5. App repos

Set each app repo's environment secrets from the outputs, as described in
`stages/3-cicd/ar/RUNBOOK.md` section 3 (`wif_provider`, `ar_repo_path`). Push to `main`
(nonprod) and, for a release, a `v*` tag (prod, waits for `devops` approval).

## Verification

```bash
gcloud builds list --region="$REGION" --project="$SEED_PROJECT" \
  --format='table(substitutions.TRIGGER_NAME,status)' --limit=12
# expect each <key>-apply: SUCCESS
for k in 1-org 2-environments 3-cicd-wif 3-cicd-ar; do run_check "$k"; done
sleep 240   # the builds appear 1–4 minutes after the job run
for k in 1-org 2-environments 3-cicd-wif 3-cicd-ar; do echo "$k: $(check_result "$k")"; done
# expect each <key>-check: SUCCESS with a createTime after the run (no approval)
gcloud scheduler jobs list --location="$REGION" --project="$SEED_PROJECT" \
  --format='table(name.basename(),state,schedule,timeZone)'
# expect 4 jobs <key>-check, ENABLED, "0 3 * * *", Asia/Taipei (daily checks start tomorrow)
gcloud storage ls "gs://${STATE_BUCKET}/tfstate/"   # 0-bootstrap, 1-org, 2-environments, 3-cicd-wif, 3-cicd-ar
```

App: images in `${REGION}-docker.pkg.dev/<nonprod project>/<repo>`; after a release the
same digests in the prod project.

Note: after stage 2, the admins and devops have no read access to the WIF/AR resources
in the env projects (by design), so local plans of stage 3 fail once those resources exist.
Use the plan builds of PRs instead.

**From now on:** the bootstrap is finished. Every change goes through a PR
([ops/change-via-pr.md](ops/change-via-pr.md)); the checks run daily at 03:00 Asia/Taipei and
on demand by devops ([ops/run-checks.md](ops/run-checks.md)).

**Next:** [ops/change-via-pr.md](ops/change-via-pr.md).
