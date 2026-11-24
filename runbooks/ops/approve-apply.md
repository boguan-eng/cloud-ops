# Approve an Infrastructure Apply (Approver)

- **Who:** the approver (non-technical persona). Not the author or the GitHub reviewer.
- **Account:** the approver Google account (listed in `approver_principals`, stage 0 tfvars).
  It has only `cloudbuild.builds.approver`, `cloudbuild.builds.viewer` and `logging.viewer` on
  the seed project; it cannot change code or resources.
- **When:** a PR that changes `stages/<stage>/` was merged to `main` and the author tells you
  `<stage>-apply` is waiting.
- **What you decide:** whether the change shown in the plan may be applied now.
- **Org Owner approval is break-glass only.** The Org Owner can technically approve any
  build. Do so only when no approver is available, and write the reason as a PR comment
  before approving. Review: seed project audit log, method `ApproveBuild` — any principal
  outside the approvers group must have such a comment.

## 1. Sign in with the approver account

Open <https://console.cloud.google.com/> in a private window (or a browser profile used only
for this account) and sign in with the approver account. Top bar project picker → the seed
project (`<prefix>-iac-seed`).

## 2. Open the waiting build

Menu → **Cloud Build** → **History** → region `us-central1`. Find `<stage>-apply` with status
**Awaiting approval**. Note its commit (the merge commit of the PR).

## 3. Read the plan of the same change

The apply build has not run yet, so its own log is empty. Read the plan of the PR:

1. In **History**, open `<stage>-plan` of the same PR (the latest one before the merge).
2. Open step **plan** and scroll to the end.
3. Check the summary line `Plan: X to add, Y to change, Z to destroy.` against what the PR
   description says.

Reject if any of these is true:

- The numbers differ from the PR description.
- `to destroy` is not 0 and the PR description does not explain the deletion.
- The plan build failed or there is no plan build for this PR.

## 4. Approve or reject

On the `<stage>-apply` build page → **Approve** (or **Reject**) → optional comment → confirm.
If you reject, tell the author why.

## 5. Verify

Wait until the build status is **Success** (a few minutes). Open step **apply**; the last
lines show `Apply complete! Resources: …` with the same numbers as the plan. If it shows
**Failed**, tell the author; do not retry it yourself.

Your approval is recorded in the seed project's audit log (Admin Activity, method
`ApproveBuild`, with your account).

Next: nothing. The change is live.
