# Foundation (Chapter 1) — Tasks

Design: `stages/foundation-design.md`. Each task is accepted by the main agent before the next.

| # | Task | Acceptance evidence | Status |
|---|---|---|---|
| T1 | PAM spike on prod project: group requester, Gmail approver; request → approve → expiry; check PAM SKUs in Cloud Billing Catalog; clean up | Denied before, allowed during, denied after expiry; SKU result; entitlement deleted | PASS (2026-11-24): consumer group requester + Gmail approver work; allowed ~6s after activation; denied after expiry and after revoke; Create/Approve/Activate/End/Revoke in audit logs; no PAM service in Billing Catalog; cleaned up. Note: base PAM only (single-level approval). User confirmed Gmail notifications work (docs only mention Cloud Identity users): approver received "Approve or deny ... grant"; requester received "Your grant has been revoked" |
| T2 | Restructure repo files into `stages/`; split `gcp-iam-bootstrap` code into `1-org` and `2-environments`; move `docs/*` | `tofu validate` per stage; no file lost (git diff --stat) | PASS (2026-11-24): resource addresses identical; 4 stages validate; wif/ar code unchanged; ignored state/tfvars left in old dirs for T5 |
| T3 | Stage 0 code: seed project, bucket, AR, builder Dockerfile, 4 IaC SAs, triggers, cloudbuild yaml; runbooks A and B | `tofu validate`; runbooks match code | PASS (2026-11-24): validate/fmt OK; builder image (tofu 1.13.1 + gcloud 594.0.0) builds and runs; read-only plan with real values = 55 to add, 0 change/destroy; all 21 role IDs exist; Cloud Billing IAM has no conditions → method B removes billing.admin manually. Triggers only validated (gated by enable_github) |
| T4 | Apply stage 0 as Org Owner. User manually: push `cloud-ops` to GitHub (public), install Cloud Build GitHub App, branch protection | Resources exist; SA roles match design table | T4-1 PASS (2026-11-24): 55 resources applied, state migrated to GCS (plan = no changes), builder image tofu:1.13.1 pushed (immutable tags), all SA/human roles verified. T4-2/T4-3 pending |
| T5 | Split and migrate state (local / nonprod bucket → seed bucket) | `tofu plan` = 0 changes for every stage, before and after | |
| T6 | Pipeline acceptance | PR → plan in GCP only, no GitHub logs; merge → pending approval; approve → apply 0 changes; audit log entry | |
| T7 | Permission changes via PR (second Org Owner added first) | devops denied on prod without elevation, allowed with, expires; developers view-only; plan SA cannot write | |
| T8 | Documentation (README, per-stage README with third-party prices + sources, identity options, b1 example, Infra Manager note) | Main agent review; public-repo checks | |
