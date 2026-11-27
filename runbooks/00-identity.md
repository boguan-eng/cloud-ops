# 00 — Domain, mail and Cloud Identity

**Who:** the person who owns the domain (Cloudflare account) and becomes `admin1`.
**Prerequisites:** `<domain>` registered at Cloudflare; Cloudflare 2FA on; a second Cloudflare
Super Administrator whose email is outside `<domain>`. A Cloud Billing account you administer.
**Result:** a Google Cloud organization owned by `<domain>`, accounts and groups, mail forwarding.
**Next:** [01-github-org.md](01-github-org.md).

Names (see `stages/identity-migration-design.md` section 1): `admin1`, `admin2` (super admins,
break-glass), one account per person named after the person, `test-approver`, `test-dev`;
groups `gcp-admins`, `gcp-devops`, `gcp-developers`, `gcp-approvers`, `gcp-billing`.
Console labels can change; if a path differs, fix this runbook.

## 1. Mail forwarding (Cloudflare)

Cloud Identity Free has no mailbox; mail to `user@<domain>` is forwarded by Cloudflare.

Dashboard paths are from the Cloudflare docs (Email Service, updated 2026-11-24); direct link:
`https://dash.cloudflare.com/?to=/:account/email-service/routing`.

1. **Onboard the domain:** Compute → Email Service → Email Routing → **Onboard Domain** →
   select `<domain>` → accept the DNS records it adds (MX, SPF TXT) → Done.
2. **Destination addresses:** Compute → Email Service → Email Routing → **Destination
   Addresses** → enter a mailbox outside `<domain>` → submit → open the mail from Cloudflare in
   that mailbox and select **Verify email address**. Repeat per destination. Rules stay disabled
   until their destination is verified.
3. **Routing rules:** Compute → Email Service → Email Routing → select `<domain>` → **Routing
   Rules** tab → **Create routing rule** → Email pattern = local part (`admin1`) + `<domain>`,
   Action = **Send to an email**, Destination = the verified mailbox → Save. (Other actions:
   Send to a Worker, Drop — not used.) One rule per user address (`admin1`, `admin2`,
   `<person>`, `test-approver`, `test-dev`). No rule for group addresses (S1 tests them).
   Leave the catch-all rule off.

Destinations: in a real team each address goes to the person who holds the account. In this
practice setup (decided 2026-11-25) two mailboxes are used: the admins' holder for `admin1` /
`admin2`, the devops person's mailbox for the other three. Recovery emails (section 2/3) are a
separate setting: **the two super admins must have different recovery emails**, and neither may
be the devops person's mailbox.

Verify: send a mail to each user address **from a mailbox other than its destination** (some
providers drop mail that appears to come from the receiving account); it arrives.

## 2. Cloud Identity Free sign-up

Screens as observed on 2026-11-25 (labels depend on the console language).

1. Open `https://workspace.google.com/gcpidentity/signup?sku=identitybasic`.
2. Business name: your company name. Only a label users see; changeable later (Admin console →
   Account → Account settings → Profile → Name). The Google Cloud organization's display name
   comes from the primary domain, not from this name.
3. Contact info (name, current email): the person who will hold `admin1` (the name becomes that
   user's display name) and **that person's mailbox outside `<domain>`** (the one `admin1@`
   forwards to). Sign-up mails go there.
4. Domain: `<domain>`. First user: `admin1@<domain>` (becomes super admin), strong password.
5. Verify the domain. Google detects Cloudflare as the DNS host and offers to add the TXT record
   through Cloudflare:
   1. Choose Cloudflare → sign in → **Authorize**. Observed: Cloudflare then showed
      `Error 401 Unauthorized`, but the record had been written.
   2. Check the record is public:
      `curl -s "https://dns.google/resolve?name=<domain>&type=TXT"` → expect
      `google-site-verification=...` next to the Email Routing `v=spf1 ...` record.
      Only if it is missing: copy the value shown by Google and add it in Cloudflare → `<domain>`
      → DNS → Records → Add record (Type `TXT`, Name `@`, Content = value). Keep the SPF record.
   3. Back in the Admin console verify page (admin.google.com → Account → Domains → Manage
      domains → Verify domain), choose the **other / manual** option instead of Cloudflare, tick
      the confirmation checkbox, confirm. Usually minutes; Google allows up to 72 hours.
6. `admin1` (myaccount.google.com → Security): turn on 2-Step Verification (authenticator or
   security key); recovery email = the holder's mailbox outside `<domain>`.

Verify: Admin console → Account → Domains → Manage domains shows `<domain>` verified.

## 3. Accounts, 2SV and groups (Admin console as `admin1`)

Order matters: every account turns on 2SV **before** enforcement is switched on (step 4).

1. Directory → Users → **Add new user**, one per account: `admin2`, `<person>`,
   `test-approver`, `test-dev`. Fill first/last name and primary email; set a password (or let
   Google generate one) and give it to the holder; secondary email = the holder's mailbox
   outside `<domain>` if the form offers it.
2. Account → Admin roles → **Super Admin** → assign `admin2`.
3. Each user signs in once (first sign-in asks to change the password), then
   myaccount.google.com → Security: 2-Step Verification on, recovery email outside `<domain>`.
   Recovery emails: `admin1` and `admin2` must differ; neither is the devops person's mailbox.
4. Security → Authentication → 2-step verification: allow users to turn it on, enforcement
   **On**, new user enrollment period 1 week → Save.
5. Directory → Groups → **Create group**, for each of the 5 groups: name and email
   (`gcp-admins@<domain>`, ...), owner `admin1`. Access type: keep the preselected one (observed
   2026-11-25: Public / Team / Announcement only / Restricted / Custom; Custom disabled);
   **not Restricted**, which blocks non-member senders and would skew S1. No per-group
   "members outside the organization" switch was shown; add only `<domain>` members.
   Members:

| Group | Members |
|---|---|
| `gcp-admins` | `admin1`, `admin2` |
| `gcp-billing` | `admin1`, `admin2` |
| `gcp-devops` | `<person>` |
| `gcp-approvers` | `test-approver` |
| `gcp-developers` | none yet (`test-dev` is added in the acceptance tests) |

Verify: Directory → Users lists 5 users with 2SV enrolled; Directory → Groups lists 5 groups
with the members above; mail to `admin2@` and `<person>@` arrives (send from a mailbox other
than the destination).

## 4. Create the organization

1. As `admin1`, open `https://console.cloud.google.com/` and accept the terms. The organization
   `<domain>` is created. The console project picker may still show "No organization"
   (observed 2026-11-25); check with `gcloud organizations list` in step 2 instead. Do not
   create a project to force it (the project would be owned by a user, against R4).
2. gcloud configurations (names are local; do not commit them):

```bash
gcloud config configurations create <cfg-admin1> --no-activate
gcloud auth login --configuration=<cfg-admin1>      # sign in as admin1@<domain>
gcloud organizations list --configuration=<cfg-admin1>
```

3. Record (spike S3) what exists right after creation:

```bash
ORG=<org id>
gcloud organizations get-iam-policy $ORG --configuration=<cfg-admin1> \
  --flatten='bindings[].members' --format='value(bindings.role,bindings.members)'
gcloud org-policies list --organization=$ORG --configuration=<cfg-admin1>
```

## 5. Bootstrap roles to the admins group

Stage 0 needs these roles before it can run, so they are granted once by hand; stage 0 declares
them afterwards. Then the defaults found in S3 are removed (stage 1 also declares the removal).

1. Grant the group (as `admin1`):

```bash
for r in roles/resourcemanager.organizationAdmin roles/resourcemanager.projectCreator; do
  gcloud organizations add-iam-policy-binding $ORG --configuration=<cfg-admin1> \
    --member="group:gcp-admins@<domain>" --role=$r --condition=None
done
```

2. Remove the domain-wide defaults (S3, 2026-11-25: every domain user could create projects and
   billing accounts):

```bash
gcloud organizations remove-iam-policy-binding $ORG --configuration=<cfg-admin1> \
  --member="domain:<domain>" --role=roles/resourcemanager.projectCreator
gcloud organizations remove-iam-policy-binding $ORG --configuration=<cfg-admin1> \
  --member="domain:<domain>" --role=roles/billing.creator
```

3. Billing (spike S2): the current billing account administrator (outside `<domain>`) grants
   `roles/billing.admin` on the billing account to `group:gcp-admins@<domain>`
   (Billing → Account management → Add principal, or
   `gcloud billing accounts add-iam-policy-binding <BILLING_ACCOUNT_ID> --member=group:gcp-admins@<domain> --role=roles/billing.admin`).
4. Prove the group grant works with an account that has no user binding: `admin2` signs in to
   its own gcloud configuration; `gcloud organizations get-iam-policy $ORG` succeeds and
   `gcloud billing accounts list` shows the billing account.
5. Only after step 4: remove the creator's user binding (`organizationAdmin` on `user:admin1`,
   granted automatically at org creation):

```bash
gcloud organizations remove-iam-policy-binding $ORG --configuration=<cfg-admin1> \
  --member="user:admin1@<domain>" --role=roles/resourcemanager.organizationAdmin
```

Verify: org IAM has no `user:` or `domain:` member; `admin1` still reads org IAM (through the
group).
6. After step 4: remove the billing administrator outside `<domain>` (R4: no individual
   holds billing access). The payment method and invoices are managed separately in the
   payments profile and are not changed by this.

```bash
gcloud billing accounts remove-iam-policy-binding <BILLING_ACCOUNT_ID> --configuration=<cfg-admin1> \
  --member="user:<outside-admin>" --role=roles/billing.admin
```

Verify: billing account IAM has no `user:` member; `admin1` still reads it (through the group);
`gcloud billing accounts list` as the outside account no longer shows it (allow ~1 min).

## 6. Group mail (spike S1)

Send a mail from another mailbox to `gcp-admins@<domain>` and to `admin2@<domain>`. Record
which ones arrive. Google Cloud notifications use user addresses unless group mail arrives.

Result 2026-11-25: the group address bounces ("Address not found"): MX points to Cloudflare,
which has no rule for group addresses. Google Cloud notifications therefore go to user
addresses.
