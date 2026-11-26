# Stage 0 — Bootstrap

## What it manages

| Area | Resources |
|---|---|
| Seed project | Billing link, required APIs, and project deletion protection. |
| State and builder | Versioned GCS state bucket with uniform bucket-level access and public access prevention; immutable-tag Docker Artifact Registry for the OpenTofu builder. The operator builds and pushes the image separately. |
| IaC pipeline | Four IaC service accounts (SAs) and their IAM; a Cloud Build repository link, four PR plan triggers, four apply triggers (run on merge), and four check triggers. The GitHub App connection and `main` protection are set up separately. |
| Drift checks | `iac-check-runner`, its custom Cloud Build role and plan-SA bindings, and four daily Cloud Scheduler jobs. |

## Concept and how it works

- An **admin** (member of `gcp-admins`) runs OpenTofu and gcloud locally (Cloud Shell is fine). Optionally, a devops member can do the initial setup under temporary grants; an admin removes the grants afterward. The creator's automatic seed project Owner binding is removed by `seed_creator_principal`.
- Start with local state, then migrate to GCS under `tfstate/0-bootstrap`. Use a git-ignored local `terraform.tfvars`; keep a private copy in `gs://<prefix>-iac-tfstate/tfvars/0-bootstrap/terraform.tfvars`. Stage 0 is not applied by the pipeline it creates.
- After the GitHub org owner authorizes the App, enable the repository link, triggers and jobs. Stages 1–3 use **PR plan → code owner review (`iac-reviewers`) → merge to `main` → apply** (no approval step in GCP; R10). Plans run without state locking as read-only SAs; on merge, the apply build plans again from `main` and applies that saved plan with normal locking.
- Plan/apply output stays in Cloud Logging. GitHub checks can expose status, the seed project ID in the check name, and build/trigger UUIDs, not plan text. External PRs require a repo writer's `/gcbrun` after review.
- Scheduler starts `<key>-check` on `main` daily or on demand (including after a stage's first apply). Checks use the corresponding plan SA; any diff or error fails the build, and no check applies changes.

## Practical value

A small team bootstraps once rather than sharing admin credentials. It gets recoverable state, a second person authorizing infrastructure writes, and a way to spot drift or missing plan permissions without handing operators the apply identity.

## GCP vs third-party

| Option | Price with source | Maintenance effort | Why chosen / not |
|---|---|---|---|
| Cloud Build + GCS state | Default-pool `e2-standard-2`: USD 0.006/build-minute; promotional 2,500 free minutes/month per billing account [Cloud Build pricing](https://cloud.google.com/build/pricing) (read 2026-11-25). Iowa Standard storage: USD 0.02/GiB-month, plus operations and applicable transfer [Cloud Storage pricing](https://cloud.google.com/storage/pricing) (read 2026-11-25). Scheduler: three jobs/month free per billing account, then USD 0.10/job/31 days [Scheduler pricing](https://cloud.google.com/scheduler/pricing) (read 2026-11-25). | Maintain the builder image, GitHub connection and trigger configuration; no runner fleet. | **Chosen:** OpenTofu, private logs for the public repo, and a post-merge approval gate in GCP. |
| HCP Terraform | No charge for up to 500 managed resources/org [HCP Terraform](https://developer.hashicorp.com/terraform/cloud-docs/overview) (read 2026-11-25). Indicative PAYG per managed resource-hour: Essentials USD 0.00013, Standard USD 0.00064, Premium USD 0.00135 [IBM pricing](https://www.ibm.com/products/hashicorp/pricing) (read 2026-11-25). | Manage SaaS workspaces, access and GCP integration. | Not adopted: adds a separate IaC platform to a GCP-only foundation. |
| Spacelift | Free USD 0 (two users, one API key); Starter from USD 399/month [Spacelift pricing](https://spacelift.io/pricing) (read 2026-11-25). | Manage SaaS stacks, access and worker setup. | Not adopted: the free user cap is tight for separate reviewers and approvers. |
| Scalr | Free up to 50 runs/month; Business $0.99/run with volume discounts [Scalr pricing](https://scalr.com/pricing) (read 2026-11-25). PR plan and apply count separately. | Manage SaaS workspaces, access and run usage. | Not adopted: Cloud Build already meets the workflow without a separate run allowance. |
| Atlantis | Apache-2.0 open source [license](https://raw.githubusercontent.com/runatlantis/atlantis/main/LICENSE) (read 2026-11-25); self-hosted infrastructure price: not stated by the vendor (checked 2026-11-25) ([Atlantis](https://www.runatlantis.io/)). | Run, patch and monitor the webhook service and hosting. | Not adopted: the small team would have another service to operate. |
| GitHub Actions (b1, private repo) | Team USD 4/user/month; Enterprise USD 21/user/month [GitHub pricing](https://github.com/pricing) (read 2026-11-25). Private-repo Team compute allowance: USD 18/month; baseline Linux 2-core x64 USD 0.006/min beyond the allowance [GitHub billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions) (read 2026-11-25) and [runner rates](https://docs.github.com/en/billing/reference/actions-runner-pricing) (read 2026-11-25). | Maintain workflows, GCP authentication and log access. | Viable if PR review is the gate; not equivalent to this pipeline's separate approval after merge. |
| Infrastructure Manager | No management fee for supported Terraform versions up to 1.5.7 or for previews. Paid versions include 500 concurrent managed resources/month per billing account, then USD 1/resource-year metered in resource-seconds; build and storage charges still apply [Infrastructure Manager pricing](https://cloud.google.com/infrastructure-manager/pricing) (read 2026-11-25). | Managed execution and state; still configure Git triggers and any Cloud Build gate. | Not adopted: OpenTofu support and a native approval gate are **not stated by the vendor (checked 2026-11-25)** ([versions](https://docs.cloud.google.com/infrastructure-manager/docs/infra-manager-terraform#terraform_versions), [Git integration](https://docs.cloud.google.com/infrastructure-manager/docs/automate-git)). The sample applies on merge; a separate [Cloud Build gate](https://docs.cloud.google.com/build/docs/securing-builds/gate-builds-on-approval) would be needed. |

The builder uses [Artifact Registry](../3-cicd/README.md#gcp-vs-third-party). For the GitHub connection token, Secret Manager includes six active versions and 10,000 access operations/month per billing account; beyond the free tier the rates are USD 0.06/active version/location/month and USD 0.03/10,000 accesses. See [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing) (read 2026-11-25).

In b1, GitHub Team in a private repo can use **PR review** before merge as the gate. GitHub environment **required reviewers** are a different control: private repos need Enterprise for that post-merge gate. See the [GitHub environment docs](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments) (read 2026-11-25).

## Permissions matrix

Role IDs omit `roles/`.

| Who | Role | Scope | Why |
|---|---|---|---|
| Admins group (`admin_principals`, `trigger_admin_principals`) | `resourcemanager.organizationAdmin`, `resourcemanager.projectCreator`; `owner`; `billing.admin`; `iam.serviceAccountUser` | Organization; seed project; billing account; IaC SAs, respectively | Local stage 0; starts the first applies once; otherwise break-glass. Org roles are granted by hand once in runbook 00 and then declared here. |
| Billing group | `billing.viewer` | Billing account | Inspect costs; no budget or IAM writes. |
| Devops group | `cloudbuild.builds.viewer`, `logging.viewer`, `cloudscheduler.jobRunner` | Seed project | Read plans and run known check jobs; no direct trigger runs or SA impersonation. Environment access is in [stage 2](../2-environments/README.md). |
| `iac-org-plan` | `viewer`, `resourcemanager.folderViewer`, `iam.securityReviewer`, `orgpolicy.policyViewer`, `privilegedaccessmanager.viewer`; `billing.viewer`; `monitoring.viewer`, `serviceusage.serviceUsageConsumer` | Organization; billing account; seed project, respectively | Refresh stages 1–2, including folder metadata, budgets and alert channels. |
| `iac-org-apply` | `resourcemanager.organizationAdmin`, `resourcemanager.folderAdmin`, `resourcemanager.projectCreator`, `orgpolicy.policyAdmin`, `privilegedaccessmanager.admin`, `serviceusage.serviceUsageAdmin`; `billing.user`, `billing.costsManager`; `monitoring.notificationChannelEditor`, `serviceusage.serviceUsageConsumer` | Organization; billing account; seed project, respectively | Writes in stages 1–2 after merge; link billing and manage the budget and its channel, not billing-account IAM. |
| Both plan SAs / both apply SAs | `storage.objectViewer` / `storage.objectAdmin`, respectively | State bucket | Both read inputs and state; only apply SAs write state and locks. |
| All four IaC SAs | `logging.logWriter`; `artifactregistry.reader` | Seed project; builder repository | Write only build logs and pull the builder. Stage 2 gives the project-tier SAs environment access. |
| `iac-check-runner` | Custom `buildTriggerRunner` (build create/get/list); `iam.serviceAccountUser` | Seed project; the two plan SAs only | Starts checks on behalf of Scheduler; cannot start applies. |
| Cloud Build service agent | `secretmanager.admin` | Seed project | Store the GitHub connection token. |

## Related runbooks

[Bootstrap (methods A/B)](../../runbooks/02-stage0-bootstrap.md) · [Connect GitHub and configure the pipeline](../../runbooks/03-cloud-ops-repo.md) · [First applies](../../runbooks/04-stages-via-pipeline.md) · [Manage PAM approvers](../../runbooks/ops/change-approver.md) · [Run checks](../../runbooks/ops/run-checks.md)
