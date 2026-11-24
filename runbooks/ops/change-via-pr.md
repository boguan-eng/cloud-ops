# Change cloud-ops via Pull Request

Every change to `cloud-ops` (code or docs) goes through a PR; `main` is protected
(1 approving review, no force push, no deletion). After setup, this is the only way
infrastructure changes reach GCP.

**Who:**
| Step | Who | Account |
|---|---|---|
| Branch, commit, push, open PR | Author | a `devops` team member |
| Review and approve on GitHub | Reviewer | a **different** `devops` member (GitHub forbids approving your own PR) |
| Merge | Author or reviewer | `devops` member |
| Approve the apply build in GCP | Approver | member of the approvers group ([approve-apply.md](approve-apply.md)) |

**Prerequisites:** both GitHub accounts are in the `devops` team (Write) and have 2FA, and
both have GitHub **Settings → Emails → Keep my email addresses private** and **Block command
line pushes that expose my email** on. A merge in the web UI is authored by the merging
account; without the private setting its real email becomes public in `main`'s history.
Local commits must use the `…@users.noreply.github.com` address (`git config user.email`).

## 1. Author: branch, commit, push

Before committing, run the public-repo checks in `AGENTS.md`.

```bash
git switch main && git pull
git switch -c <type>/<short-name>          # e.g. docs/runbooks-flow, feat/pam-prod
# edit, then one commit per purpose:
git add <files> && git commit -m "<type>: <what and why>"
git push -u origin <type>/<short-name>
```

## 2. Author: open the PR

GitHub → `cloud-ops` → banner **Compare & pull request** (or **Pull requests** → **New pull
request** → base `main`, compare `<branch>`) → title and description (what, why, which stages
are affected) → **Create pull request**.

What happens automatically:
- If the PR touches `stages/<stage>/` or `stages/cloudbuild/`, the `<stage>-plan` trigger runs.
  The PR shows a Cloud Build check with status only; the plan output is in GCP:
  Console → seed project → **Cloud Build** → **History** (region `us-central1`) → the build →
  step `plan` log. Viewing needs Cloud Build Viewer + Logs Viewer (devops, approvers).
- Docs-only PRs (`runbooks/`, `*.md` outside stage dirs) run no build.

### Public exposure check (every PR with a build)

The repo is public. GitHub checks may show only: status, the seed project ID in the check name
(accepted), and build/trigger UUIDs. Anything else (plan text, org ID, project number, billing
account, email) is a leak: stop, and fix before merging.

```bash
SHA=<head commit of the PR>; FORBIDDEN='<org id>|<project number>|<billing id>|@gmail|google_'
curl -s "https://api.github.com/repos/<ORG>/cloud-ops/commits/${SHA}/check-runs" \
  | python3 -c 'import json,sys; [print(c["name"], c["output"]["summary"]) for c in json.load(sys.stdin)["check_runs"]]' \
  | grep -E "$FORBIDDEN" && echo LEAK || echo OK
```

## 3. Reviewer: review and approve (other account)

Sign in to GitHub with the reviewer account → the PR → **Files changed** → read the diff
(and, for stage changes, the plan in Cloud Build) → **Review changes** → **Approve** →
**Submit review**.

## 4. Merge

PR → **Merge pull request** → choose **Create a merge commit** (keeps one commit per purpose;
do not squash commits with different purposes) → **Confirm merge** → **Delete branch**.

Locally:

```bash
git switch main && git pull && git branch -d <type>/<short-name>
git log -1 --format='%ae | %ce'   # expect: <id>+<login>@users.noreply.github.com | noreply@github.com
```

Any other address in the output is a leak of personal data: report it to the Org Owner.
Pushed history is not rewritten without the Org Owner's explicit decision.

## 5. Approver: approve the apply (only if stages changed)

Merging a change under `stages/<stage>/` starts `<stage>-apply`, which waits for approval.
No notification is configured for pending approvals; the author tells the approver, who
follows [approve-apply.md](approve-apply.md). Write the expected plan summary
(`Plan: X to add, Y to change, Z to destroy`) in the PR description so the approver can
compare it.

After the build succeeds, the change is live. Approvals are recorded in the seed project's
Admin Activity audit log (`ApproveBuild`).
