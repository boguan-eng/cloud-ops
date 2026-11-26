# Identity Migration (Cloud Identity) — Design

Status: draft 2026-11-25, waiting for user confirmation.
Requirements: [identity-migration-requirements.md](identity-migration-requirements.md).
Real values (domain, account and group addresses, prefix, IDs) stay in tfvars, gcloud configs and
the chat; this file uses placeholders. Done so far: `<domain>` registered at Cloudflare
(USD 11, 2026-11-25), second Cloudflare Super Administrator invited (R1-1, part of R1-2).

## 1. Names

| Kind | Name (local part @`<domain>`) | Members / use |
|---|---|---|
| User | `admin1`, `admin2` | Cloud Identity super admins and organization admins via `gcp-admins`; break-glass and bootstrap only |
| User | `<person>` (devops person, e.g. first name) | Daily account; `gcp-devops` |
| User | `test-approver` | `gcp-approvers` (PAM approver persona, separate from devops) |
| User | `test-dev` | `gcp-developers`; acceptance and handover tests |
| Group | `gcp-admins` | `admin1`, `admin2` only |
| Group | `gcp-devops`, `gcp-developers`, `gcp-approvers`, `gcp-billing` | As in Foundation; `gcp-billing` = `admin1`, `admin2` |

- Naming rule (decided 2026-11-25): **a person's account is named after the person**, never
  after a role (`devops1`): the role is the group membership, so a role change is a group change
  and a leaver's account is deleted, not handed to the next person (audit logs stay attributable).
  Role-named accounts are allowed only for break-glass (`admin1`, `admin2`) and test personas
  (`test-*`), which no person uses daily.
- Each user address has one Cloudflare Email Routing rule to that person's verified mailbox
  outside `<domain>`. No catch-all. Super admin recovery email/phone are outside `<domain>`.
- gcloud configurations: one per account, created with `--no-activate`; names not committed.
- GitHub: team `iac-reviewers` (both GitHub members who review IaC), used by CODEOWNERS.

## 2. Who holds what (R4: no IAM on an individual)

| Grant | Holder | Managed by |
|---|---|---|
| Org `organizationAdmin`, `projectCreator` (what the stage 0 operator needs) | `group:gcp-admins` | Granted once by hand in runbook 00 (stage 0 cannot grant what it needs to run); then declared in stage 0 (`admin_principals`; additive member resources, so re-declaring an existing binding is a no-op) |
| Seed project `owner` | `group:gcp-admins`; the creator's user binding removed | Stage 0 (`google_project_iam_member` + `google_project_iam_member_remove`) |
| Billing account `billing.admin` | `group:gcp-admins` (S2); old Gmail admin removed in teardown | Granted by hand in runbook 00 by the current Gmail billing admin; then declared in stage 0 |
| actAs on IaC SAs (first applies, break-glass) | `group:gcp-admins` | Stage 0 `trigger_admin_principals` (value change only) |
| Defaults granted at org creation (S3: `projectCreator` + `billing.creator` on `domain:`, `organizationAdmin` on the creator) | Removed (none required) | Runbook 00 §5 by hand; checked by V1. Not declared in IaC: the provider has no org-level `_remove` resource (read 2026-11-25), and org IAM is non-authoritative (`_member`), so `<stage>-check` does not detect any added org binding anyway |

Super admin itself is a Cloud Identity role on 2 accounts (Google requires accounts; R3/D6).

### 2.1 Access layers and group granularity (user decision 2026-11-25)

| Layer | Decides | Where |
|---|---|---|
| Change | Who may get GCP resources created or changed: author a PR, approve which paths | GitHub teams + CODEOWNERS |
| Direct access | Who still acts in GCP as a person: bootstrap, break-glass, read, incident, billing | Cloud Identity groups |

Org, folders and projects are created by pipeline SAs after merge (stage 0 is the only human
apply, by the Org Owner). So groups follow the direct-access duties, not resource ownership:

| Group | Direct duty in GCP |
|---|---|
| `gcp-admins` | Bootstrap, break-glass, Org Owner |
| `gcp-billing` | Billing account admin (same members as admins now; separate duty, may move to finance) |
| `gcp-devops` | Read config and logs; PAM request for prod in incidents |
| `gcp-approvers` | PAM approval only (requester cannot self-approve) |
| `gcp-developers` | Read nonprod resources and logs |

Rules:
- Granularity = duty × scope, not department. Add a group only for a distinct permission set.
  Leads who approve are members of a duty group, not a group of their own. With several
  products: `gcp-<product>-<duty>`.
- Repos: one platform repo with CODEOWNERS path ownership (apps already have their own repos).
  Split a product's infra into its own repo (own SA and state) only when a separate team must
  not approve the platform's changes. The security boundary is each pipeline SA's permissions.
- GitHub teams and Cloud Identity groups are maintained separately (no sync assumed).

## 3. Approval only in GitHub (R10)

| Change | Where |
|---|---|
| Apply triggers run on push to `main` without approval: remove `approval_config` | `stages/0-bootstrap/cicd.tf` |
| Remove the approvers' seed roles (`cloudbuild.builds.approver/viewer`, `logging.viewer`) and `approver_principals` | `stages/0-bootstrap/iam.tf`, `variables.tf`, tfvars example |
| Approvers keep PAM approver + prod `folderViewer` | `stages/2-environments/pam.tf` (unchanged) |
| `CODEOWNERS`: `/stages/` and `/stages/cloudbuild/` → `@<org>/iac-reviewers` | `.github/CODEOWNERS` |
| Ruleset `protect-main`: 1 approval, require code owner review, required checks = new `<key>-plan` names, bypass = organization admins only (no author bypass) | GitHub UI (runbook 01) |
| GitHub org: 2 owners, require 2FA; authors (devops) are members, not owners, because the bypass actor is Organization admin | GitHub UI (runbook 01) |
| Docs: delete `ops/approve-apply.md`; rewrite `ops/change-approver.md` (PAM approvers only) and `ops/change-via-pr.md` (no Cloud Build approval, bypass = Org Owner emergency + PR note); update runbooks 01, 03, 04, README role matrix, `foundation-design.md` decisions | Repo docs |

The old org is deleted first (phase 0), so no PR or merge runs against it. While no pipeline
exists, the ruleset keeps 1 approval but has no required checks (phase 0 step 1); the new
`<key>-plan` checks are added back in phase 3 step 5.

## 4. Phases and steps

### Phase 0 — Delete the old setup first (user decision 2026-11-25)

Kept: the billing account and its Gmail `billing.admin` (needed for S2), local gitignored tfvars
copies (reference only), the old Org Owner gcloud configs (until the org is deleted).

1. GitHub ruleset `protect-main`: remove the 4 old required `<key>-plan` checks (they would never
   report again); keep 1 approval. Demo app workflows fail until phase 3 (accepted).
2. Delete the budget on the billing account (it is not deleted with the projects).
3. Remove billing account IAM of the old IaC SAs and the old billing group; keep the Gmail admin.
4. Unlink billing from the 3 old projects, then delete them (env projects, then seed;
   30-day pending deletion). Linked projects on the billing account become 0 (replaces S6).
5. Delete the `prod` / `nonprod` folders if allowed; otherwise together with the org later.
6. Delete the 5 old consumer Google Groups (groups.google.com).
7. Later (after the 30-day purge): delete the old org as its Organization Owner. Not on the
   acceptance path.

Acceptance: no budget; billing IAM = Gmail admin only; 0 linked projects; 3 projects
`DELETE_REQUESTED`; ruleset without old required checks.

### Phase 1 — Identity (runbook 00, new; operator: admin1 unless stated)

1. Cloudflare: Email Routing on (adds MX/SPF); verify destination mailboxes; one rule per user.
2. Cloud Identity Free sign-up (`sku=identitybasic`) with `admin1`; verify `<domain>` by TXT in
   Cloudflare DNS.
3. Create `admin2` (super admin), `<person>`, `test-approver`, `test-dev`; enforce 2SV (enrollment
   period for new users); create the 5 groups and members.
4. `admin1` opens the Cloud Console and accepts the terms → organization created.
5. **S3**: list org IAM, org policies and billing permissions right after creation (record).
6. Grant `organizationAdmin` and `projectCreator` to `group:gcp-admins` (once, by hand) and
   confirm `admin2` can act.
6a. **S2**: the current Gmail billing admin grants `billing.admin` on the billing account to
   `group:gcp-admins`; confirm `admin1` sees the account.
7. **S1**: send mail from outside to a user address and to a group address; record delivery.

Acceptance: both super admins sign in with 2SV; mail to every user address arrives; org exists;
`admin1`/`admin2` hold the bootstrap roles through the group; S1, S2, S3 recorded.

### Phase 2 — Approval change in code (before rebuild)

1. **S5** on the public repo: CODEOWNERS review requirement and an org-admin-only bypass in a
   ruleset on GitHub Free (test on a scratch branch rule, then remove).
2. Code + docs changes of section 3 and the new stage 0 grants of section 2 (one PR, reviewed).
3. `tofu validate` and a local plan against the **new** org after phase 3 step 1 (no old-org apply).

Acceptance: S5 recorded; PR merged with review; no old-org resources changed.

### Phase 3 — Rebuild from zero (runbooks 01–04 as written)

1. Re-check trial days and credit (R5-4). Stage 0 tfvars: `<new-prefix>`, new org, admins group.
2. Runbook 02: stage 0 applied locally by `admin1` (gcloud config of `admin1`).
3. Runbook 03: new GitHub connection + triggers; update ruleset required checks (section 3).
4. Runbook 04: stages 1–3 via PR → review → merge → apply (no Cloud Build approval).
5. demo-api / demo-web: new WIF provider and Artifact Registry path; one successful deploy each.
6. Foundation acceptance 1–8 again with the new accounts; **S4** (PAM request email to
   `test-approver`, budget email target).

Every runbook gap found is fixed in the runbook/design in the same PR series, not worked around.

### Phase 4 — Teardown and handover

1. Remove the old Gmail `billing.admin` from the billing account after `gcp-admins` is verified.
2. Write `ops/change-person.md`; exercise it with `test-dev`: join `gcp-developers` → read works →
   leave (remove from group, suspend) → access denied.
3. Update `foundation-*` docs and README for the new identity model; T7-12 closed by S4 result.

## 5. Verification (each maps to a requirement acceptance item)

| # | Check | Why it is needed |
|---|---|---|
| V1 | IAM on org, folders, seed, env projects, billing account: no `user:` member except auto grants of super admins (S3) | Acceptance 1 |
| V2 | Foundation acceptance 1–8 in the new org | Acceptance 2 |
| V3 | `test-dev` join/leave with `testIamPermissions` before and after | Acceptance 3 |
| V4 | PAM request email received by `test-approver`; budget channel verified | Acceptance 4 |
| V5 | 2 Cloudflare Super Administrators, 2 super admins, 2 GitHub org owners listed | Acceptance 5 |
| V6 | Merged `stages/` PR applies without approval; author cannot merge without code-owner approval | Acceptance 6 |

No other checks: build success alone is not accepted as evidence.

## 6. Risks

| Risk | Handling |
|---|---|
| Group mail not delivered with Cloudflare MX (S1 fails) | Notifications use user addresses (R2-2) |
| Domain account cannot be billing admin of the trial account (S2 fails) | Keep the Gmail admin until the business billing account (D5 later); record as exception |
| Billing project quota | Old projects unlinked in phase 0 (0 linked before the rebuild) |
| Trial ends mid-migration | Re-check at phase 3 step 1; upgrade first if < 3 weeks left |
| GitHub becomes the only gate | 2FA, 2 owners, CODEOWNERS, no author bypass (R10) |
| Old org deletion delayed by pending project deletion | Not on the acceptance path |

## 7. Delegation plan

| Task | Who | Output |
|---|---|---|
| Phase 1 steps 1–4, 6 (Cloudflare, Admin console, Console) | User (browser) with runbook 00 written by main agent | Screens/answers; main agent verifies with gcloud |
| S3, S1 checks, V1 | system-execution-agent (read-only) | Command output, masked |
| S5 | User (GitHub UI) + main agent check | Ruleset result |
| Phase 2 code changes | system-execution-agent | Diff, `tofu validate`, no apply |
| Phase 3 stage 0 apply, demo app switch | system-execution-agent with the `admin1` gcloud config | Apply output, verification |
| Phase 3 PR/merge (runbook 04) | User (GitHub) | Builds checked by main agent |
| Phase 0 deletions | system-execution-agent (old Org Owner config), user confirmed 2026-11-25 | Deletion evidence |
| All docs (runbook 00, change-person, design/tasks updates) | Main agent | — |
