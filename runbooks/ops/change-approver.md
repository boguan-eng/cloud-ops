# Add or Remove an Approver

- **Who:** the Org Owner (the only owner of the approvers group).
- **Account:** the Org Owner Google account, at <https://groups.google.com/>.
- **Why a group:** the approver roles (`cloudbuild.builds.approver`, `cloudbuild.builds.viewer`,
  `logging.viewer` on the seed project) are bound once to `<prefix>-gcp-approvers` in stage 0.
  Changing people is a group membership change; stage 0 is not re-applied.
- **Trade-off:** group membership changes are not in GCP audit logs; only Google Groups shows
  them. Approvals themselves are in the seed project audit log (`ApproveBuild`).

## 1. Group settings (once, when the group is created)

| Setting | Value |
|---|---|
| Name / email | `<prefix>-gcp-approvers` |
| Who can join | Only invited users |
| Who can view members | Group managers |
| Owner | Org Owner only |

An approver must not be in the devops or developers groups (the person who writes or reviews
a change must not release it).

## 2. Add an approver

1. The new approver has a Google account with 2-Step Verification on.
2. groups.google.com → `<prefix>-gcp-approvers` → **Members** → **Add members** → the
   account → add directly (not invite) → **Add**.
3. Verify: the new approver signs in (private window) → seed project → **Cloud Build** →
   **History** (region `us-central1`) shows builds. IAM may take a few minutes.
4. Give them [approve-apply.md](approve-apply.md).

## 3. Remove an approver

1. groups.google.com → `<prefix>-gcp-approvers` → **Members** → select → **Remove**.
2. Verify: that account no longer sees Cloud Build **History** (allow a few minutes).
3. Keep at least one approver, or no infra change can be applied.

Next: nothing.
