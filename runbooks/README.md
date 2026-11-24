# Runbooks — Start Here

First-time setup is linear: do the numbered runbooks in order. Each one starts with
*who / which account / prerequisites* and ends with *verification* and *next*.
Never commit real values (IDs, emails); fill them in shell variables or git-ignored files.

```
 01 GitHub org            02 Stage 0 bootstrap        03 cloud-ops repo + pipeline      04 Migrate stages
 (GitHub org owner)  ──▶  (GCP Org Owner, or     ──▶  (GitHub org owner +          ──▶  (GCP Org Owner)
                           devops w/ temp grant)       GCP Org Owner)
 org, 2FA, teams          seed project, state         push repo, ruleset,              existing stages →
                          bucket, IaC SAs,            Cloud Build connection,          GCS state, pipeline
                          builder image               triggers                         applies from now on
```

| # | Runbook | Who (account) | Result |
|---|---|---|---|
| 01 | [01-github-org.md](01-github-org.md) | GitHub org owner | Org with 2FA, owner-only repo creation, teams `devops` / `developers` |
| 02 | [02-stage0-bootstrap.md](02-stage0-bootstrap.md) | GCP Org Owner (method A) or a devops member with temporary elevation (method B) | Seed project, state bucket, builder image, 4 IaC service accounts |
| 03 | [03-cloud-ops-repo.md](03-cloud-ops-repo.md) | GitHub org owner (browser) + GCP Org Owner (CLI) | Public `cloud-ops` with protected `main`; Cloud Build connection; 8 triggers |
| 04 | `04-migrate-stages.md` (to be written in task T5) | GCP Org Owner | All stages on GCS state; changes go through PR → plan → approval → apply |

After setup, all changes are pull requests to `cloud-ops`:
[ops/change-via-pr.md](ops/change-via-pr.md) (author, reviewer, merge); the approver follows [ops/approve-apply.md](ops/approve-apply.md). Per-stage technical details are in
`stages/<stage>/RUNBOOK.md`.

## Roles at a glance

| Persona | GitHub | GCP |
|---|---|---|
| Org Owner (non-technical, break-glass) | org Owner | Organization Owner; runs/approves stage 0 |
| Approver (non-technical) | none | Cloud Build Approver on the seed project; PAM approver |
| Billing viewer (non-technical) | none | Billing Account Viewer |
| devops | `devops` team (Write on `cloud-ops`) | nonprod operate; prod read-only + PAM elevation |
| developers | `developers` team (app repos) | logs / monitoring / service status, read-only |
