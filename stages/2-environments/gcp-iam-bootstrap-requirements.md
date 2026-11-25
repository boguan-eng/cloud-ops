> **Superseded (2026-11-25):** historical record of the pre-restructure work. Current sources: [requirements](../foundation-requirements.md), [design](../foundation-design.md), [tasks](../foundation-tasks.md) and the [stage README](README.md).

# GCP IAM Bootstrap — Requirements

## Goal

Bootstrap a startup's GCP organization with environment folders, one project per
environment, and group-based IAM (admins / devops / developers). The setup must be
reusable for other organizations by changing only configuration values.

## Context / Constraints

- The GCP Organization already exists and has **no directory** (no Google Workspace /
  Cloud Identity). User accounts cannot be created inside the org.
- Members use their own personal Google accounts (e.g. Gmail).
- Groups are consumer Google Groups (`@googlegroups.com`), created manually by the admin.
  Only admins may own/manage the groups (group membership = permission).
- The repository is **public**: org ID, billing account ID, emails, and any other
  environment values must not be committed. Only example config with fake values is committed.
- Tool: Terraform-compatible IaC (HCL).

## Resource Layout

```
Organization (existing)
├─ Folder: prod
│   └─ Project: <PREFIX>-app-prod
└─ Folder: nonprod
    └─ Project: <PREFIX>-app-nonprod
```

- Both projects are linked to the same existing billing account.
- Logging and Monitoring APIs are enabled on both projects (required for developers to view them).
- Project IDs are globally unique; if taken, a suffix is used.
- Naming is derived from `<PREFIX>`. Groups: `<PREFIX>-gcp-admins`, `<PREFIX>-gcp-devops`,
  `<PREFIX>-gcp-developers` (actual emails are configuration values).
- Existing projects outside this setup are not touched.

## Roles

| Principal | Scope | Roles |
|---|---|---|
| admins group | Organization | Organization Administrator, Billing Administrator |
| admin personal account | Organization | Keep existing direct bindings (break-glass) |
| devops group | prod + nonprod | compute.admin, container.admin, run.admin, dns.admin, cloudsql.admin, storage.admin, artifactregistry.admin, secretmanager.admin, iam.serviceAccountAdmin, iam.serviceAccountUser, logging.admin, monitoring.admin, serviceusage.serviceUsageAdmin |
| devops group | nonprod only | + resourcemanager.projectIamAdmin |
| developers group | prod + nonprod | logging.viewer, monitoring.viewer, serviceusage.serviceUsageConsumer |

- devops cannot change IAM in prod, cannot manage billing, org policy, folders, or projects.
- developers are read-only for logs and monitoring; Data Access audit logs are not visible.
  serviceUsageConsumer is needed because gcloud sends the current project as quota project
  by default (otherwise `USER_PROJECT_DENIED`); it does not allow enabling APIs.

## Acceptance (requirement level)

1. Folders and projects exist as in the layout, projects are billing-linked.
2. Each group has exactly the roles in the table at the stated scope.
3. Existing org-level bindings are preserved.
4. A member of each group can do what the role allows and is denied what it does not
   (spot check: developer can read logs, cannot write; devops cannot set prod IAM).
5. No environment-specific values are committed.

## Verified Assumptions

- Consumer `@googlegroups.com` groups are accepted as IAM principals (verified in T0).
