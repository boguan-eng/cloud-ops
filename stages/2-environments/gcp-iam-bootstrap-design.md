# GCP IAM Bootstrap — Design

Requirements: `stages/2-environments/gcp-iam-bootstrap-requirements.md`

## Tooling

- OpenTofu (`tofu`), HCL compatible with Terraform. Provider: `hashicorp/google`.
- Auth: Application Default Credentials of the org admin account
  (`gcloud auth application-default login`).
- State: local file, git-ignored. (May be migrated to a GCS backend later.)

## Layout

```
stages/2-environments/
├─ versions.tf               # tofu + provider versions
├─ variables.tf              # inputs (no defaults for env-specific values)
├─ main.tf                   # folders, projects, billing link
├─ iam.tf                    # IAM bindings
├─ outputs.tf                # folder IDs, project IDs
├─ terraform.tfvars.example  # fake values only (committed)
└─ RUNBOOK.md                # every command, parameterized, for re-use
.gitignore                   # *.tfvars (except *.example), *.tfstate*, .terraform/, crash.log
```

## Inputs

| Variable | Type | Note |
|---|---|---|
| `org_id` | string | env-specific |
| `billing_account` | string | env-specific |
| `prefix` | string | names derive from it |
| `project_id_suffix` | string, default `""` | used only when the project ID is taken |
| `group_admins` / `group_devops` / `group_developers` | string | group emails |
| `admin_org_roles` | list, default per table below | |
| `devops_roles` | list, default per table below | |
| `devops_nonprod_extra_roles` | list, default `[projectIamAdmin]` | |
| `developer_roles` | list, default `[logging.viewer, monitoring.viewer, serviceusage.serviceUsageConsumer]` | |
| `project_services` | list, default `[logging.googleapis.com, monitoring.googleapis.com]` | |

## Resources

- `google_folder` x2: `prod`, `nonprod` under the org.
- `google_project` x2: `<prefix>-app-<env><suffix>` in its folder, linked to billing,
  `auto_create_network = false`, `deletion_policy = "PREVENT"`.
- `google_project_service` for each env x `project_services`, `disable_on_destroy = false`.
- IAM, additive only (`google_organization_iam_member`, `google_folder_iam_member`).
  Never `*_iam_policy` / `*_iam_binding` (would overwrite existing bindings).

| Principal | Scope | Roles |
|---|---|---|
| admins group | org | organizationAdmin, billing.admin, folderAdmin, projectCreator |
| devops group | folder prod + nonprod | devops_roles |
| devops group | folder nonprod | devops_nonprod_extra_roles |
| developers group | folder prod + nonprod | developer_roles |

folderAdmin and projectCreator are added to admins because organizationAdmin alone
cannot create folders/projects.

## Prerequisites (manual, once per org)

1. ADC login as the org admin account.
2. Grant `roles/resourcemanager.folderCreator` at org to the account running tofu.
3. Groups created at groups.google.com, owned by an admin.
   Group emails must match `terraform.tfvars` (non-existent groups are rejected by IAM).

`@googlegroups.com` groups as IAM principals: verified once (T0), so no per-org check step.

## Verification

| # | Check | Why |
|---|---|---|
| V1 | `tofu validate` passes; `plan` has only creates, no update/destroy | protect existing resources |
| V2 | gcloud IAM policies of org/folders match the role table | requirement acceptance 1–3 |
| V3 | Test account in group: developer reads logs OK, write denied; devops cannot set prod IAM | config ≠ effective permission |
| V4 | `git status` + grep: no env-specific values tracked | public repo |

## Re-use

All commands are recorded in `stages/2-environments/RUNBOOK.md` with shell variables
(`ORG_ID`, `BILLING_ACCOUNT`, `ADMIN_ACCOUNT`, `PREFIX`, group emails). To apply to another
org: create groups, fill `terraform.tfvars`, follow the runbook from the top.
