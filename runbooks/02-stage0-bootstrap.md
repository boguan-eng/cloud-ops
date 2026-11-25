# 02 — Stage 0 Bootstrap

Creates the seed project, state bucket, builder image repository and the 4 IaC service
accounts. Run **once**, by a human. Code: `stages/0-bootstrap/`. Design:
`stages/foundation-design.md`.

**Who:** method A — the GCP **Org Owner**; method B — a named **devops member** under a
temporary grant from the Org Owner (sections B1 and B2 wrap the common steps).
**Prerequisites:** runbook 01 done; Google groups `<prefix>-gcp-devops`, `<prefix>-gcp-approvers`,
`<prefix>-gcp-developers` and `<prefix>-gcp-billing` exist (groups.google.com, created by the Org Owner;
IAM rejects a group that does not exist, so check each address against the tfvars) with the settings in
[ops/change-approver.md](ops/change-approver.md) section 1.
**Next:** [03-cloud-ops-repo.md](03-cloud-ops-repo.md).

Never commit real values (`terraform.tfvars`, `backend.hcl` are git-ignored).

## 0. Variables (example values are FAKE)

```bash
export ORG_ID="123456789012"                  # gcloud organizations list
export BILLING_ACCOUNT="000000-000000-000000" # gcloud billing accounts list
export PREFIX="acme"
export REGION="us-central1"
export SEED_PROJECT="${PREFIX}-iac-seed"      # add a suffix only if the ID is taken
export STATE_BUCKET="${PREFIX}-iac-tfstate"   # globally unique
export OWNER_USER="owner@example.com"         # the Org Owner
export TOFU_VERSION="1.13.1"                  # = TOFU_VERSION in builder/Dockerfile
export BUILDER_IMAGE="${REGION}-docker.pkg.dev/${SEED_PROJECT}/iac-builder/tofu:${TOFU_VERSION}"
# method B only
export DEVOPS_MEMBER="devops1@example.com"
export END_UTC="2030-01-01T12:00:00Z"         # temp grant expiry (UTC), e.g. now + 8h
export COND="expression=request.time < timestamp('${END_UTC}'),title=stage0-temp"
```

## B1. (Method B only) Org Owner grants temporary roles

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

`trigger_admin_principals` in `terraform.tfvars` must list the **Org Owner**, not the devops
member. The devops member then runs sections 1–5 with their own credentials, before `$END_UTC`.

## 1. Prerequisites check

- Method A: the Org Owner is Organization Owner/Administrator and Billing Account Administrator.
- OpenTofu ≥ 1.6 (`tofu version`; in Cloud Shell install the standalone binary to `$HOME/bin`,
  https://opentofu.org/docs/intro/install/standalone/), Docker.

```bash
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter="bindings.members:user:$(gcloud config get-value account)" --format='value(bindings.role)'
# expect roles/billing.admin
```

## 2. Configure

```bash
cd cloud-ops/stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Fill: org_id, billing_account, prefix, state_bucket_name, devops_principal ("group:..."),
# approver_principals (["group:<prefix>-gcp-approvers@..."]), trigger_admin_principals (["user:<OWNER_USER>"]),
# enable_github = false.
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

## 5. Build and push the builder image

Tags are immutable: tag = OpenTofu version (bump `builder/Dockerfile` and the tag together).

```bash
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
docker build --build-arg TOFU_VERSION="$TOFU_VERSION" -t "$BUILDER_IMAGE" builder
docker push "$BUILDER_IMAGE"
```

If the gcloud credential helper uses an account without access, log in with a token instead:
`gcloud auth print-access-token | docker login -u oauth2accesstoken --password-stdin https://${REGION}-docker.pkg.dev`.

## B2. (Method B only) Org Owner removes the elevation

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
# iac-org-plan: viewer, iam.securityReviewer, orgpolicy.policyViewer, privilegedaccessmanager.viewer
# iac-org-apply: organizationAdmin, folderAdmin, projectCreator, orgpolicy.policyAdmin,
#                privilegedaccessmanager.admin, serviceusage.serviceUsageAdmin
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:iac-' --format='table(bindings.members,bindings.role)'
# iac-org-plan: billing.viewer; iac-org-apply: billing.user, billing.costsManager
gcloud artifacts docker images list "${REGION}-docker.pkg.dev/${SEED_PROJECT}/iac-builder" --include-tags
```

**Next:** [03-cloud-ops-repo.md](03-cloud-ops-repo.md).

## References

- Billing IAM has no conditions: https://cloud.google.com/iam/docs/resource-types-with-conditional-roles
- Expiring grants: https://cloud.google.com/iam/docs/configuring-temporary-access
- Project creator becomes Owner: https://cloud.google.com/iam/docs/roles-permissions/resourcemanager
- Billing link permission: https://cloud.google.com/billing/docs/how-to/modify-project
