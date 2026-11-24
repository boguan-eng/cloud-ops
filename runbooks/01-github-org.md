# 01 — GitHub Organization

**Who:** the company owner, signed in to GitHub (becomes the GitHub org **Owner**).
**Prerequisites:** none. **Next:** [02-stage0-bootstrap.md](02-stage0-bootstrap.md).

Placeholders: `<ORG>` = GitHub org name. Never commit real values.

## Security model

| Item | Setting | Why |
|---|---|---|
| Who creates the org | The company owner (same person as the GCP Org Owner) → GitHub org **Owner** | Highest privilege stays with the accountable person; not used day to day |
| Number of org owners | 2 (owner + backup) | A single lost owner account makes the org unrecoverable |
| Two-factor authentication | **Required** for all members | Available on Free. GCP without a domain cannot enforce 2SV; GitHub can |
| Who creates repos | **Owners only** | New repos are onboarded to GCP through a `cloud-ops` PR anyway; prevents ad-hoc public repos leaking data |
| Visibility change, delete, transfer | Owners only | Prevents accidental publication or deletion |
| Base permissions | **No permission** | All access is granted through teams |
| `cloud-ops` access | `devops` = **Write**; `developers` = none (public, readable anyway); owners = Admin | Infra changes only by devops via PR + branch protection |
| App repo access | `developers` = **Write**, `devops` = **Maintain** | See `stages/3-cicd/ar/RUNBOOK.md` |
| Non-technical approver | No GitHub access | Approves infra applies in the GCP Console |
| Cloud Build GitHub App | Installed by an owner, **only on `cloud-ops`** (runbook 03) | Limits what the stored OAuth token can reach |

Repos are **public**: on GitHub Free, rulesets/branch protection and Environments (required
reviewers, deployment rules, environment secrets) work only on public repos. Everything in
the repos and their Actions logs is public.

## 1. Create the organization

1. https://github.com/account/organizations/new → plan **Free** → name `<ORG>`
   (check availability: `curl -s -o /dev/null -w '%{http_code}' https://api.github.com/users/<ORG>`,
   `404` = available).
2. Add the backup owner: org → **People** → **Invite member** → role **Owner**.

## 2. Org security settings

Org → **Settings**:
- **Authentication security** → **Require two-factor authentication for everyone in the
  `<ORG>` organization** → **Save**. Members without 2FA are removed; ask them to enable it first.
- **Member privileges**:
  - *Base permissions*: **No permission**.
  - *Repository creation*: uncheck **Public** and **Private**.
  - *Repository visibility change*, *Repository deletion and transfer*: unchecked.
- **Actions** → **General**:
  - *Fork pull request workflows from outside collaborators*: **Require approval for all external contributors**.
  - *Workflow permissions*: **Read repository contents and packages permissions**.

## 3. Teams

Org → **Teams** → **New team** (the create page has no member field):
- `developers`: app developers.
- `devops`: operators; `prod` environment reviewers; the only team that writes `cloud-ops`.

Add members: team page → **Members** tab → **Add a member** → username → Enter →
**Add `<user>` to `<team>`**.

## 4. Numeric org ID

Needed later for `stages/3-cicd/wif/terraform.tfvars` (`github_org_id`). The numeric ID (not
the name) is used in GCP WIF conditions, so a re-registered org name cannot impersonate the org.

```bash
curl -s https://api.github.com/orgs/<ORG> | jq .id
```

## Verification

- Org → Settings → Authentication security shows 2FA required.
- Org → People: 2 owners. Teams `devops` and `developers` exist with members.
- A member (non-owner) sees no **New** button for repositories.

**Next:** [02-stage0-bootstrap.md](02-stage0-bootstrap.md).
