# Stage 0 Bootstrap — Method B (devops member with temporary elevation)

Same outcome as `runbooks/stage0-bootstrap-method-a.md`, but a named devops member runs the
apply under **time-bound** org roles granted by the Org Owner. Steps 1–9 of Method A apply
unchanged except where noted below. The Org Owner does the grants, the GitHub/Console steps
and the second apply (triggers).

## 0. Variables (fill in; example values are FAKE)

Same variables as Method A section 0, plus:

```bash
export DEVOPS_MEMBER="devops1@example.com"    # the named devops member who runs stage 0
export END_UTC="2030-01-01T12:00:00Z"         # temp grant expiry (UTC), e.g. now + 8h
export COND="expression=request.time < timestamp('${END_UTC}'),title=stage0-temp"
```

## 1. Org Owner: grant the temporary roles

Minimal set needed to apply stage 0 (no more):

| Where | Role | Why |
|---|---|---|
| Org (conditional) | `roles/resourcemanager.projectCreator` | `google_project.seed` (`resourcemanager.projects.create`). The creator is automatically made **Owner of the seed project**, which covers everything inside it (APIs, bucket, AR, 4 SAs, project IAM, SA IAM, `actAs` for triggers). |
| Org (conditional) | `roles/resourcemanager.organizationAdmin` | `google_organization_iam_member` for the SAs (`resourcemanager.organizations.setIamPolicy`/`getIamPolicy`). |
| Billing account (**no condition possible**) | `roles/billing.admin` | Linking the seed project needs `billing.resourceAssociations.create` (`billing.user` would be enough), but `google_billing_account_iam_member` needs `billing.accounts.setIamPolicy`, which only `billing.admin` has. |

No other org-level role is needed (`iam.serviceAccountAdmin` etc. come from seed project Owner).
Verified with `gcloud iam roles describe` (included permissions).

```bash
for ROLE in roles/resourcemanager.projectCreator roles/resourcemanager.organizationAdmin; do
  gcloud organizations add-iam-policy-binding "$ORG_ID" \
    --member="user:${DEVOPS_MEMBER}" --role="$ROLE" --condition="$COND"
done
# Cloud Billing does not accept IAM Conditions (see "Doc notes"): unconditional, remove manually in step 4.
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/billing.admin
```

In `terraform.tfvars` of stage 0 `trigger_admin_principals` must contain the **Org Owner**
user(s), not the devops member (so devops gets no lasting `actAs` on the IaC SAs).

## 2. Devops member: run Method A steps 2–6

Run with the devops member's own credentials (`gcloud auth application-default login`):
Method A section 2 (clone/configure), 3 (first apply, `enable_github = false`), 4 (migrate
state), 5 (build and push builder image), 6 (tfvars safekeeping).
Everything must finish before `$END_UTC`; the member can do this because of the seed-project
Owner role created in step 1. The member hands the Owner the real `terraform.tfvars` through
a private channel (never git).

## 3. Org Owner: GitHub part and second apply

The member needs no extra rights: the Org Owner does Method A section 7 (GitHub, Cloud Build
connection, GitHub App) and section 8 (`enable_github = true` apply, fetching
`terraform.tfvars` from `gs://$STATE_BUCKET/tfvars/0-bootstrap/`) as `trigger_admin_principals`
holder. (Alternative: temporarily add the member to `trigger_admin_principals` and let them
apply; they already hold seed-project Owner and `actAs` while the window is open. Remove them
from the list again in the same session.)

## 4. Org Owner: remove the elevation and verify (do not wait for expiry)

```bash
for ROLE in roles/resourcemanager.projectCreator roles/resourcemanager.organizationAdmin; do
  gcloud organizations remove-iam-policy-binding "$ORG_ID" \
    --member="user:${DEVOPS_MEMBER}" --role="$ROLE" --condition="$COND"
done
gcloud billing accounts remove-iam-policy-binding "$BILLING_ACCOUNT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/billing.admin
# Auto-granted Owner of the seed project (project creator): remove it too.
gcloud projects remove-iam-policy-binding "$SEED_PROJECT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/owner

# Verify: all three must print nothing
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='table(bindings.role,bindings.condition.title)'
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='table(bindings.role)'
gcloud projects get-iam-policy "$SEED_PROJECT" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='table(bindings.role)'
```

The member keeps only what the pipeline-managed stages and `devops_principal` give
(Cloud Build viewer + Logging viewer on the seed project, via the group). Also confirm the member
is not in `trigger_admin_principals` and has no `iam.serviceAccountUser` on the 4 SAs
(Method A section 9, last loop). Then run Method A section 9 in full.
Future changes to stage 0 require this runbook (or Method A) again.

## Doc notes

- Cloud Billing and IAM Conditions: the page "Services that permit conditions in allow
  policies" lists the services whose resources accept conditional bindings (Resource Manager,
  Cloud Storage, Secret Manager, ... ); **Cloud Billing is not listed**, so a billing account
  binding cannot carry the `request.time` condition. It is removed manually (step 4).
  https://cloud.google.com/iam/docs/resource-types-with-conditional-roles
  ("You can add conditions to allow policies for resources from the following services: ...")
- Org/folder/project bindings accept conditions (Resource Manager is listed); expiring grants:
  https://cloud.google.com/iam/docs/configuring-temporary-access
  (condition `request.time < timestamp(...)`; not allowed on legacy basic roles, so `roles/owner` is not used).
- Project creator is auto-granted Owner:
  https://cloud.google.com/iam/docs/roles-permissions/resourcemanager ("Once a user creates a project, they're automatically granted the owner role for that project.")
- Permissions to link a project to a billing account (`billing.resourceAssociations.create`
  on the billing account; Billing Account User or Administrator):
  https://cloud.google.com/billing/docs/how-to/modify-project
- Role permission lists checked with `gcloud iam roles describe <role>`:
  `billing.admin` (has `billing.accounts.setIamPolicy`), `billing.user` (does not),
  `organizationAdmin` (`resourcemanager.organizations.setIamPolicy`), `projectCreator`
  (`resourcemanager.projects.create`).
