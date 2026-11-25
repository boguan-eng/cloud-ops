# Identity Migration (Cloud Identity) — Requirements

Status: draft 2026-11-25, waiting for user confirmation.
Related: [foundation-requirements.md](foundation-requirements.md), [1-org/identity-options.md](1-org/identity-options.md).
Placeholders only in this repo: `<domain>`, `<prefix>`, `<new-prefix>`; real values stay out of git.

Admin roles in three separate systems (do not mix them up):

| Term | System | Controls |
|---|---|---|
| Cloudflare Super Administrator | Cloudflare account (member role) | Domain registration, DNS, mail forwarding |
| Cloud Identity super admin | Google Admin console | Users, groups, 2SV, domain verification |
| Org Owner / organization admin | Google Cloud IAM | Org, folders, projects, IAM |

## Goal

Move the foundation from a standalone organization (consumer Gmail accounts, no domain) to a new
organization owned by a domain through **Cloud Identity Free**, so that accounts, groups and the
organization belong to the company and not to a person. People who join or leave change group
membership or accounts; no IAM binding has to follow a person. Do this before chapter 2.

## Context (facts, official pages read 2026-11-25)

| Fact | Source |
|---|---|
| Current org is standalone: `directoryCustomerId` is empty; Org Owners are personal Gmail accounts. The primary owner also holds 8 hand-granted org roles; the seed project `owner` and the billing account `billing.admin` are personal accounts. | Checked with gcloud 2026-11-25 |
| Cloud Identity Free: no license fee, 50 users by default (increase on request), needs a verified domain (TXT record). Includes user lifecycle, groups, 2-Step Verification and security-key enforcement, admin audit logs. | cloud.google.com/identity/pricing, docs …/identity/docs/editions |
| Cloud Identity Free has **no Gmail inbox**; mail to `user@<domain>` needs a third-party MX or forwarding. | docs …/identity/docs/how-to/set-up-cloud-identity-admin |
| One Cloud Identity account = one organization resource; products are separated by folders/projects. App hostnames are DNS records and need no extra identity domain. | knowledge.workspace.google.com …/faq-for-multiple-domains |
| A new organization enforces `iam.allowedPolicyMemberDomains` (only the own domain) by default, plus the other secure-by-default policies. | docs …/organization-policy/manage-baseline-constraints |
| A Gmail-created standalone org has no documented in-place claim; folders cannot move across orgs. | docs …/resource-manager/docs/standalone-organization-overview |
| The current billing account is a **Free Trial** account with **no parent organization**. A project in any org can link to it with `billing.user` (account) + `billing.projectManager` (project). A second Free Trial is not allowed. When the trial ends without upgrade, resources stop. | gcloud 2026-11-25; docs …/billing/docs/concepts; docs …/free/docs/free-cloud-features |
| Cloudflare: Registrar at cost; Email Routing free, needs Cloudflare DNS, one verified destination per rule; multiple account members on Free; 60-day transfer lock after registration. | developers.cloudflare.com (registrar, email-service, fundamentals) |
| A standalone org can be deleted by its Organization Owner after its projects/folders are gone (30-day recovery). | docs …/resource-manager/docs/delete-standalone-org |

## Decisions (user, 2026-11-25)

| # | Decision |
|---|---|
| D1 | Use Cloud Identity Free with the domain `<domain>` (chosen; not in this repo). |
| D2 | Register the domain at Cloudflare. DNS and mail forwarding on Cloudflare. |
| D3 | Cloudflare account login: the devops person's existing personal Gmail; second Cloudflare Super Administrator: the primary Org Owner's personal Gmail. Both outside `<domain>`, so recovery does not depend on the domain. |
| D4 | **Rebuild from zero** in the new org with the runbooks; delete the old setup **first** (user, 2026-11-25: nothing in it must be kept; demo apps may stop). No project move. |
| D5 | Keep the current Free Trial billing account (no parent) for now and link the new projects to it. Later (trial end or a real company): new billing account with a **business** payments profile in the new org — deferred. |
| D6 | Accounts: 2 super admins (break-glass; also Org Owners); one daily account per person and role. |
| D7 | New project ID prefix `<new-prefix>` (neo-related, no old prefix). |
| D9 | Review and approval of infrastructure changes are **only in GitHub**; Cloud Build apply runs on merge without manual approval (R10). Done after Cloud Identity, before the rebuild. |
| D8 | Trial has about 2 months left (checked 2026-11-25): enough for the migration; re-check before R6. |

## Requirements

### R1 Domain and Cloudflare
1. `<domain>` registered at Cloudflare, auto-renew on, accurate registrant data.
2. Cloudflare account: 2FA on (security key or TOTP); a **second Cloudflare Super Administrator member**
   so the domain does not depend on one person (D3 risk); handover documented (R8).

### R2 Mail
1. Every Cloud Identity user address forwards to that person's verified mailbox (Cloudflare Email
   Routing, one rule per address).
2. Notification targets are **user addresses**; group addresses are used for mail only if the
   spike S1 proves group mail is delivered.

### R3 Cloud Identity and accounts
1. Cloud Identity Free signed up for `<domain>`, domain verified by TXT in Cloudflare DNS.
2. Accounts (names decided at design time):

| Account | Purpose | Daily use |
|---|---|---|
| super admin 1, super admin 2 | Cloud Identity super admin and Org Owner; break-glass and bootstrap | No |
| devops person | devops group | Yes |
| approver | approvers group (separate from devops) | When approving |
| developer (test) | developers group, acceptance tests | Tests only |

3. 2-Step Verification enforced for all users; super admins use security keys if available.
4. Groups are Cloud Identity groups: devops, developers, approvers, billing, admins.
   `admins` holds only the 2 super admins.

### R4 No IAM binding on an individual human
1. Org bootstrap roles, the seed project admin role and billing account admin are granted to
   **groups** (admins / billing), not to a person. Exception: what Google grants automatically
   to Org Owners or super admins.
2. Default grants that a new org gives to the whole domain (if any) are reviewed and removed
   unless required (verify in spike S3).

### R5 Billing
1. New projects link to the current Free Trial billing account (D5).
2. At least 2 billing account administrators through the admins group (official recommendation);
   the old personal Gmail admin is removed after the new admins are verified.
3. Budget and its email target recreated by stage 1 in the new org.
4. The migration must finish before the trial ends (about 2 months from 2026-11-25), or the
   account is upgraded first.

### R6 Rebuild from zero
1. A new runbook step before runbook 01 covers: domain, Cloudflare, mail forwarding, Cloud
   Identity sign-up, accounts, groups, 2SV.
2. Runbooks 01–04 are followed as written in the new org (with `<new-prefix>` project IDs);
   every gap found is fixed in the runbook or design, not worked around.
3. Same operating model, stages and acceptance as Foundation (foundation-requirements.md),
   except the approval change in R10.
4. demo-api and demo-web repos are switched to the new WIF provider and Artifact Registry.

### R7 Old organization teardown
1. Before the rebuild: delete the old projects, folders, budget and old groups; the old org
   itself is deleted by its Organization Owner once the projects are purged (30 days).
2. The billing account stays (no parent); old Gmail IAM grants on it are removed.
3. Old GitHub triggers/connection go with the old seed; the old required checks are removed from
   the ruleset until the new ones exist.

### R8 People change (handover)
1. Runbook `ops/change-person.md`: join and leave for each role, including super admin,
   Cloudflare member, billing admin and payment method. Order: add and verify the new person
   first, then remove the old one; a leaver is removed from groups and suspended/deleted
   (suspension alone keeps IAM bindings).

### R9 Public repo
1. No domain, account address, prefix, project ID or billing ID in commits.

### R10 Approval only in GitHub (D9)
1. Stages 1–3 apply runs automatically after merge to `main`; Cloud Build manual approval is removed.
2. Ruleset on `main`: at least 1 approval; changes under `stages/` need a CODEOWNERS review.
   Author bypass (decision B) is **removed**; the only bypass is the Org Owner for emergencies,
   recorded afterwards in the PR. Reason: without the Cloud Build gate, anyone who can bypass can
   apply without a second person.
3. GitHub org: at least 2 owners, 2FA required; GitHub org owners can change the ruleset, so they
   count as top-level admins and are covered by `ops/change-person.md`.
4. The approvers group only approves PAM grants; `ops/approve-apply.md` is removed and
   `ops/change-approver.md` is rewritten.
5. Design decision updated: approval records are PR reviews in GitHub; GCP records the apply build.

## Order

0. Teardown of the old setup (R7).
1. Identity: domain, Cloudflare, mail, Cloud Identity, accounts, groups (R1–R3, spikes S1, S3).
2. Approval change in code and docs (R10, spike S5), before the rebuild.
3. Rebuild from zero (R4–R6, spikes S2, S4).
4. Handover runbook exercised (R8).

## Spikes (verify before design is final)

| # | Question | Why |
|---|---|---|
| S1 | Is mail to a Cloud Identity **group** address delivered when MX points to Cloudflare? | Decides R2-2 |
| S2 | Can a domain account be added as admin of the Free Trial billing account (no parent)? | R5-2 |
| S3 | Which IAM grants does the new org have at creation (domain-wide or creator)? | R4-2 |
| S4 | Do PAM request and budget emails reach the forwarded mailboxes? | Closes T7-12 |
| S5 | Can a public repo on GitHub Free require CODEOWNERS review in a ruleset, and can bypass be limited to org owners? | R10-2 |

## Out of scope / deferred

- Business payments profile billing account (D5 later).
- Premium Cloud Identity features (context-aware access, advanced device management).
- SSO to other SaaS. GitHub accounts are not moved to `<domain>`; only R10-3 applies to them.

## Acceptance (requirement level)

1. Old projects deleted (old org deletion follows after the 30-day purge, not on this path);
   nothing in the new org depends on a personal Gmail account
   (IAM on org, folders, projects, billing account checked).
2. Foundation acceptance 1–8 pass again in the new org.
3. A test account joins and leaves via `ops/change-person.md`; after leaving it has no access.
4. PAM request email reaches the approver; budget alert email target is reachable (S4).
5. Domain renewal, Cloudflare and super admin access do not depend on one person (2 members,
   2 super admins, 2 GitHub org owners).
6. A merged PR under `stages/` applies without Cloud Build approval; a PR without the required
   CODEOWNERS approval cannot be merged by its author.
