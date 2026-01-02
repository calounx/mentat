variable "environment" {
  description = "Environment name (production, staging, development)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

variable "ovh_endpoint" {
  description = "OVH API endpoint"
  type        = string
  default     = "ovh-eu"

  validation {
    condition     = contains(["ovh-eu", "ovh-ca", "ovh-us"], var.ovh_endpoint)
    error_message = "OVH endpoint must be ovh-eu, ovh-ca, or ovh-us."
  }
}

variable "ovh_application_key" {
  description = "OVH API application key"
  type        = string
  sensitive   = true
}

variable "ovh_application_secret" {
  description = "OVH API application secret"
  type        = string
  sensitive   = true
}

variable "ovh_consumer_key" {
  description = "OVH API consumer key"
  type        = string
  sensitive   = true
}

variable "ovh_cloud_project_id" {
  description = "OVH Public Cloud project ID"
  type        = string
}

variable "domain_zone" {
  description = "DNS zone for the domain"
  type        = string
  default     = "arewel.com"
}

variable "create_vps" {
  description = "Whether to create VPS instances (usually false for existing infrastructure)"
  type        = bool
  default     = false
}

variable "manage_dns" {
  description = "Whether to manage DNS records via Terraform"
  type        = bool
  default     = true
}

variable "create_backup_storage" {
  description = "Whether to create Object Storage for backups"
  type        = bool
  default     = true
}

variable "backup_region" {
  description = "Region for backup storage"
  type        = string
  default     = "GRA"

  validation {
    condition     = contains(["GRA", "SBG", "BHS", "DE", "UK", "WAW"], var.backup_region)
    error_message = "Backup region must be a valid OVH region."
  }
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 90

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "Backup retention must be between 7 and 365 days."
  }
}

variable "create_monitoring_db" {
  description = "Whether to create a separate monitoring database"
  type        = bool
  default     = false
}

variable "enable_ha" {
  description = "Enable high availability configuration"
  type        = bool
  default     = false
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for application servers"
  type        = bool
  default     = false
}

variable "notification_email" {
  description = "Email address for infrastructure notifications"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}
