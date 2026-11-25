# Stage 3 — Application CI/CD

## What it manages

| Stack | Resources |
|---|---|
| `wif/` | IAM, IAM Credentials and Security Token Service APIs in both environment projects; one Workload Identity Federation (WIF) pool and GitHub OIDC provider per environment. |
| `ar/` | Artifact Registry API in both projects; one Docker repository per configured GitHub app repo in each environment, with immutable tags in prod. Additive repository IAM grants the matching federated identity write access and the prod identity read access to the matching nonprod repository. |

## Concept and how it works

- Stage 2 supplies the projects and folder IAM. Apply `wif/` first; its pool resource names are inputs to `ar/`. Provider and registry outputs are handed to the app repo privately, not committed.
- For each stack, Cloud Build plans the devops PR as `iac-project-plan`. After review and merge to `main`, the approvers group authorizes a fresh plan and apply as `iac-project-apply`. Logs stay in GCP. From zero, the Org Owner starts the first apply trigger for each stack once, still behind approval. Run the corresponding `<key>-check` after the first apply and to check for drift or missing read access.
- The GitHub Actions **app** pipeline uses short-lived federated credentials directly against Artifact Registry, not the infrastructure apply SA. Nonprod accepts the `nonprod` GitHub environment on `main`; prod accepts the `prod` environment on `v*` tags. The provider checks the numeric GitHub org ID, and repo IAM checks the numeric repository ID. Each environment has its own pool, so nonprod identity configuration cannot grant prod trust. A prod workflow can promote the matching nonprod image instead of rebuilding it.

| Stack | GCS state key | `terraform.tfvars` directory |
|---|---|---|
| `wif/` | `tfstate/3-cicd-wif` | `gs://<prefix>-iac-tfstate/tfvars/3-cicd-wif/` |
| `ar/` | `tfstate/3-cicd-ar` | `gs://<prefix>-iac-tfstate/tfvars/3-cicd-ar/` |

## Practical value

A small team can ship images from GitHub without storing or rotating GCP keys. Separate pools and repository grants keep one app or environment from publishing into another; immutable prod tags keep a release tag from being overwritten.

## GCP vs third-party

| Option | Price with source | Maintenance effort | Why chosen / not |
|---|---|---|---|
| GCP WIF + GitHub OIDC | WIF is included at no additional per-user or per-identity cost — [IAM pricing](https://cloud.google.com/products/iam) (read 2026-11-25) and [WIF overview](https://docs.cloud.google.com/iam/docs/workload-identity-federation) (read 2026-11-25). | Keep trust conditions and repo IDs current; no keys to rotate. | Chosen: short-lived access scoped to a GitHub environment, ref and app repo. |
| Service-account keys | Separate key price: not stated by the vendor (checked 2026-11-25) ([IAM pricing](https://cloud.google.com/iam/pricing)). | Store, rotate and revoke long-lived credentials. | Not adopted: org policies block key creation and upload. |
| GCP Artifact Registry | First 0.5 GiB-month free per billing account; USD 0.10/GiB-month above that. Inbound and same-location transfer are free; outbound Internet transfer uses Premium Tier rates — [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing) (read 2026-11-25). | Manage repositories, image retention and IAM; no registry servers. | Chosen: native repo IAM for WIF, separate environment repos and immutable prod tags. |

Other registries: not compared.

## Permissions matrix

Role IDs omit `roles/`.

| Who | Role | Scope | Why |
|---|---|---|---|
| Org Owner | `cloudowner.admin` (outside IAM), `iam.serviceAccountUser` on IaC SAs | Organization; IaC SAs | Starts the first applies during bootstrap; otherwise break-glass. |
| Approvers group | `cloudbuild.builds.approver`, `cloudbuild.builds.viewer`, `logging.viewer` | Seed project | Approve infrastructure changes, not app pushes. |
| Devops group | `viewer`, `iam.workloadIdentityPoolViewer`; `cloudbuild.builds.viewer`, `logging.viewer`, `cloudscheduler.jobRunner` | Both environment folders; seed project, respectively | Inspect WIF and plans, change IaC by PR, and start check jobs. No standing repo write; prod PAM is incident-only (see [stage 2](../2-environments/README.md)). |
| `iac-project-plan` | `viewer`, `iam.securityReviewer` | Both environment folders (inherited into projects) | Refresh APIs, pools/providers, registry repos and repo IAM. |
| `iac-project-apply` | `iam.workloadIdentityPoolAdmin`, `artifactregistry.admin`, `serviceusage.serviceUsageAdmin` | Both environment folders (inherited into projects) | Manage WIF, repositories and repo IAM, and enable APIs after approval. |
| `iac-check-runner` | `buildTriggerRunner`; `iam.serviceAccountUser` | Seed project; plan SAs only | Starts check builds but cannot act as either apply SA. |
| Federated GitHub repo identity | `artifactregistry.writer` | Matching repository in its own environment | Push images for that app only. |
| Matching prod federated identity | `artifactregistry.reader` | Same app's nonprod repository | Read the source image for promotion to prod. |

The [stage 0 matrix](../0-bootstrap/README.md#permissions-matrix) covers shared pipeline access; [stage 2](../2-environments/README.md#permissions-matrix) covers developer visibility and the folder grants. Billing viewers have no CI/CD role.

## Related runbooks

[First applies and app handoff](../../runbooks/04-stages-via-pipeline.md) · [Change by PR](../../runbooks/ops/change-via-pr.md) · [Approve an apply](../../runbooks/ops/approve-apply.md) · [Run checks](../../runbooks/ops/run-checks.md)
