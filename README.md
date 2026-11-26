# Cloud Ops

Cloud Ops is a hands-on implementation of Google Cloud Professional Cloud DevOps topics for a small team. Chapter 1, **Foundation**, covers resource hierarchy, IAM, and reviewed infrastructure changes with OpenTofu. This repository is public: environment-specific values stay out of Git, and the pipeline reads `tfvars` from the seed project's state bucket.

## Operating model

| When | How it works |
|---|---|
| Bootstrap and break-glass | An admin (member of `gcp-admins`, a Cloud Identity group of the two super admins) handles stage 0 locally and starts the first applies of stages 1–3 once from `main`. Outside bootstrap, the admins handle tfvars-only changes and break-glass. |
| Routine infrastructure changes | DevOps opens a PR → Cloud Build runs a plan → a member of the `iac-reviewers` code owner team (not the author) approves → merge to `main` → the apply runs. The PR review is the only approval; only an Org Owner may bypass it, in an emergency, recorded in the PR. DevOps has no standing write access to either environment. |
| Production incident | Direct production writes by DevOps require an approved, time-limited `prod-operator` Privileged Access Manager (PAM) grant. Reconcile the change by PR, then run the affected checks and verify no diff. |
| Drift and read coverage | Four daily Cloud Scheduler jobs start Cloud Build checks on `main` as the plan service accounts (SAs). A check fails on a diff or error. DevOps can also run the jobs on demand. |

## Index

| Chapter / scenario | Stage or runbook |
|---|---|
| Foundation: bootstrap from zero | [Runbook index](runbooks/README.md) · [01 GitHub org](runbooks/01-github-org.md) → [02 Stage 0 bootstrap](runbooks/02-stage0-bootstrap.md) → [03 Repo and pipeline](runbooks/03-cloud-ops-repo.md) → [04 First pipeline applies](runbooks/04-stages-via-pipeline.md) |
| Change infrastructure | [Change via PR](runbooks/ops/change-via-pr.md) |
| Prod incident access | [Request and approve a PAM grant](runbooks/ops/approve-pam-grant.md) |
| Drift checks | [Run stage checks](runbooks/ops/run-checks.md) |
| Change PAM approver | [Add or remove a PAM approver](runbooks/ops/change-approver.md) |
| Stage 0: seed project and pipeline | [Bootstrap](stages/0-bootstrap/README.md) |
| Stage 1: organization policy and billing budget | [Organization](stages/1-org/README.md) |
| Stage 2: prod and nonprod folders, projects, and access | [Environments](stages/2-environments/README.md) |
| Stage 3: GitHub federation and artifact storage | [CI/CD](stages/3-cicd/README.md) |
| Identity options | [Standalone org, Cloud Identity, and workforce federation](stages/1-org/identity-options.md) |
| Foundation specifications | [Requirements](stages/foundation-requirements.md) · [Design](stages/foundation-design.md) · [Tasks](stages/foundation-tasks.md) |

## Layout

```text
cloud-ops/
├── runbooks/               # numbered bootstrap guides
│   └── ops/                # day-to-day operations
├── stages/
│   ├── 0-bootstrap/        # seed project, state bucket, and pipeline
│   │   └── builder/        # OpenTofu builder image
│   ├── 1-org/              # organization policies and billing budget
│   ├── 2-environments/     # environment projects, IAM, and PAM
│   ├── 3-cicd/
│   │   ├── ar/             # Artifact Registry
│   │   └── wif/            # Workload Identity Federation
│   └── cloudbuild/         # shared plan, apply, and check definitions
└── apps/                   # Git-ignored; each app is in a separate repo
```

## Role matrix

Predefined role IDs below omit the `roles/` prefix. All four IaC SAs have `logging.logWriter` on the seed project for build logs and `artifactregistry.reader` on the builder repository. Plan SAs cannot change managed resources.

| Persona | Where | Roles | How they act |
|---|---|---|---|
| Admins group (`gcp-admins`: the two super admins) | Organization; seed project; billing account; IaC SAs | Org: `resourcemanager.organizationAdmin`, `resourcemanager.projectCreator`; seed: `owner`; billing: `billing.admin`; IaC SAs: `iam.serviceAccountUser` | Handle stage 0, the first pipeline applies and tfvars-only changes; otherwise break-glass. Manage Cloud Identity users and groups. No IAM is bound to an individual. |
| Approvers group | Prod folder | `resourcemanager.folderViewer` and designated PAM approver | Approve incident grants in PAM only. Separate from DevOps and developers. |
| IaC reviewers (GitHub team `iac-reviewers`) | `cloud-ops` repo | Write; code owner of `/stages/` and `/.github/` | Review the PR and plan; the approval releases the apply. |
| Billing group | Billing account | `billing.viewer`; designated budget alert recipient | View costs and the budget without administering billing. |
| DevOps group | Seed project; prod and nonprod folders | Seed: `cloudbuild.builds.viewer`, `logging.viewer`, `cloudscheduler.jobRunner`; both folders: `viewer`, `iam.workloadIdentityPoolViewer`; prod only: eligible for `prod-operator` | Change infrastructure via reviewed PRs, read plans, and run Scheduler jobs on demand. Request temporary prod writes for incidents only. |
| Developers group | Prod and nonprod folders | `logging.viewer`, `monitoring.viewer`, `serviceusage.serviceUsageConsumer`, `run.viewer`, `cloudtrace.user`, `errorreporting.viewer` | Read logs, metrics, and service status; no service writes. `cloudtrace.user` can edit trace scopes. |
| `iac-org-plan` | Org; billing account; seed project and state bucket | Org: `viewer`, `resourcemanager.folderViewer`, `iam.securityReviewer`, `orgpolicy.policyViewer`, `privilegedaccessmanager.viewer`; billing: `billing.viewer`; seed: `monitoring.viewer`, `serviceusage.serviceUsageConsumer`; bucket: `storage.objectViewer` | Run PR plans and checks for stages 1–2. |
| `iac-org-apply` | Org; billing account; seed project and state bucket | Org: `resourcemanager.organizationAdmin`, `resourcemanager.folderAdmin`, `resourcemanager.projectCreator`, `orgpolicy.policyAdmin`, `privilegedaccessmanager.admin`, `serviceusage.serviceUsageAdmin`; billing: `billing.user`, `billing.costsManager`; seed: `monitoring.notificationChannelEditor`, `serviceusage.serviceUsageConsumer`; bucket: `storage.objectAdmin` | Apply stages 1–2 only through approved Cloud Build builds. |
| `iac-project-plan` | Both env folders; state bucket | Folders: `viewer`, `iam.securityReviewer`; bucket: `storage.objectViewer` | Run PR plans and checks for the stage 3 WIF and Artifact Registry modules. |
| `iac-project-apply` | Both env folders (inherited by projects); state bucket | Folders: `iam.workloadIdentityPoolAdmin`, `artifactregistry.admin`, `serviceusage.serviceUsageAdmin`; bucket: `storage.objectAdmin` | Apply the stage 3 modules only through approved Cloud Build builds. |
| `iac-check-runner` | Seed project; the two plan SAs | Custom `buildTriggerRunner` (create/get/list builds); `iam.serviceAccountUser` on plan SAs only | Cloud Scheduler uses it to start checks; it cannot start applies. |

## Pipeline comparison

**Cloud Build + OpenTofu (chosen).** Build logs and apply approvals stay in GCP. On default-pool `e2-standard-2`, [Cloud Build pricing](https://cloud.google.com/build/pricing) (read 2026-11-25) lists 2,500 promotional free build-minutes/month per billing account, then USD 0.006/minute. See [stage 0](stages/0-bootstrap/README.md) for setup and trade-offs.

**b1: GitHub Actions in a private repo (not implemented; decided 2026-11-25).** On GitHub Team, use PR review as the gate, not a second approval after merge. Private-repo environment required reviewers [need Enterprise](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments#required-reviewers) (read 2026-11-25). [GitHub plan pricing](https://github.com/pricing) (read 2026-11-25) lists Enterprise at USD 21/user/month and 2,000 / 3,000 / 50,000 CI/CD minutes/month for Free / Team / Enterprise, respectively. These are baseline equivalents: private-repo [Actions allowances](https://docs.github.com/en/billing/concepts/product-billing/github-actions) (read 2026-11-25) are USD 12 / 18 / 300 per month for Free organizations / Team / Enterprise Cloud, with usage depending on the runner.

| Alternative | Trade-off and pricing |
|---|---|
| Infrastructure Manager (not adopted) | OpenTofu support was not found in the [supported versions](https://docs.cloud.google.com/infrastructure-manager/docs/infra-manager-terraform#terraform_versions) (read 2026-11-25). The [Git sample](https://docs.cloud.google.com/infrastructure-manager/docs/automate-git) (read 2026-11-25) deploys on merge; no native approval gate was found. [Pricing](https://cloud.google.com/infrastructure-manager/pricing) (read 2026-11-25): no management fee for supported Terraform through 1.5.7 or for previews; paid versions include 500 concurrent managed resources/month per billing account, then USD 1/resource-year. Build and storage charges still apply. |
| HCP Terraform | [Free for up to 500 managed resources per org](https://developer.hashicorp.com/terraform/cloud-docs/overview) (read 2026-11-25); [indicative IBM pay-as-you-go rates](https://www.ibm.com/products/hashicorp/pricing) (read 2026-11-25) are USD 0.00013 / 0.00064 / 0.00135 per managed resource-hour for Essentials / Standard / Premium. |
| Spacelift | [Free for two users; Starter from USD 399/month](https://spacelift.io/pricing) (read 2026-11-25). |
| Scalr | [Free for up to 50 runs/month; Business $0.99/run before volume discounts](https://scalr.com/pricing) (read 2026-11-25). A PR plan and post-merge apply count separately. |
| Atlantis | [Open source and self-hosted](https://www.runatlantis.io/) (read 2026-11-25); no published hosting price. The team supplies and operates the infrastructure. |

## Known limitations and open items

| Item | Status |
|---|---|
| T7-12: PAM, budget, and check-failure email | Notification work is deferred until a domain and Cloud Identity are in place; see [identity options](stages/1-org/identity-options.md). For now, contact PAM approvers directly and check budgets and builds in GCP. |
| Organization policies | `compute.vmExternalIpAccess` is deferred to a later chapter; `gcp.resourceLocations` needs a region plan. |
| Cloud Run | The Cloud Run API is not yet enabled in the environment projects. Enable it when deploying Cloud Run. |

## Public-repo rule

Run the [public-repo checks in AGENTS.md](AGENTS.md) before every commit and push. Keep real environment values out of commits; track only placeholder `tfvars` examples, never real `terraform.tfvars`.
