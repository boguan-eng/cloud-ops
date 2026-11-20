# GCP IAM Bootstrap — Runbook

Re-usable for any GCP organization. Run from the repo root unless noted.
Design: `docs/gcp-iam-bootstrap-design.md`.

## 0. Variables (fill per org; never commit real values)

```bash
export ORG_ID="123456789012"                       # gcloud organizations list
export BILLING_ACCOUNT="000000-000000-000000"      # gcloud billing accounts list
export ADMIN_ACCOUNT="admin@example.com"           # account that runs tofu
export PREFIX="acme"
export G_ADMINS="${PREFIX}-gcp-admins@googlegroups.com"
export G_DEVOPS="${PREFIX}-gcp-devops@googlegroups.com"
export G_DEVELOPERS="${PREFIX}-gcp-developers@googlegroups.com"
```

## 1. Prerequisites (once per org)

### 1.1 Create groups (manual, browser)

At https://groups.google.com create the 3 groups above, signed in as the admin.
Only admins may be Owner/Manager of the groups (membership = permission).
Double-check the 3 group emails match `terraform.tfvars` exactly: IAM rejects a group that
does not exist, and `tofu apply` would fail part-way (fix the email and re-run apply).
(`@googlegroups.com` groups are confirmed to work as IAM principals.)

### 1.2 Login

```bash
gcloud auth login "$ADMIN_ACCOUNT"
gcloud auth application-default login            # choose $ADMIN_ACCOUNT in the browser
gcloud organizations list --account="$ADMIN_ACCOUNT"
gcloud billing accounts list --account="$ADMIN_ACCOUNT"
```

### 1.3 Allow the admin account to create folders

organizationAdmin does not include `resourcemanager.folders.create`.

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" --account="$ADMIN_ACCOUNT" \
  --member="user:$ADMIN_ACCOUNT" --role=roles/resourcemanager.folderCreator --condition=None
```

## 2. Apply

```bash
cd gcp-iam-bootstrap
cp terraform.tfvars.example terraform.tfvars      # edit with real values (git-ignored)
tofu init -input=false
tofu plan -out=bootstrap.tfplan                   # expect: only "to add", 0 change, 0 destroy
tofu apply bootstrap.tfplan
tofu output
```

## 2a. Adjust roles / APIs (after initial apply)

Role lists and APIs are variables with defaults in `variables.tf`:
`admin_org_roles`, `devops_roles`, `devops_nonprod_extra_roles`, `developer_roles`, `project_services`.
To change them, copy the commented block from `terraform.tfvars.example` into `terraform.tfvars`,
uncomment, and edit. An override replaces the whole default list.

Example: devops does not need GKE → set `devops_roles` without `"roles/container.admin"`.

```bash
cd gcp-iam-bootstrap
tofu plan -out=change.tfplan      # check: only the intended IAM members are added/destroyed
tofu apply change.tfplan
rm -f change.tfplan
```

Removing a role from a list destroys only that IAM member (additive resources);
other bindings on the org/folder are not touched. Removing an API from `project_services`
only drops it from state (`disable_on_destroy = false`); the API stays enabled.

## 3. Verify (V2)

```bash
gcloud organizations get-iam-policy "$ORG_ID" --account="$ADMIN_ACCOUNT" \
  --flatten=bindings --filter="bindings.members:group:$G_ADMINS" --format="value(bindings.role)"

for ENV in prod nonprod; do
  FOLDER=$(cd gcp-iam-bootstrap && tofu output -json folder_ids | jq -r ".$ENV")
  echo "== $ENV ($FOLDER)"
  gcloud resource-manager folders get-iam-policy "$FOLDER" --account="$ADMIN_ACCOUNT" \
    --flatten=bindings --format="table(bindings.role,bindings.members)"
done

gcloud projects list --account="$ADMIN_ACCOUNT" --filter="projectId:${PREFIX}-app-*" --format="table(projectId,parent.id,lifecycleState)"
```

## 4. Effective permission test (V3)

Use a spare test account (`TEST_ACCOUNT`, logged in via `gcloud auth login`).
Group membership changes take ~1–2 min to propagate; poll before testing:

```bash
export TEST_ACCOUNT="tester@example.com"
export P_PROD="${PREFIX}-app-prod" P_NONPROD="${PREFIX}-app-nonprod"
perm(){ # perm <project> <perm>...  -> prints granted permissions
  local P=$1; shift; local T; T=$(gcloud auth print-access-token --account="$TEST_ACCOUNT")
  curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/$P:testIamPermissions" \
    -d "{\"permissions\":$(printf '%s\n' "$@" | jq -R . | jq -sc .)}" | jq -c .permissions; }
```

### 4.1 developers round (TEST_ACCOUNT only in developers group)

```bash
for P in $P_PROD $P_NONPROD; do
  gcloud logging read 'timestamp>="2020-01-01T00:00:00Z"' --project=$P --account=$TEST_ACCOUNT --limit=1   # expect OK
  gcloud monitoring dashboards list --project=$P --account=$TEST_ACCOUNT                                  # expect OK
  gcloud logging write v3-test "x" --project=$P --account=$TEST_ACCOUNT                                   # expect DENIED
  gcloud services enable pubsub.googleapis.com --project=$P --account=$TEST_ACCOUNT                       # expect DENIED
  gcloud projects add-iam-policy-binding $P --account=$TEST_ACCOUNT \
    --member=user:$TEST_ACCOUNT --role=roles/viewer --condition=None                                       # expect DENIED
  perm $P compute.instances.list logging.logEntries.list monitoring.timeSeries.list                         # expect no compute.*
done
```

### 4.2 devops round (move TEST_ACCOUNT from developers to devops group)

```bash
SFX=$(date +%s | tail -c 6)
for P in $P_PROD $P_NONPROD; do
  gcloud services enable pubsub.googleapis.com --project=$P --account=$TEST_ACCOUNT                       # expect OK
  gcloud storage buckets create gs://$P-v3-$SFX --project=$P --location=asia-east1 --account=$TEST_ACCOUNT # expect OK
  gcloud storage buckets delete gs://$P-v3-$SFX --account=$TEST_ACCOUNT --quiet                            # cleanup
done
gcloud projects add-iam-policy-binding $P_PROD --account=$TEST_ACCOUNT \
  --member=user:$TEST_ACCOUNT --role=roles/viewer --condition=None                                         # expect DENIED
gcloud projects add-iam-policy-binding $P_NONPROD --account=$TEST_ACCOUNT \
  --member=user:$TEST_ACCOUNT --role=roles/viewer --condition=None                                         # expect OK
gcloud projects remove-iam-policy-binding $P_NONPROD --account=$TEST_ACCOUNT \
  --member=user:$TEST_ACCOUNT --role=roles/viewer                                                          # cleanup
gcloud resource-manager folders create --display-name=v3-test --organization=$ORG_ID --account=$TEST_ACCOUNT # expect DENIED
gcloud projects create ${PREFIX}-v3-test-$SFX --organization=$ORG_ID --account=$TEST_ACCOUNT               # expect DENIED
# Billing: devops must not appear here (billing perms only come from billing-account IAM or org IAM)
gcloud billing accounts get-iam-policy "$BILLING_ACCOUNT" --account="$ADMIN_ACCOUNT"
gcloud organizations get-iam-policy "$ORG_ID" --account="$ADMIN_ACCOUNT" --flatten=bindings --filter="bindings.role~billing"
```

### 4.3 Cleanup

```bash
for P in $P_PROD $P_NONPROD; do
  gcloud services disable pubsub.googleapis.com --project=$P --account=$ADMIN_ACCOUNT --quiet
done
# Remove TEST_ACCOUNT from all groups (groups.google.com). Then confirm no drift:
(cd gcp-iam-bootstrap && tofu plan -detailed-exitcode)   # exit 0 = no changes
rm -f gcp-iam-bootstrap/*.tfplan
```

### Pitfalls found

- `gcloud compute instances list` (aggregated) shows `Listed 0 items` instead of an error when
  permission is missing. Use `perm` or a zonal API call to check denial.
- gcloud sends the current project as quota project by default; without
  `serviceusage.services.use` calls fail with `USER_PROJECT_DENIED`
  (reason developers get `serviceusage.serviceUsageConsumer`).
- New projects do not have Logging/Monitoring APIs enabled; tofu enables them (`project_services`).
- The project's linked billing account ID is visible to anyone with `resourcemanager.projects.get`;
  billing data/costs are not.
- Creating a folder/project makes the creator folderAdmin/folderEditor (folder) or Owner (project) automatically.

## 5. Re-use for another org

1. Section 0 with new values; 1.1–1.3; copy this directory with a fresh state
   (do not reuse `terraform.tfstate`); section 2; sections 3–4.
