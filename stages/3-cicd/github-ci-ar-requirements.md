# GitHub CI → Artifact Registry — Requirements

Related: `stages/2-environments/gcp-iam-bootstrap-requirements.md` (org, folders, `<PREFIX>-app-{prod,nonprod}` projects, groups).

## Goal

Development teams work in a GitHub Organization. GitHub Actions builds container images and
pushes them to GCP Artifact Registry (AR) using a keyless, workflow-scoped identity.
The setup must support many GitHub repos and many images per repo.

## Context / Constraints

- GitHub plan: **Free** organization. App repos are **public** (needed for Environments
  required reviewers / deployment rules on Free). Everything in app repos and their Actions
  logs is public.
- GitHub org Teams are available on Free (verified in GitHub docs).
- GCP projects already exist: `<PREFIX>-app-nonprod`, `<PREFIX>-app-prod`.
- Developers' Google accounts / groups are NOT used to push images. `developers` group
  permissions on GCP are unchanged.
- No service account keys or any long-lived credential stored in GitHub.
- GCP-side setup is IaC (OpenTofu) in this repo (`cloud-ops`, public), applied by an org admin.
  Environment values (org IDs, project IDs, GitHub numeric IDs) are not committed.
- GitHub-side setup (org, teams, rulesets, environments, secrets) is done manually by the
  user, following a document written by the agent.

## Names

| Item | Value |
|---|---|
| GitHub org | `<PREFIX>-eng` (user confirmed concrete name locally; must be globally unique) |
| Demo repo 1 | `demo-api`: images `api`, `worker` |
| Demo repo 2 | `demo-web`: image `web` |
| Local app path | `cloud-ops/apps/<repo>/` (each is its own git repo; `apps/` is git-ignored) |

## Flow

| GitHub event | Action |
|---|---|
| Pull request | Build images only. No GCP authentication. |
| Push to `main` | Build every image of the repo, push to **nonprod** AR, tag = full git SHA. |
| Push tag `v*` | **Promote**: copy the nonprod image of the tag's commit SHA to **prod** AR by digest (no rebuild), tag = the `v*` tag. Fails if the nonprod image does not exist. Runs on the GitHub runner. |

Prod AR receives images only through promote; nothing is built for prod.

## GCP Artifact Registry

- One AR Docker repository per GitHub repo per env (nonprod project, prod project).
  Images of the same GitHub repo are packages in that AR repository:
  `<region>-docker.pkg.dev/<project>/<github-repo>/<image>:<tag>`.
  Reason: AR IAM granularity is the repository; per-repo AR isolates GitHub repos from each other.
- Region is a variable, default `us-central1` (AR storage price is the same in all regions;
  co-locate with future runtime to avoid transfer cost).
- Prod AR repositories have immutable tags.

## Identity

- Workload Identity Federation (WIF) with GitHub OIDC. **Direct WIF** (no service account)
  is preferred; fall back to service account impersonation only if a spike shows AR push or
  promote does not work with direct WIF.
- WIF provider accepts only tokens from the GitHub org's numeric ID.
- Authorization is bound to GitHub repo numeric ID + GitHub Environment:
  - Environment `nonprod`: deployable only from `main`; may write nonprod AR of that repo.
  - Environment `prod`: deployable only from `v*` tags, required reviewer = `devops` team;
    may read nonprod AR and write prod AR of that repo.
- Onboarding a new repo = add it to a list in tfvars and admin runs `tofu apply`.
  Repos not in the list are denied.

## GitHub (manual, documented by agent)

- Org on Free plan; Teams `developers` (write on app repos), `devops` (maintain).
- Rulesets: protect `main`; restrict creation of `v*` tags.
- Environments `nonprod`, `prod` as above.
- Actions: workflows from fork PRs require approval.
- Secrets for GCP identifiers; how to get org/repo numeric IDs.

## Public log hygiene

- GCP identifiers (project ID, project number, WIF provider path, AR host path) are stored
  as GitHub **Secrets** (masked in logs); derived strings are masked with `::add-mask::`.
- Masking is exact-string only, so it is verified by scanning the actual public logs.

## Acceptance (requirement level)

1. Push to `main` of `demo-api` → nonprod AR has `api` and `worker` tagged with the SHA.
2. Tag `v*` → prod AR has the image with the same digest as nonprod.
3. Tag on a commit with no nonprod image → promote fails.
4. `demo-web` not onboarded → push denied; after onboarding → push succeeds.
5. A job not in an allowed Environment (e.g. other branch) is denied by WIF.
6. An existing prod tag cannot be overwritten.
7. Public Actions logs contain no project ID / project number (grep = 0 hits).
8. No environment-specific values committed to `cloud-ops`.

## To be verified in design (spike)

- Direct WIF works for `docker push` to AR and for cross-project promote.
- Whether AR supports cross-repository blob mount (avoids egress during promote).
