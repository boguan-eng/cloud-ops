variable "org_id" {
  description = "Numeric GCP organization ID (without the 'organizations/' prefix)."
  type        = string
}

variable "allowed_policy_member_customer_ids" {
  description = "Cloud Identity customer IDs allowed in IAM policies, in the bare format returned by the organization policy (no 'is:' prefix)."
  type        = list(string)
}

variable "allowed_contact_domains" {
  description = "Allowed Essential Contacts domains, including the leading @ (e.g. @example.com)."
  type        = list(string)
}
