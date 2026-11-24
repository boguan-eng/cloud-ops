# GitHub Organization — Runbook (org owner)

One-time setup of the GitHub organization used by development teams. Per-repo CI setup is in
`stages/3-cicd/ar/RUNBOOK.md`. Never commit real values (IDs, emails).

Placeholders: `<ORG>` = GitHub org name.

## 1. Create the organization

1. https://github.com/account/organizations/new → plan **Free** → name `<ORG>`
   (globally unique; check with `curl -s -o /dev/null -w '%{http_code}' https://api.github.com/users/<ORG>`,
   `404` = available).
2. App repos are **public**: on Free, Environments (required reviewers, deployment branch/tag
   rules, environment secrets) and rulesets are only available for public repos.
   Everything in the repos and their Actions logs is public.

## 2. Org Actions settings

Org → Settings → Actions → General:
- *Fork pull request workflows from outside collaborators*: **Require approval for all external contributors**.
- *Workflow permissions*: **Read repository contents and packages permissions**.

## 3. Teams (available on Free)

Org → Teams → **New team** (the create page has no member field):
- `developers`: app developers.
- `devops`: operators; `prod` environment reviewers and release-tag bypass.

Add members: team page → **Members** tab → **Add a member** → username → Enter →
**Add `<user>` to `<team>`**. Add yourself to `devops` if you approve prod promotions.

Repo access is granted per repo when onboarding (see `stages/3-cicd/ar/RUNBOOK.md`):
`developers` = **Write**, `devops` = **Maintain**.

## 4. Numeric org ID

Needed by the org admin for `stages/3-cicd/wif/terraform.tfvars` (`github_org_id`):

```bash
curl -s https://api.github.com/orgs/<ORG> | jq .id
```

The numeric ID (not the name) is used in GCP WIF conditions, so a re-registered org name
cannot impersonate the org.
