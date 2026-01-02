terraform {
  required_version = ">= 1.5.0"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 0.35"
    }
  }

  # Backend configuration for remote state
  backend "s3" {
    bucket = "chom-terraform-state"
    key    = "production/terraform.tfstate"
    region = "eu-west-1"
    # Optionally use OVH Object Storage as S3-compatible backend
    # endpoints = {
    #   s3 = "https://s3.rbx.io.cloud.ovh.net"
    # }
  }
}

provider "ovh" {
  endpoint           = var.ovh_endpoint
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

# ============================================================================
# LOCAL VARIABLES
# ============================================================================

locals {
  project_name = "chom"
  environment  = var.environment

  common_tags = {
    Project     = local.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    CreatedAt   = timestamp()
  }

  vps_configs = {
    observability = {
      name        = "mentat.arewel.com"
      ip          = "51.254.139.78"
      datacenter  = "rbx"
      model       = "vps-value-1-2-40"
      description = "Observability Stack - Prometheus, Grafana, Loki, Tempo"
      monitoring  = true
      backup      = true
    }
    application = {
      name        = "landsraad.arewel.com"
      ip          = "51.77.150.96"
      datacenter  = "rbx"
      model       = "vps-value-1-2-40"
      description = "CHOM Application Server - Laravel SaaS Platform"
      monitoring  = true
      backup      = true
    }
  }
}

# ============================================================================
# DATA SOURCES
# ============================================================================

# Get available VPS models
data "ovh_vps_models" "available" {}

# ============================================================================
# VPS INSTANCES
# ============================================================================

# Observability Stack VPS
resource "ovh_vps" "observability" {
  count = var.create_vps ? 1 : 0

  name        = local.vps_configs.observability.name
  datacenter  = local.vps_configs.observability.datacenter
  model       = local.vps_configs.observability.model
  description = local.vps_configs.observability.description

  # Optional: Enable monitoring
  monitoring = local.vps_configs.observability.monitoring

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [
      # Ignore changes to certain attributes that might change outside Terraform
      description,
    ]
  }

  # Note: VPS provisioning is manual through OVH console
  # This resource mainly documents the infrastructure
}

# Application VPS
resource "ovh_vps" "application" {
  count = var.create_vps ? 1 : 0

  name        = local.vps_configs.application.name
  datacenter  = local.vps_configs.application.datacenter
  model       = local.vps_configs.application.model
  description = local.vps_configs.application.description

  monitoring = local.vps_configs.application.monitoring

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [
      description,
    ]
  }
}

# ============================================================================
# DNS CONFIGURATION
# ============================================================================

# Observability DNS A Record
resource "ovh_domain_zone_record" "observability_a" {
  count = var.manage_dns ? 1 : 0

  zone      = var.domain_zone
  subdomain = "mentat"
  fieldtype = "A"
  ttl       = 3600
  target    = local.vps_configs.observability.ip
}

# Application DNS A Record
resource "ovh_domain_zone_record" "application_a" {
  count = var.manage_dns ? 1 : 0

  zone      = var.domain_zone
  subdomain = "landsraad"
  fieldtype = "A"
  ttl       = 3600
  target    = local.vps_configs.application.ip
}

# ============================================================================
# BACKUP CONFIGURATION (Object Storage for offsite backups)
# ============================================================================

# Create Object Storage container for backups
resource "ovh_cloud_project_storage_s3" "backups" {
  count = var.create_backup_storage ? 1 : 0

  service_name = var.ovh_cloud_project_id
  name         = "${local.project_name}-backups-${var.environment}"
  region       = var.backup_region

  lifecycle_policy = jsonencode({
    Rules = [
      {
        ID     = "expire-old-backups"
        Status = "Enabled"
        Filter = {
          Prefix = "database/"
        }
        Expiration = {
          Days = var.backup_retention_days
        }
      },
      {
        ID     = "transition-to-glacier"
        Status = "Enabled"
        Filter = {
          Prefix = "archive/"
        }
        Transitions = [
          {
            Days         = 30
            StorageClass = "GLACIER"
          }
        ]
      }
    ]
  })
}

# ============================================================================
# MONITORING & ALERTING
# ============================================================================

# OVH Cloud Database for external monitoring database (optional)
resource "ovh_cloud_project_database" "monitoring_db" {
  count = var.create_monitoring_db ? 1 : 0

  service_name = var.ovh_cloud_project_id
  description  = "Monitoring metrics database"
  engine       = "postgresql"
  version      = "15"
  plan         = "essential"
  flavor       = "db1-7"

  nodes {
    region = var.backup_region
  }

  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "observability_vps" {
  description = "Observability VPS configuration"
  value = {
    name = local.vps_configs.observability.name
    ip   = local.vps_configs.observability.ip
    url  = "https://${local.vps_configs.observability.name}"
  }
}

output "application_vps" {
  description = "Application VPS configuration"
  value = {
    name = local.vps_configs.application.name
    ip   = local.vps_configs.application.ip
    url  = "https://${local.vps_configs.application.name}"
  }
}

output "backup_storage" {
  description = "Backup storage information"
  value = var.create_backup_storage ? {
    bucket_name = ovh_cloud_project_storage_s3.backups[0].name
    region      = var.backup_region
    endpoint    = "https://s3.${var.backup_region}.io.cloud.ovh.net"
  } : null
}

output "dns_records" {
  description = "DNS record configuration"
  value = var.manage_dns ? {
    observability = "${ovh_domain_zone_record.observability_a[0].subdomain}.${var.domain_zone}"
    application   = "${ovh_domain_zone_record.application_a[0].subdomain}.${var.domain_zone}"
  } : null
}

output "infrastructure_summary" {
  description = "Complete infrastructure summary"
  value = {
    project     = local.project_name
    environment = var.environment
    vps_count   = var.create_vps ? 2 : 0
    backups     = var.create_backup_storage
    monitoring  = var.create_monitoring_db
    managed_by  = "Terraform"
  }
}
