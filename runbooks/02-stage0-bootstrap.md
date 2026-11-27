# 02 — Stage 0 Bootstrap

Creates the seed project, state bucket, builder image repository and the 4 IaC service
accounts. Run **once**, by a human. Code: `stages/0-bootstrap/`. Design:
`stages/foundation-design.md`.

**Who:** method A — an **admin** (`admin1`; the `gcp-admins` group holds the org bootstrap
roles and billing admin from runbook 00 section 5); method B — a named **devops member** under a
temporary grant from an admin (sections B1 and B2 wrap the common steps).
**Prerequisites:** runbooks 00 and 01 done; Cloud Identity groups `gcp-admins`, `gcp-devops`,
`gcp-approvers`, `gcp-developers` and `gcp-billing` exist (runbook 00 section 3; IAM rejects a
group that does not exist, so check each address against the tfvars).
**Next:** [03-cloud-ops-repo.md](03-cloud-ops-repo.md).

Never commit real values (`terraform.tfvars`, `backend.hcl` are git-ignored).

## 0. Variables (example values are FAKE)

```bash
export ORG_ID="123456789012"                  # gcloud organizations list
export BILLING_ACCOUNT="000000-000000-000000" # gcloud billing accounts list
export PREFIX="acme"                          # project IDs are globally unique; a deleted ID is never reusable;
                                              # PUBLIC: GitHub check names show the seed project ID
export REGION="us-central1"
export SEED_PROJECT="${PREFIX}-iac-seed"      # add a suffix only if the ID is taken
export STATE_BUCKET="${PREFIX}-iac-tfstate"   # globally unique
export TOFU_VERSION="1.13.1"                  # = TOFU_VERSION in builder/Dockerfile
export BUILDER_IMAGE="${REGION}-docker.pkg.dev/${SEED_PROJECT}/iac-builder/tofu:${TOFU_VERSION}"
# method B only
export DEVOPS_MEMBER="devops1@example.com"
export END_UTC="2030-01-01T12:00:00Z"         # temp grant expiry (UTC), e.g. now + 8h
export COND="expression=request.time < timestamp('${END_UTC}'),title=stage0-temp"
```

## B1. (Method B only) Admin grants temporary roles

| Where | Role | Why |
|---|---|---|
| Org (expires) | `roles/resourcemanager.projectCreator` | Creates the seed project; the creator automatically becomes **Owner of the seed project**, which covers APIs, bucket, AR, SAs, project/SA IAM |
| Org (expires) | `roles/resourcemanager.organizationAdmin` | Org IAM bindings for the IaC SAs |
| Billing account (**cannot expire**) | `roles/billing.admin` | Linking billing + billing IAM bindings (`billing.accounts.setIamPolicy`). Cloud Billing does not support IAM Conditions, so it is removed manually in B2 |

```bash
for ROLE in roles/resourcemanager.projectCreator roles/resourcemanager.organizationAdmin; do
  gcloud organizations add-iam-policy-binding "$ORG_ID" \
    --member="user:${DEVOPS_MEMBER}" --role="$ROLE" --condition="$COND"
done
gcloud billing accounts add-iam-policy-binding "$BILLING_ACCOUNT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/billing.admin
```

`trigger_admin_principals` in `terraform.tfvars` must list `group:gcp-admins@<domain>`, not the
devops member. The devops member then runs sections 1–5 with their own credentials, before `$END_UTC`.

## 1. Prerequisites check

- Billing account active. If it is a **Free Trial**, check the remaining credit and days
  (Console → **Billing** → **Overview**); if they may run out during the bootstrap, upgrade first
  (when the trial ends, its resources stop).
- Method A: the admin is in `gcp-admins`, which holds `organizationAdmin`, `projectCreator`
  and Billing Account Administrator (runbook 00 section 5).
- OpenTofu ≥ 1.6 (`tofu version`; in Cloud Shell install the standalone binary to `$HOME/bin`,
  https://opentofu.org/docs/intro/install/standalone/), Docker.

```bash
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --filter="bindings.members:group:gcp-admins@" --format='value(bindings.role)'
# expect roles/resourcemanager.organizationAdmin and roles/resourcemanager.projectCreator
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter="bindings.members:group:gcp-admins@" --format='value(bindings.role)'
# expect roles/billing.admin
```

## 2. Configure

```bash
cd cloud-ops/stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Fill: org_id, billing_account, prefix, state_bucket_name, devops_principal ("group:gcp-devops@<domain>"),
# admin_principals and trigger_admin_principals (["group:gcp-admins@<domain>"]),
# billing_viewer_principals (["group:gcp-billing@<domain>"]), enable_github = false.
# Leave seed_creator_principal unset until section 4a.
gcloud auth application-default login
```

## 3. First apply (local state)

The state bucket does not exist yet, so run without the GCS backend.

```bash
mv backend.tf backend.tf.off
tofu init
tofu apply            # review: only creates; type yes
```

## 4. Move the state into the new bucket

```bash
mv backend.tf.off backend.tf
echo "bucket = \"${STATE_BUCKET}\"" > backend.hcl
tofu init -migrate-state -backend-config=backend.hcl     # answer yes
tofu plan             # expect: No changes
rm -f terraform.tfstate terraform.tfstate.backup
gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/0-bootstrap/terraform.tfvars"
```

## 4a. (Method A) Remove the creator's owner binding

Creating the seed project made your user its `roles/owner`; the `gcp-admins` group is owner now
(R4: no IAM on an individual). Set `seed_creator_principal = "user:<your account>"` in
`terraform.tfvars`, then:

```bash
tofu apply            # expect: 1 to add (google_project_iam_member_remove), 0 to change, 0 to destroy
gcloud projects get-iam-policy "$SEED_PROJECT" --flatten='bindings[].members' \
  --filter='bindings.members:user:' --format='value(bindings.role,bindings.members)'
# expect: nothing
gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/0-bootstrap/terraform.tfvars"
```

If an apply fails with permission denied right after this, IAM is still propagating the group
grant: wait a minute and run it again.

## 5. Build and push the builder image

Tags are immutable: tag = OpenTofu version (bump `builder/Dockerfile` and the tag together).

```bash
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
docker build --build-arg TOFU_VERSION="$TOFU_VERSION" -t "$BUILDER_IMAGE" builder
docker push "$BUILDER_IMAGE"
```

If the push fails with "You do not currently have an active account selected" (the gcloud
credential helper in `~/.docker/config.json` uses the default gcloud configuration and overrides
`docker login`), push with a temporary Docker config and a token instead:

```bash
export DOCKER_CONFIG=$(mktemp -d)
gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin "https://${REGION}-docker.pkg.dev"
docker push "$BUILDER_IMAGE"
rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG
```

## B2. (Method B only) Admin removes the elevation

Do not wait for expiry; the billing role never expires.

```bash
for ROLE in roles/resourcemanager.projectCreator roles/resourcemanager.organizationAdmin; do
  gcloud organizations remove-iam-policy-binding "$ORG_ID" \
    --member="user:${DEVOPS_MEMBER}" --role="$ROLE" --condition="$COND"
done
gcloud billing accounts remove-iam-policy-binding "$BILLING_ACCOUNT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/billing.admin
gcloud projects remove-iam-policy-binding "$SEED_PROJECT" \
  --member="user:${DEVOPS_MEMBER}" --role=roles/owner        # auto-granted to the creator
# each must print nothing:
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='value(bindings.role)'
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='value(bindings.role)'
gcloud projects get-iam-policy "$SEED_PROJECT" --flatten='bindings[].members' \
  --filter="bindings.members:user:${DEVOPS_MEMBER}" --format='value(bindings.role)'
```

## Verification

```bash
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:iac-' --format='table(bindings.members,bindings.role)'
# iac-org-plan: viewer, resourcemanager.folderViewer, iam.securityReviewer, orgpolicy.policyViewer,
#               privilegedaccessmanager.viewer
# iac-org-apply: organizationAdmin, folderAdmin, projectCreator, orgpolicy.policyAdmin,
#                privilegedaccessmanager.admin, serviceusage.serviceUsageAdmin
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:iac-' --format='table(bindings.members,bindings.role)'
# iac-org-plan: billing.viewer; iac-org-apply: billing.user, billing.costsManager
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --format='value(bindings.members)' | grep -E '^(user|domain):'
# expect: nothing (org roles of people are held through gcp-admins)
gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${SEED_PROJECT}/iac-builder" --include-tags
```

**Next:** [03-cloud-ops-repo.md](03-cloud-ops-repo.md).

## References

- Billing IAM has no conditions: https://cloud.google.com/iam/docs/resource-types-with-conditional-roles
- Expiring grants: https://cloud.google.com/iam/docs/configuring-temporary-access
- Project creator becomes Owner: https://cloud.google.com/iam/docs/roles-permissions/resourcemanager
- Billing link permission: https://cloud.google.com/billing/docs/how-to/modify-project
