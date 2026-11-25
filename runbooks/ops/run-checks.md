# Run the Stage Checks (Drift and Read Coverage)

A `<stage>-check` plans the stage on `main` as the read-only plan SA
(`tofu plan -detailed-exitcode`) and fails on any error or diff. SUCCESS means: code,
state and GCP agree, and the plan SA can read everything the stage manages.

**Who / which account:** a `devops` member (Google account in the devops group); the Org Owner
can too. No approval is needed; nothing is changed.
**Prerequisites:** stage 0 with `enable_github = true` applied (runbook 03); variables
`REGION` and `SEED_PROJECT` set (runbook 02 section 0). `<key>` is one of
`1-org`, `2-environments`, `3-cicd-wif`, `3-cicd-ar`.
**Next:** on FAILURE, step 3; otherwise nothing.

## 1. When

- **Daily, automatic:** 03:00 Asia/Taipei, 4 Cloud Scheduler jobs `<key>-check`.
- **On demand:** after a manual or incident change ([approve-pam-grant.md](approve-pam-grant.md)),
  after the reconcile PR, or to look for drift.

## 2. Run on demand and verify

```bash
gcloud scheduler jobs run <key>-check --location="$REGION" --project="$SEED_PROJECT"
# prints NOTHING and returns at once; the build appears 1–4 minutes later
gcloud builds list --region="$REGION" --project="$SEED_PROJECT" \
  --filter='substitutions.TRIGGER_NAME=<key>-check' --limit=1 --format='value(status,createTime)'
```

Expect `SUCCESS` and a `createTime` after your run. `QUEUED` / `WORKING` = not finished, repeat
the second command after a minute. No build yet after 5 minutes: look at the scheduler attempt in
Cloud Logging (logName contains `cloudscheduler`; success is `URL_CRAWLED. Original HTTP
response code number = 200`).

## 3. On FAILURE

FAILURE means an error or a diff. Console → seed project → **Cloud Build** → **History**
(region `us-central1`) → `<key>-check` → step `plan`:
- **Diff on resources you did not change:** drift (someone changed GCP by hand). Fix by a PR that
  matches the code to the intended state, or revert the manual change.
- **Permission error (403 on read):** the plan SA lacks a read role; fix in stage 0
  (see `stages/foundation-design.md`, Plan SA Read Coverage) via the Org Owner.
- Read daily failures the same way: failed builds are not notified yet (deferred with the
  notification topic), so check `gcloud builds list` (above) in the morning if you are on duty.

## What devops cannot do, and why

- **Start a trigger directly** (`gcloud builds triggers run <key>-check`): `PERMISSION_DENIED`.
  Starting a trigger needs actAs on the trigger's service account. A human with actAs on a plan
  SA could run any build as it (org-wide read, state, tfvars), so no human gets it, except the Org
  Owner.
- **List jobs** (`gcloud scheduler jobs list`): the devops role `roles/cloudscheduler.jobRunner`
  has `jobs.run`, not `jobs.get` / `jobs.list`. Run a job by its name; the four names are above.
- **Start applies:** only a merge to `main` plus approval does
  ([approve-apply.md](approve-apply.md)). The scheduler SA `iac-check-runner` can start builds, but
  can act as the two plan SAs only.
