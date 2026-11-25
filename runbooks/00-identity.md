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

1. Cloudflare → `<domain>` → Email → Email Routing → enable (adds MX and SPF records).
2. Destination addresses: add each person's mailbox outside `<domain>` and click the
   verification link sent to it.
3. Routing rules: one custom address per user (`admin1`, `admin2`, `<person>`, `test-approver`,
   `test-dev`) → its destination. No catch-all.

Verify: send a mail from another mailbox to `admin1@<domain>`; it arrives at the destination.

## 2. Cloud Identity Free sign-up

1. Open `https://workspace.google.com/gcpidentity/signup?sku=identitybasic`.
2. Business info: your company name; current email: a mailbox outside `<domain>`.
3. Domain: `<domain>`. First user: `admin1@<domain>` (becomes super admin). Strong password.
4. Verify the domain: copy the TXT record shown, add it in Cloudflare DNS for `<domain>`, then
   click Verify in the Admin console (admin.google.com). DNS can take minutes.
5. `admin1`: set up 2-Step Verification (security key or authenticator) and a recovery email /
   phone outside `<domain>`.

Verify: Admin console → Account → Domains shows `<domain>` verified.

## 3. Accounts, 2SV and groups (Admin console as `admin1`)

1. Directory → Users → Add new user: `admin2`, `<person>`, `test-approver`, `test-dev`.
   Hand each password to its user (or keep test personas yourself).
2. Account → Admin roles → Super Admin → assign `admin2`. `admin2` signs in, sets 2SV and a
   recovery email / phone outside `<domain>`.
3. Security → Authentication → 2-step verification: allow, enforcement **On**, new user
   enrollment period 1 week.
4. Directory → Groups → Create: the 5 groups. Members:

| Group | Members |
|---|---|
| `gcp-admins` | `admin1`, `admin2` |
| `gcp-billing` | `admin1`, `admin2` |
| `gcp-devops` | `<person>` |
| `gcp-approvers` | `test-approver` |
| `gcp-developers` | `test-dev` (added later in acceptance tests) |

Verify: each user signs in once with 2SV.

## 4. Create the organization

1. As `admin1`, open `https://console.cloud.google.com/` and accept the terms. The organization
   `<domain>` is created.
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
them afterwards.

```bash
for r in roles/resourcemanager.organizationAdmin roles/resourcemanager.projectCreator; do
  gcloud organizations add-iam-policy-binding $ORG --configuration=<cfg-admin1> \
    --member="group:gcp-admins@<domain>" --role=$r --condition=None
done
```

Billing (spike S2): the current billing account administrator (outside `<domain>`) grants
`roles/billing.admin` on the billing account to `group:gcp-admins@<domain>`
(Billing → Account management → Add principal, or
`gcloud billing accounts add-iam-policy-binding <BILLING_ACCOUNT_ID> --member=group:gcp-admins@<domain> --role=roles/billing.admin`).

Verify: as `admin2` (own gcloud config), `gcloud organizations get-iam-policy $ORG` works, and
`gcloud billing accounts list --configuration=<cfg-admin1>` shows the billing account.

## 6. Group mail (spike S1)

Send a mail from another mailbox to `gcp-admins@<domain>` and to `admin2@<domain>`. Record
which ones arrive. Google Cloud notifications use user addresses unless group mail arrives.
