# Identity options for people

This compares human identities, not [Workload Identity Federation for GitHub Actions](../3-cicd/README.md).

| Option | Price and prerequisites | Benefits and limits |
|---|---|---|
| **A. Standalone org, no domain (current)** | Consumer Google accounts and consumer Google Groups. Separate price for this consumer setup: not stated by the vendor (checked 2026-11-25). No domain or central directory to maintain. | Groups work for IAM and PAM eligibility, but group membership changes are not in GCP audit logs ([approver runbook](../../runbooks/ops/change-approver.md)). No domain-restricted sharing in this setup. PAM auto-notification is limited to Cloud Identity users/groups; explicit email recipients did not fix delivery to the consumer approvers group (T7-12). |
| **B. Verified domain + Cloud Identity Free** | No charge; signing up adds 50 users to the cap (50 initial users from zero, with increases possible). Requires registrar admin access and a verified domain — [editions](https://docs.cloud.google.com/identity/docs/editions) (read 2026-11-25), [licensing](https://docs.cloud.google.com/identity/docs/how-to/how-licensing-works-for-cloud-identity) (read 2026-11-25), [setup](https://docs.cloud.google.com/identity/docs/how-to/set-up-cloud-identity-admin) (read 2026-11-25). | Central accounts and groups allow managed onboarding/offboarding and meet PAM's auto-notification identity requirement. Plan for a **new organization and project moves**: this is an inference from the [requirements](../foundation-requirements.md#scope), not a tested migration path. Claiming a standalone org is limited to organizations created by users of the domain. |
| **C. Workforce Identity Federation + external IdP** | Google Cloud IAM includes workforce federation at no additional per-user or per-identity cost — [IAM pricing](https://cloud.google.com/products/iam) (read 2026-11-25). Requires an external identity provider. See examples below. | Reuses an existing workforce directory for human GCP access. Maintain the IdP, attribute mappings and IAM. This does not by itself supply Cloud Identity principals for PAM auto-notifications. |

| External workforce IdP | Vendor plan price (not a Google federation charge) |
|---|---|
| Okta | Workforce Identity Starter: $6/user/month, billed annually, with a $1,500 annual contract minimum — [Okta pricing](https://www.okta.com/pricing/) (read 2026-11-25). |
| Microsoft Entra ID | P1: $7/user/month, paid yearly (US listing). Entra ID Free is included with Microsoft 365 or Azure; standalone signup requires an Azure subscription — [Microsoft pricing](https://www.microsoft.com/en-us/security/microsoft-entra-pricing) (read 2026-11-25). |

## Recommendation

**Stay on A now.** Contact PAM approvers directly, have billing viewers check the budget in the Console, and have devops inspect check builds; don't depend on group email delivery.

**Move to B when a verified domain is available.** Plan the new org and project moves, then test IAM and all three deferred T7-12 notification paths (PAM, budget, and check failures). Cloud Identity unblocks that work; it doesn't prove delivery or configure check-failure alerts by itself. Consider C if the team already uses an external IdP and wants GCP access managed through it.
