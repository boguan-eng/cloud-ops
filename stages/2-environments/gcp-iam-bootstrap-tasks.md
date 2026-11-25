> **Superseded (2026-11-25):** historical record of the pre-restructure work. Current sources: [requirements](../foundation-requirements.md), [design](../foundation-design.md), [tasks](../foundation-tasks.md) and the [stage README](README.md).

# GCP IAM Bootstrap — Tasks

Design: `stages/2-environments/gcp-iam-bootstrap-design.md`

| # | Owner | Work | Acceptance | Status |
|---|---|---|---|---|
| T0 | user + main | Prerequisites 1–4 (ADC login, folderCreator grant, group principal test) | gcloud output shows success; test binding removed | done |
| T1 | subagent | Write tofu code, `.gitignore`, `terraform.tfvars.example` | V1 (`tofu init` + `validate` + `fmt -check`), V4 | done |
| T1b | main | Write `stages/2-environments/RUNBOOK.md` (all commands, parameterized) | commands match those actually executed | done |
| T2 | subagent | `plan` with real tfvars; `apply` only after user approval | V1 (only creates), V2 | done (+ project_services, developer serviceUsageConsumer) |
| T3 | main + user | Effective permission test with a test account (add to group, test, remove) | V3 | done |

Order: T0 ∥ T1 → T2 → T3 → T1b finalized with actual commands.
