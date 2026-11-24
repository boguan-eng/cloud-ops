# Stage 0 Bootstrap — Method A (Org Owner in Cloud Shell)

Creates the seed project, state bucket, builder AR repo, 4 IaC service accounts and (second
apply) the Cloud Build repository link + triggers. Run **once**, by a human.
Design: `stages/foundation-design.md` ("Seed Project", "Pipeline Flow"). Code: `stages/0-bootstrap/`.
Never commit real values (`terraform.tfvars`, `backend.hcl` are git-ignored).

## 0. Variables (fill in; example values are FAKE)

```bash
export ORG_ID="123456789012"                  # gcloud organizations list
export BILLING_ACCOUNT="000000-000000-000000" # gcloud billing accounts list
export PREFIX="acme"
export REGION="us-central1"
export SEED_SUFFIX=""                         # only if <prefix>-iac-seed is taken globally
export SEED_PROJECT="${PREFIX}-iac-seed${SEED_SUFFIX}"
export STATE_BUCKET="${PREFIX}-iac-tfstate"   # globally unique
export OWNER_USER="owner@example.com"         # the Org Owner running this runbook
export G_DEVOPS="${PREFIX}-gcp-devops@googlegroups.com"
export GITHUB_OWNER="acme"                    # GitHub org/user that owns the repo
export GITHUB_REPO="cloud-ops"
export CONNECTION="github-cloud-ops"         # Cloud Build connection name (step 6)
export TOFU_VERSION="1.13.1"                  # must match builder/Dockerfile TOFU_VERSION
export BUILDER_REPO="${REGION}-docker.pkg.dev/${SEED_PROJECT}/iac-builder"
export BUILDER_IMAGE="${BUILDER_REPO}/tofu-builder:${TOFU_VERSION}"
```

## 1. Prerequisites

- Signed in as the Org Owner in Cloud Shell (`gcloud auth list`).
- The Org Owner can administer the org (Organization Owner / `roles/cloudowner.admin`, or
  `organizationAdmin` + `projectCreator`) **and** is Billing Account Administrator
  (`roles/billing.admin`) on `$BILLING_ACCOUNT`.
- The devops group and the approver account(s) exist.
- OpenTofu >= 1.6 in Cloud Shell (not preinstalled; use the standalone installer from
  https://opentofu.org/docs/intro/install/standalone/ into `$HOME/bin`).
- A GitHub org/user that will own the public `cloud-ops` repo, and (for the GitHub App) a GitHub
  account with owner rights on it.

```bash
gcloud organizations describe "$ORG_ID" --format='value(displayName)'
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" \
  --flatten='bindings[].members' --filter="bindings.members:user:${OWNER_USER}" \
  --format='value(bindings.role)'        # expect roles/billing.admin
tofu version
```

## 2. Clone and configure

```bash
git clone "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}.git" && cd "$GITHUB_REPO"   # or the existing local clone
cd stages/0-bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: org_id, billing_account, prefix, seed_project_id_suffix,
# state_bucket_name, devops_principal ("group:$G_DEVOPS"),
# approver_principals, trigger_admin_principals (["user:$OWNER_USER"]); enable_github = false.
gcloud auth application-default login
```

## 3. First apply (local state, no GitHub)

The state bucket does not exist yet, so run without the GCS backend.

```bash
mv backend.tf backend.tf.off
tofu init
tofu apply            # review the plan: only creates; type yes
```

## 4. Migrate state to the new bucket

```bash
mv backend.tf.off backend.tf
echo "bucket = \"${STATE_BUCKET}\"" > backend.hcl
tofu init -migrate-state -backend-config=backend.hcl     # answer yes
tofu plan             # expect: No changes
rm -f terraform.tfstate terraform.tfstate.backup          # local copies; state is now in GCS
```

Note: the Org Owner must be able to read/write the bucket (the org-level owner role is
inherited; otherwise grant yourself `roles/storage.objectAdmin` on the bucket first).

## 5. Build and push the builder image

Image tags are immutable: use the OpenTofu version as the tag (bump `builder/Dockerfile`
and `TOFU_VERSION` together for a new version).

```bash
gcloud auth configure-docker "${REGION}-docker.pkg.dev"
docker build --build-arg TOFU_VERSION="$TOFU_VERSION" -t "$BUILDER_IMAGE" builder
docker push "$BUILDER_IMAGE"
gcloud artifacts docker images list "$BUILDER_REPO" --project="$SEED_PROJECT"
```

## 6. Safekeeping and pipeline inputs

Stage 0 is applied by a human, not by a trigger, so keep its tfvars in the bucket for reuse.
The pipeline reads `tfvars/<stage-key>/terraform.tfvars` for every other stage; upload those
too (keys: `1-org`, `2-environments`, `3-cicd-wif`, `3-cicd-ar`) before their first build.

```bash
gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/0-bootstrap/terraform.tfvars"
# for each pipeline stage:  gcloud storage cp <stage>/terraform.tfvars "gs://${STATE_BUCKET}/tfvars/<stage-key>/terraform.tfvars"
```

## 7. GitHub

1. Push `cloud-ops` to GitHub as a **public** repo (branch protection needs a public repo on
   GitHub Free). Check the repo first for secrets/personal data (see AGENTS.md).
2. Branch protection on `main`: require a pull request with 1 approving review, optional
   CODEOWNERS review, no force push; restrict write access to the devops team
   (org-level settings: `runbooks/github-org.md`).
3. Create the Cloud Build **2nd-gen GitHub connection** in the Console (interactive OAuth /
   GitHub App install; cannot be done by IaC): Cloud Build → Repositories → 2nd gen →
   *Create host connection* → GitHub; project `$SEED_PROJECT`, region `$REGION`, name
   `$CONNECTION`. When GitHub asks for the repositories, install the Cloud Build GitHub App
   **only on the `cloud-ops` repo**.

```bash
gcloud builds connections describe "$CONNECTION" --region="$REGION" --project="$SEED_PROJECT" \
  --format='value(installationState.stage)'    # expect COMPLETE
```

## 8. Second apply (triggers)

In `terraform.tfvars` set:

```hcl
enable_github          = true
builder_image          = "<value of $BUILDER_IMAGE>"
github_connection_name = "<value of $CONNECTION>"
github_repo_uri        = "https://github.com/<GITHUB_OWNER>/<GITHUB_REPO>.git"
```

```bash
tofu init -backend-config=backend.hcl
tofu apply            # creates the repository link and 8 triggers
gcloud storage cp terraform.tfvars "gs://${STATE_BUCKET}/tfvars/0-bootstrap/terraform.tfvars"
```

## 9. Verification

```bash
# 8 triggers: <key>-plan / <key>-apply for 1-org, 2-environments, 3-cicd-wif, 3-cicd-ar
gcloud builds triggers list --region="$REGION" --project="$SEED_PROJECT" \
  --format='table(name,filename,serviceAccount.basename())'

# include_build_logs must be unset (empty output) on every trigger
for t in $(gcloud builds triggers list --region="$REGION" --project="$SEED_PROJECT" --format='value(name)'); do
  echo "$t: [$(gcloud builds triggers describe "$t" --region="$REGION" --project="$SEED_PROJECT" --format='value(includeBuildLogs)')]"
done

# apply triggers require approval
gcloud builds triggers describe 1-org-apply --region="$REGION" --project="$SEED_PROJECT" \
  --format='value(approvalConfig.approvalRequired)'     # True

# IaC SA roles: org, billing account, seed project, state bucket, builder repo
gcloud organizations get-iam-policy "$ORG_ID" --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:iac-' --format='table(bindings.members,bindings.role)'
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:iac-' --format='table(bindings.members,bindings.role)'
gcloud projects get-iam-policy "$SEED_PROJECT" --flatten='bindings[].members' \
  --format='table(bindings.members,bindings.role)'
gcloud storage buckets get-iam-policy "gs://${STATE_BUCKET}"
gcloud artifacts repositories get-iam-policy iac-builder --location="$REGION" --project="$SEED_PROJECT"

# actAs on the IaC SAs: only the trigger admin(s)
for sa in iac-org-plan iac-org-apply iac-project-plan iac-project-apply; do
  gcloud iam service-accounts get-iam-policy "${sa}@${SEED_PROJECT}.iam.gserviceaccount.com" --project="$SEED_PROJECT" \
    --format='table(bindings.role,bindings.members)'
done
```

Expected: org tier only has the org roles listed in `stages/0-bootstrap/iam.tf`; project-tier
SAs have no org/billing role; humans on the seed project have only Cloud Build/Logging roles.
Then open a test PR touching `stages/1-org/` and confirm the `1-org-plan` build runs.
