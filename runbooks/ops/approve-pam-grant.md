# Elevate to Prod Write (PAM) — Request and Approve

Direct write access to prod, **incidents only** (pipeline broken, urgent rollback). Normal
changes go through a PR ([change-via-pr.md](change-via-pr.md)). The access is time-limited
and needs a second person.

**Who / which account:**
- **Requester:** a `devops` member, user in `gcp-devops`.
- **Approver:** a member of `gcp-approvers` (Console only; never the requester).
- **Admin (Org Owner):** break-glass only (nobody holds a standing revoke right; see step 6).

**Prerequisites:** stage 2 applied (entitlement `prod-operator` on the prod folder exists);
variable `PROD_FOLDER_ID` (numeric folder ID, from the stage 2 output; never commit it);
`gcloud` signed in as the requester.
**Next:** [run-checks.md](run-checks.md) (step 7).

**Notifications:** PAM emails go to the individual addresses in `pam_approver_emails` (group
addresses get no mail in this domain, spike S1). Until delivery is verified (spike S4), the
requester also tells an approver directly (chat) and sends the grant ID.

## 1. Requester: request the grant

Duration 1800–14400 s (30 min–4 h); ask for the shortest that fits the work.

```bash
export PROD_FOLDER_ID=<PROD_FOLDER_ID>
gcloud beta pam grants create --entitlement=prod-operator --requested-duration=3600s \
  --justification="<incident / ticket and why a PR is not possible>" \
  --location=global --folder="$PROD_FOLDER_ID"
```

Verify: the output shows `state: APPROVAL_AWAITED` and the grant name; note the `<GRANT_ID>`
(last path segment).

## 2. Requester: notify an approver

Tell an approver (chat or phone): "PAM request `<GRANT_ID>`, prod folder, `<duration>`, reason
`<…>`". Do not put the folder ID in public places (issues, PRs).

## 3. Approver: approve in the Console

1. Open <https://console.cloud.google.com/iam-admin/pam/grants/approvals> with the approver account.
2. In the resource picker select the **prod folder** (approvers have
   `resourcemanager.folderViewer` there; without it the page says "You need additional access").
3. Open the request, check that the requester and justification match what you were told
   (a request you were not told about: **Deny**), then **Approve** with a justification.

Verify: the grant shows **Active** within seconds.

## 4. Requester: verify and do the incident work

```bash
gcloud beta pam grants describe <GRANT_ID> --entitlement=prod-operator \
  --location=global --folder="$PROD_FOLDER_ID" --format='value(state)'   # expect ACTIVE
```

Do only what the incident needs, in the prod project(s). Note each command and why, for the PR in
step 7. If the work will outlast the grant, request a new one before it ends.

## 5. Grant expires

The grant ends by itself at the requested duration; write permissions are removed.

```bash
gcloud beta pam grants describe <GRANT_ID> --entitlement=prod-operator \
  --location=global --folder="$PROD_FOLDER_ID" --format='value(state)'   # expect ENDED
```

## 6. Ending early or an emergency

Nobody holds a revoke right (only `privilegedaccessmanager.admin` can revoke; it is not
granted, since it can also edit entitlements). Wait for expiry, so request short grants. If the
grant must stop now, or the access is misused, the Org Owner acts with break-glass.

## 7. Reconcile (always)

1. Open a PR that makes the code match what you changed
   ([change-via-pr.md](change-via-pr.md)); merge and wait for the approved apply.
2. Run the check for each affected stage ([run-checks.md](run-checks.md)) and expect
   **SUCCESS** (no diff). A FAILURE with a diff means the manual change and the code differ:
   fix the code or revert the change, and repeat.
