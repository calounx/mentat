CREATE TABLE IF NOT EXISTS "migrations"(
  "id" integer primary key autoincrement not null,
  "migration" varchar not null,
  "batch" integer not null
);
CREATE TABLE IF NOT EXISTS "cache"(
  "key" varchar not null,
  "value" text not null,
  "expiration" integer not null,
  primary key("key")
);
CREATE TABLE IF NOT EXISTS "cache_locks"(
  "key" varchar not null,
  "owner" varchar not null,
  "expiration" integer not null,
  primary key("key")
);
CREATE TABLE IF NOT EXISTS "jobs"(
  "id" integer primary key autoincrement not null,
  "queue" varchar not null,
  "payload" text not null,
  "attempts" integer not null,
  "reserved_at" integer,
  "available_at" integer not null,
  "created_at" integer not null
);
CREATE INDEX "jobs_queue_index" on "jobs"("queue");
CREATE TABLE IF NOT EXISTS "job_batches"(
  "id" varchar not null,
  "name" varchar not null,
  "total_jobs" integer not null,
  "pending_jobs" integer not null,
  "failed_jobs" integer not null,
  "failed_job_ids" text not null,
  "options" text,
  "cancelled_at" integer,
  "created_at" integer not null,
  "finished_at" integer,
  primary key("id")
);
CREATE TABLE IF NOT EXISTS "failed_jobs"(
  "id" integer primary key autoincrement not null,
  "uuid" varchar not null,
  "connection" text not null,
  "queue" text not null,
  "payload" text not null,
  "exception" text not null,
  "failed_at" datetime not null default CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX "failed_jobs_uuid_unique" on "failed_jobs"("uuid");
CREATE TABLE IF NOT EXISTS "organizations"(
  "id" varchar not null,
  "name" varchar not null,
  "slug" varchar not null,
  "billing_email" varchar not null,
  "stripe_customer_id" varchar,
  "default_tenant_id" varchar,
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("default_tenant_id") references "tenants"("id") on delete set null,
  primary key("id")
);
CREATE UNIQUE INDEX "organizations_slug_unique" on "organizations"("slug");
CREATE UNIQUE INDEX "organizations_stripe_customer_id_unique" on "organizations"(
  "stripe_customer_id"
);
CREATE TABLE IF NOT EXISTS "users"(
  "id" varchar not null,
  "organization_id" varchar,
  "name" varchar not null,
  "email" varchar not null,
  "email_verified_at" datetime,
  "password" varchar not null,
  "role" varchar check("role" in('owner', 'admin', 'member', 'viewer')) not null default 'member',
  "remember_token" varchar,
  "two_factor_enabled" tinyint(1) not null default '0',
  "two_factor_secret" text,
  "created_at" datetime,
  "updated_at" datetime,
  "two_factor_backup_codes" text,
  "two_factor_confirmed_at" datetime,
  "password_confirmed_at" datetime,
  "ssh_key_rotated_at" datetime,
  foreign key("organization_id") references "organizations"("id") on delete cascade,
  primary key("id")
);
CREATE INDEX "users_organization_id_index" on "users"("organization_id");
CREATE UNIQUE INDEX "users_email_unique" on "users"("email");
CREATE TABLE IF NOT EXISTS "password_reset_tokens"(
  "email" varchar not null,
  "token" varchar not null,
  "created_at" datetime,
  primary key("email")
);
CREATE TABLE IF NOT EXISTS "sessions"(
  "id" varchar not null,
  "user_id" varchar,
  "ip_address" varchar,
  "user_agent" text,
  "payload" text not null,
  "last_activity" integer not null,
  primary key("id")
);
CREATE INDEX "sessions_user_id_index" on "sessions"("user_id");
CREATE INDEX "sessions_last_activity_index" on "sessions"("last_activity");
CREATE TABLE IF NOT EXISTS "vps_servers"(
  "id" varchar not null,
  "hostname" varchar not null,
  "ip_address" varchar not null,
  "provider" varchar not null,
  "provider_id" varchar,
  "region" varchar,
  "spec_cpu" integer not null,
  "spec_memory_mb" integer not null,
  "spec_disk_gb" integer not null,
  "status" varchar check("status" in('provisioning', 'active', 'maintenance', 'failed', 'decommissioned')) not null default 'provisioning',
  "allocation_type" varchar check("allocation_type" in('shared', 'dedicated')) not null default 'shared',
  "vpsmanager_version" varchar,
  "observability_configured" tinyint(1) not null default '0',
  "ssh_key_id" varchar,
  "last_health_check_at" datetime,
  "health_status" varchar check("health_status" in('healthy', 'degraded', 'unhealthy', 'unknown')) not null default 'unknown',
  "created_at" datetime,
  "updated_at" datetime,
  "ssh_private_key" text,
  "ssh_public_key" text,
  "key_rotated_at" datetime,
  "previous_ssh_private_key" text,
  "previous_ssh_public_key" text,
  primary key("id")
);
CREATE UNIQUE INDEX "vps_servers_hostname_unique" on "vps_servers"("hostname");
CREATE TABLE IF NOT EXISTS "vps_allocations"(
  "id" varchar not null,
  "vps_id" varchar not null,
  "tenant_id" varchar not null,
  "sites_allocated" integer not null default '0',
  "storage_mb_allocated" integer not null default '0',
  "memory_mb_allocated" integer not null default '0',
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("vps_id") references "vps_servers"("id") on delete cascade,
  foreign key("tenant_id") references "tenants"("id") on delete cascade,
  primary key("id")
);
CREATE UNIQUE INDEX "vps_allocations_vps_id_tenant_id_unique" on "vps_allocations"(
  "vps_id",
  "tenant_id"
);
CREATE INDEX "vps_allocations_tenant_id_index" on "vps_allocations"(
  "tenant_id"
);
CREATE TABLE IF NOT EXISTS "site_backups"(
  "id" varchar not null,
  "site_id" varchar not null,
  "filename" varchar,
  "backup_type" varchar check("backup_type" in('full', 'files', 'database', 'config', 'manual', 'scheduled')) not null default 'full',
  "status" varchar check("status" in('pending', 'in_progress', 'completed', 'failed')) not null default 'pending',
  "storage_path" varchar,
  "size_bytes" integer,
  "size_mb" integer,
  "checksum" varchar,
  "retention_days" integer not null default '30',
  "expires_at" datetime,
  "completed_at" datetime,
  "error_message" text,
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("site_id") references "sites"("id") on delete cascade,
  primary key("id")
);
CREATE INDEX "site_backups_site_id_index" on "site_backups"("site_id");
CREATE INDEX "site_backups_status_index" on "site_backups"("status");
CREATE INDEX "site_backups_expires_at_index" on "site_backups"("expires_at");
CREATE INDEX "site_backups_created_at_index" on "site_backups"("created_at");
CREATE TABLE IF NOT EXISTS "subscriptions"(
  "id" varchar not null,
  "organization_id" varchar not null,
  "stripe_subscription_id" varchar not null,
  "stripe_price_id" varchar,
  "tier" varchar check("tier" in('starter', 'pro', 'enterprise')) not null,
  "status" varchar not null default 'active',
  "trial_ends_at" datetime,
  "current_period_start" datetime not null,
  "current_period_end" datetime not null,
  "cancelled_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  "canceled_at" datetime,
  foreign key("organization_id") references "organizations"("id") on delete cascade,
  primary key("id")
);
CREATE INDEX "subscriptions_organization_id_index" on "subscriptions"(
  "organization_id"
);
CREATE INDEX "subscriptions_status_index" on "subscriptions"("status");
CREATE UNIQUE INDEX "subscriptions_stripe_subscription_id_unique" on "subscriptions"(
  "stripe_subscription_id"
);
CREATE TABLE IF NOT EXISTS "usage_records"(
  "id" varchar not null,
  "tenant_id" varchar not null,
  "metric_type" varchar not null,
  "quantity" numeric not null,
  "unit_price" numeric,
  "period_start" date not null,
  "period_end" date not null,
  "stripe_usage_record_id" varchar,
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("tenant_id") references "tenants"("id") on delete cascade,
  primary key("id")
);
CREATE INDEX "usage_records_tenant_id_period_start_period_end_index" on "usage_records"(
  "tenant_id",
  "period_start",
  "period_end"
);
CREATE INDEX "usage_records_metric_type_index" on "usage_records"(
  "metric_type"
);
CREATE TABLE IF NOT EXISTS "tier_limits"(
  "tier" varchar not null,
  "name" varchar not null,
  "max_sites" integer not null,
  "max_storage_gb" integer not null,
  "max_bandwidth_gb" integer not null,
  "backup_retention_days" integer not null,
  "support_level" varchar not null,
  "dedicated_ip" tinyint(1) not null default '0',
  "staging_environments" tinyint(1) not null default '0',
  "white_label" tinyint(1) not null default '0',
  "api_rate_limit_per_hour" integer not null,
  "price_monthly_cents" integer not null,
  "created_at" datetime,
  "updated_at" datetime,
  primary key("tier")
);
CREATE TABLE IF NOT EXISTS "sites"(
  "id" varchar not null,
  "tenant_id" varchar not null,
  "vps_id" varchar,
  "domain" varchar not null,
  "site_type" varchar not null default('wordpress'),
  "php_version" varchar not null default('8.2'),
  "ssl_enabled" tinyint(1) not null default('0'),
  "ssl_expires_at" datetime,
  "status" varchar not null default('creating'),
  "document_root" varchar,
  "db_name" varchar,
  "db_user" varchar,
  "storage_used_mb" integer not null default('0'),
  "settings" text,
  "created_at" datetime,
  "updated_at" datetime,
  "deleted_at" datetime,
  foreign key("tenant_id") references tenants("id") on delete cascade on update no action,
  foreign key("vps_id") references "vps_servers"("id") on delete set null,
  primary key("id")
);
CREATE INDEX "sites_domain_index" on "sites"("domain");
CREATE INDEX "sites_status_index" on "sites"("status");
CREATE UNIQUE INDEX "sites_tenant_id_domain_unique" on "sites"(
  "tenant_id",
  "domain"
);
CREATE INDEX "sites_tenant_id_status_index" on "sites"("tenant_id", "status");
CREATE INDEX "sites_vps_id_index" on "sites"("vps_id");
CREATE TABLE IF NOT EXISTS "invoices"(
  "id" varchar not null,
  "organization_id" varchar not null,
  "stripe_invoice_id" varchar not null,
  "amount_cents" integer not null,
  "currency" varchar not null default('usd'),
  "status" varchar not null,
  "paid_at" datetime,
  "period_start" date,
  "period_end" date,
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("organization_id") references "organizations"("id") on delete restrict,
  primary key("id")
);
CREATE INDEX "invoices_organization_id_index" on "invoices"("organization_id");
CREATE INDEX "invoices_status_index" on "invoices"("status");
CREATE UNIQUE INDEX "invoices_stripe_invoice_id_unique" on "invoices"(
  "stripe_invoice_id"
);
CREATE TABLE IF NOT EXISTS "tenants"(
  "id" varchar not null,
  "organization_id" varchar not null,
  "name" varchar not null,
  "slug" varchar not null,
  "tier" varchar not null default('starter'),
  "status" varchar not null default('active'),
  "settings" text,
  "metrics_retention_days" integer not null default('15'),
  "created_at" datetime,
  "updated_at" datetime,
  "cached_storage_mb" integer not null default '0',
  "cached_sites_count" integer not null default '0',
  "cached_at" datetime,
  foreign key("organization_id") references organizations("id") on delete cascade on update no action,
  foreign key("tier") references "tier_limits"("tier") on delete restrict on update cascade,
  primary key("id")
);
CREATE UNIQUE INDEX "tenants_organization_id_slug_unique" on "tenants"(
  "organization_id",
  "slug"
);
CREATE INDEX "tenants_status_index" on "tenants"("status");
CREATE TABLE IF NOT EXISTS "operations"(
  "id" varchar not null,
  "tenant_id" varchar,
  "user_id" varchar,
  "operation_type" varchar not null,
  "target_type" varchar,
  "target_id" varchar,
  "status" varchar not null default('pending'),
  "input_data" text,
  "output_data" text,
  "error_message" text,
  "started_at" datetime,
  "completed_at" datetime,
  "created_at" datetime,
  "updated_at" datetime,
  foreign key("tenant_id") references tenants("id") on delete no action on update no action,
  foreign key("user_id") references "users"("id") on delete set null,
  primary key("id")
);
CREATE INDEX "operations_status_index" on "operations"("status");
CREATE INDEX "operations_target_type_target_id_index" on "operations"(
  "target_type",
  "target_id"
);
CREATE INDEX "operations_tenant_id_index" on "operations"("tenant_id");
CREATE TABLE IF NOT EXISTS "audit_logs"(
  "id" varchar not null,
  "organization_id" varchar,
  "user_id" varchar,
  "action" varchar not null,
  "resource_type" varchar,
  "resource_id" varchar,
  "ip_address" varchar,
  "user_agent" text,
  "metadata" text,
  "created_at" datetime,
  "updated_at" datetime,
  "hash" varchar,
  "severity" varchar check("severity" in('low', 'medium', 'high', 'critical')) not null default 'medium',
  foreign key("organization_id") references organizations("id") on delete no action on update no action,
  foreign key("user_id") references "users"("id") on delete set null,
  primary key("id")
);
CREATE INDEX "audit_logs_action_index" on "audit_logs"("action");
CREATE INDEX "audit_logs_organization_id_created_at_index" on "audit_logs"(
  "organization_id",
  "created_at"
);
CREATE INDEX "idx_sites_tenant_status" on "sites"("tenant_id", "status");
CREATE INDEX "idx_sites_tenant_created" on "sites"("tenant_id", "created_at");
CREATE INDEX "idx_sites_vps_status" on "sites"("vps_id", "status");
CREATE INDEX "idx_operations_tenant_status" on "operations"(
  "tenant_id",
  "status"
);
CREATE INDEX "idx_operations_tenant_created" on "operations"(
  "tenant_id",
  "created_at"
);
CREATE INDEX "idx_operations_user_status" on "operations"("user_id", "status");
CREATE INDEX "idx_usage_tenant_metric_period" on "usage_records"(
  "tenant_id",
  "metric_type",
  "period_start",
  "period_end"
);
CREATE INDEX "idx_audit_org_created" on "audit_logs"(
  "organization_id",
  "created_at"
);
CREATE INDEX "idx_audit_user_action" on "audit_logs"("user_id", "action");
CREATE INDEX "idx_audit_resource_lookup" on "audit_logs"(
  "resource_type",
  "resource_id"
);
CREATE INDEX "idx_vps_alloc_vps_tenant" on "vps_allocations"(
  "vps_id",
  "tenant_id"
);
CREATE INDEX "idx_backups_site_created" on "site_backups"(
  "site_id",
  "created_at"
);
CREATE INDEX "idx_backups_expires_type" on "site_backups"(
  "expires_at",
  "backup_type"
);
CREATE INDEX "idx_subscriptions_org_status" on "subscriptions"(
  "organization_id",
  "status"
);
CREATE INDEX "idx_subscriptions_period" on "subscriptions"(
  "current_period_end"
);
CREATE INDEX "idx_invoices_org_status" on "invoices"(
  "organization_id",
  "status"
);
CREATE INDEX "idx_invoices_org_period" on "invoices"(
  "organization_id",
  "period_start",
  "period_end"
);
CREATE INDEX "idx_vps_status_type_health" on "vps_servers"(
  "status",
  "allocation_type",
  "health_status"
);
CREATE INDEX "idx_vps_provider_region" on "vps_servers"("provider", "region");
CREATE INDEX "idx_users_org_role" on "users"("organization_id", "role");
CREATE INDEX "idx_tenants_cached_at" on "tenants"("cached_at");
CREATE INDEX "idx_key_rotation" on "vps_servers"("key_rotated_at");
CREATE INDEX "idx_audit_hash" on "audit_logs"("hash");
CREATE INDEX "idx_audit_severity" on "audit_logs"("severity");
CREATE INDEX "users_two_factor_enabled_index" on "users"("two_factor_enabled");
CREATE INDEX "users_ssh_key_rotated_at_index" on "users"("ssh_key_rotated_at");
CREATE TABLE IF NOT EXISTS "personal_access_tokens"(
  "id" integer primary key autoincrement not null,
  "tokenable_type" varchar not null,
  "tokenable_id" integer not null,
  "name" text not null,
  "token" varchar not null,
  "abilities" text,
  "last_used_at" datetime,
  "expires_at" datetime,
  "created_at" datetime,
  "updated_at" datetime
);
CREATE INDEX "personal_access_tokens_tokenable_type_tokenable_id_index" on "personal_access_tokens"(
  "tokenable_type",
  "tokenable_id"
);
CREATE UNIQUE INDEX "personal_access_tokens_token_unique" on "personal_access_tokens"(
  "token"
);
CREATE INDEX "personal_access_tokens_expires_at_index" on "personal_access_tokens"(
  "expires_at"
);
CREATE UNIQUE INDEX "vps_servers_ip_address_unique" on "vps_servers"(
  "ip_address"
);

INSERT INTO migrations VALUES(1,'0001_01_01_000000_create_users_table',1);
INSERT INTO migrations VALUES(2,'0001_01_01_000001_create_cache_table',1);
INSERT INTO migrations VALUES(3,'0001_01_01_000002_create_jobs_table',1);
INSERT INTO migrations VALUES(4,'2024_01_01_000001_create_organizations_table',1);
INSERT INTO migrations VALUES(5,'2024_01_01_000002_create_tenants_table',1);
INSERT INTO migrations VALUES(6,'2024_01_01_000003_add_default_tenant_foreign_key',1);
INSERT INTO migrations VALUES(7,'2024_01_01_000003_modify_users_table',1);
INSERT INTO migrations VALUES(8,'2024_01_01_000004_create_vps_servers_table',1);
INSERT INTO migrations VALUES(9,'2024_01_01_000005_create_vps_allocations_table',1);
INSERT INTO migrations VALUES(10,'2024_01_01_000006_create_sites_table',1);
INSERT INTO migrations VALUES(11,'2024_01_01_000007_create_site_backups_table',1);
INSERT INTO migrations VALUES(12,'2024_01_01_000008_create_subscriptions_table',1);
INSERT INTO migrations VALUES(13,'2024_01_01_000009_create_usage_records_table',1);
INSERT INTO migrations VALUES(14,'2024_01_01_000010_create_invoices_table',1);
INSERT INTO migrations VALUES(15,'2024_01_01_000011_create_operations_table',1);
INSERT INTO migrations VALUES(16,'2024_01_01_000012_create_audit_logs_table',1);
INSERT INTO migrations VALUES(17,'2024_01_01_000013_create_tier_limits_table',1);
INSERT INTO migrations VALUES(18,'2024_01_01_000014_fix_foreign_key_constraints',1);
INSERT INTO migrations VALUES(19,'2025_01_01_000000_add_critical_performance_indexes',1);
INSERT INTO migrations VALUES(20,'2025_01_01_000001_add_cached_aggregates_to_tenants',1);
INSERT INTO migrations VALUES(21,'2025_01_01_000002_encrypt_ssh_keys_in_vps_servers',1);
INSERT INTO migrations VALUES(22,'2025_01_01_000003_add_key_rotation_to_vps_servers_table',1);
INSERT INTO migrations VALUES(23,'2025_01_01_000004_add_audit_log_hash_chain',1);
INSERT INTO migrations VALUES(24,'2025_01_01_000005_add_security_fields_to_users_table',1);
INSERT INTO migrations VALUES(25,'2026_01_01_110421_create_personal_access_tokens_table',1);
INSERT INTO migrations VALUES(26,'2026_01_02_000001_add_canceled_at_to_subscriptions_table',1);
INSERT INTO migrations VALUES(27,'2026_01_02_000002_add_unique_constraint_to_vps_ip_address',1);
