# Identity Migration (Cloud Identity) — Tasks

Design: [identity-migration-design.md](identity-migration-design.md). One step at a time; a step
is used by the next one only after its acceptance passes. Evidence is masked (no real values).

| # | Task | Who | Acceptance (evidence) | Result |
|---|---|---|---|---|
| M0-1 | Ruleset: remove the 4 old required checks, keep 1 approval | User (GitHub UI) | Ruleset JSON (API) shows no required status checks, 1 approval | |
| M0-2 | Delete the budget; remove billing IAM of old SAs and old billing group | system-execution-agent | `budgets list` empty; billing IAM = Gmail admin only | |
| M0-3 | Unlink billing and delete the 3 old projects (env first, seed last) | system-execution-agent | 0 linked projects; 3 projects `DELETE_REQUESTED` | |
| M0-4 | Delete old folders if allowed; delete 5 old consumer groups | agent / user | Folder list result recorded; groups gone | |
| M1-1 | Cloudflare Email Routing; destination mailboxes verified (runbook 00 §1) | User | Test mail to one user address arrives | |
| M1-2 | Cloud Identity sign-up, domain verified (runbook 00 §2) | User | Admin console shows domain verified | |
| M1-3 | Users, super admin 2, 2SV enforcement, 5 groups (runbook 00 §3) | User | Users/groups list; both super admins signed in with 2SV | |
| M1-4 | Organization created; **S3** recorded (runbook 00 §4) | User + agent (read-only) | Org exists; org IAM and policies recorded | |
| M1-5 | Bootstrap roles to `gcp-admins`; **S2** billing admin (runbook 00 §5) | User | `admin2` can read org IAM; `admin1` sees the billing account | |
| M1-6 | **S1** group and user mail delivery (runbook 00 §6) | User | Delivery result per address recorded | |
| M2-1 | **S5** CODEOWNERS review + org-admin-only bypass on GitHub Free | User + main agent | Ruleset settings saved; result recorded | |
| M2-2 | R10 + section 2 code changes (stage 0), CODEOWNERS, docs | system-execution-agent + main agent (docs) | `tofu validate`; diff reviewed; PR merged with review | |
| M3-1 | Re-check trial; stage 0 tfvars for the new org; runbook 02 apply as `admin1` | system-execution-agent | Apply output; V1 partial (seed, billing) | |
| M3-2 | Runbook 03: connection, triggers, ruleset required checks | User + agent | Triggers listed; ruleset shows 4 new checks | |
| M3-3 | Runbook 04: stages 1–3 via PR, apply without approval | User (PRs) + main agent checks | 4 applies SUCCESS; checks No changes; V6 | |
| M3-4 | demo-api / demo-web switched; one deploy each | agent / user | Successful run in each repo | |
| M3-5 | Foundation acceptance 1–8 with new accounts; **S4** | agent + user | V2, V4 evidence | |
| M4-1 | Remove the Gmail billing admin (after S2 passed) | agent | V1 complete | |
| M4-2 | `ops/change-person.md`; exercise with `test-dev` | main agent + user | V3 evidence | |
| M4-3 | Update foundation docs/README for the new identity model; close T7-12 | main agent | Docs reviewed | |
| M4-4 | Delete the old org after the 30-day purge | User (old Org Owner) | Org gone (not on the acceptance path) | |
