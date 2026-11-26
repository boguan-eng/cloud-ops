# Monthly budget on the whole billing account, alerting by email (T7-5).
# Applied by iac-org-apply (billing.costsManager on the billing account; on the seed project
# monitoring.notificationChannelEditor + serviceusage.serviceUsageConsumer).
#
# The Budget API needs a quota project when called with user/SA tokens: this alias sets
# billing_project + user_project_override. Only the channel and the budget use it.
provider "google" {
  alias                 = "billing"
  billing_project       = var.seed_project_id
  user_project_override = true
}

variable "billing_account" {
  description = "Billing account ID (format XXXXXX-XXXXXX-XXXXXX) the budget applies to."
  type        = string
}

variable "seed_project_id" {
  description = "Seed project ID: quota project for the Budget API and host of the notification channel."
  type        = string
}

variable "budget_amount" {
  description = "Monthly budget in whole currency units (see budget_currency)."
  type        = number
}

variable "budget_currency" {
  description = "ISO 4217 currency code; must match the billing account currency."
  type        = string
  default     = "TWD"
}

variable "budget_thresholds" {
  description = "Alert thresholds as fractions of the budget (0.5 = 50 %), on current spend."
  type        = list(number)
  default     = [0.5, 0.9, 1.0]
}

variable "billing_alert_email" {
  description = "Individual user email address for billing alerts; mail to group addresses is not delivered in this domain."
  type        = string
}

resource "google_monitoring_notification_channel" "billing_email" {
  provider     = google.billing
  project      = var.seed_project_id
  display_name = "Billing alerts"
  type         = "email"

  labels = {
    email_address = var.billing_alert_email
  }
}

resource "google_billing_budget" "monthly" {
  provider        = google.billing
  billing_account = var.billing_account
  display_name    = "Monthly budget"

  # No projects/services filter: the whole billing account.
  budget_filter {
    calendar_period = "MONTH"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.billing_email.id]
    # Keep default emails to billing admins/users in addition to the group.
    disable_default_iam_recipients = false
  }
}
