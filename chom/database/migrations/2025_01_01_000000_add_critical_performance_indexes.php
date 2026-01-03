<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Add critical performance indexes identified during architectural review.
 *
 * These composite indexes are designed to optimize frequently-executed queries:
 * - Tenant-scoped queries with status filtering
 * - Time-based ordering and filtering
 * - Resource lookup and allocation queries
 *
 * Performance Impact: Expected 60-90% reduction in query execution time for
 * tenant-scoped operations and time-series queries.
 */
return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Sites table - tenant scoping and VPS allocation queries
        Schema::table('sites', function (Blueprint $table) {
            // Optimize: SELECT * FROM sites WHERE tenant_id = ? AND status = ?
            // Used in: Site listings, tenant quota checks
            $table->index(['tenant_id', 'status'], 'idx_sites_tenant_status');

            // Optimize: SELECT * FROM sites WHERE tenant_id = ? ORDER BY created_at DESC
            // Used in: Site listings with newest-first ordering
            $table->index(['tenant_id', 'created_at'], 'idx_sites_tenant_created');

            // Optimize: SELECT * FROM sites WHERE vps_id = ? AND status = ?
            // Used in: VPS capacity calculations, health checks
            $table->index(['vps_id', 'status'], 'idx_sites_vps_status');
        });

        // Operations table - tenant activity tracking and user operations
        Schema::table('operations', function (Blueprint $table) {
            // Optimize: SELECT * FROM operations WHERE tenant_id = ? AND status = ?
            // Used in: Operation status monitoring, active operations count
            $table->index(['tenant_id', 'status'], 'idx_operations_tenant_status');

            // Optimize: SELECT * FROM operations WHERE tenant_id = ? ORDER BY created_at DESC
            // Used in: Operation history, audit trail
            $table->index(['tenant_id', 'created_at'], 'idx_operations_tenant_created');

            // Optimize: SELECT * FROM operations WHERE user_id = ? AND status = ?
            // Used in: User activity tracking, pending operations
            $table->index(['user_id', 'status'], 'idx_operations_user_status');
        });

        // Usage records - metrics and billing queries
        Schema::table('usage_records', function (Blueprint $table) {
            // Optimize: SELECT * FROM usage_records WHERE tenant_id = ? AND metric_type = ?
            //           AND period_start >= ? AND period_end <= ?
            // Used in: Billing calculations, usage analytics, quota enforcement
            $table->index(
                ['tenant_id', 'metric_type', 'period_start', 'period_end'],
                'idx_usage_tenant_metric_period'
            );
        });

        // Audit logs - compliance and security monitoring
        Schema::table('audit_logs', function (Blueprint $table) {
            // Optimize: SELECT * FROM audit_logs WHERE organization_id = ? ORDER BY created_at DESC
            // Used in: Security dashboards, compliance reports
            $table->index(['organization_id', 'created_at'], 'idx_audit_org_created');

            // Optimize: SELECT * FROM audit_logs WHERE user_id = ? AND action = ?
            // Used in: User activity audits, security investigations
            $table->index(['user_id', 'action'], 'idx_audit_user_action');

            // Optimize: SELECT * FROM audit_logs WHERE resource_type = ? AND resource_id = ?
            // Used in: Resource change history, compliance tracking
            $table->index(['resource_type', 'resource_id'], 'idx_audit_resource_lookup');
        });

        // VPS allocations - resource management queries
        Schema::table('vps_allocations', function (Blueprint $table) {
            // Optimize: SELECT * FROM vps_allocations WHERE vps_id = ? AND tenant_id = ?
            // Used in: Allocation verification, capacity planning
            $table->index(['vps_id', 'tenant_id'], 'idx_vps_alloc_vps_tenant');
        });

        // Site backups - backup management and retention
        Schema::table('site_backups', function (Blueprint $table) {
            // Optimize: SELECT * FROM site_backups WHERE site_id = ? ORDER BY created_at DESC
            // Used in: Backup listings, restore point selection
            $table->index(['site_id', 'created_at'], 'idx_backups_site_created');

            // Optimize: SELECT * FROM site_backups WHERE expires_at < ? AND backup_type = ?
            // Used in: Backup retention cleanup, scheduled deletion
            $table->index(['expires_at', 'backup_type'], 'idx_backups_expires_type');
        });

        // Subscriptions - billing and access control
        Schema::table('subscriptions', function (Blueprint $table) {
            // Optimize: SELECT * FROM subscriptions WHERE organization_id = ? AND status = ?
            // Used in: Access checks, billing status validation
            $table->index(['organization_id', 'status'], 'idx_subscriptions_org_status');

            // Optimize: SELECT * FROM subscriptions WHERE current_period_end < ?
            // Used in: Renewal processing, expiration notifications
            $table->index(['current_period_end'], 'idx_subscriptions_period');
        });

        // Invoices - financial reporting and reconciliation
        Schema::table('invoices', function (Blueprint $table) {
            // Optimize: SELECT * FROM invoices WHERE organization_id = ? AND status = ?
            // Used in: Invoice listings, payment status checks
            $table->index(['organization_id', 'status'], 'idx_invoices_org_status');

            // Optimize: SELECT * FROM invoices WHERE organization_id = ?
            //           AND period_start >= ? AND period_end <= ?
            // Used in: Billing period reports, financial analytics
            $table->index(['organization_id', 'period_start', 'period_end'], 'idx_invoices_org_period');
        });

        // VPS servers - capacity planning and health monitoring
        Schema::table('vps_servers', function (Blueprint $table) {
            // Optimize: SELECT * FROM vps_servers WHERE status = ? AND allocation_type = ?
            //           AND health_status = ?
            // Used in: Available VPS selection, capacity planning
            $table->index(['status', 'allocation_type', 'health_status'], 'idx_vps_status_type_health');

            // Optimize: SELECT * FROM vps_servers WHERE provider = ? AND region = ?
            // Used in: Regional capacity reports, provider analytics
            $table->index(['provider', 'region'], 'idx_vps_provider_region');
        });

        // Users - organization membership and role-based queries
        Schema::table('users', function (Blueprint $table) {
            // Optimize: SELECT * FROM users WHERE organization_id = ? AND role = ?
            // Used in: Team management, permission checks
            $table->index(['organization_id', 'role'], 'idx_users_org_role');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Drop all indexes in reverse order
        Schema::table('users', function (Blueprint $table) {
            $table->dropIndex('idx_users_org_role');
        });

        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropIndex('idx_vps_status_type_health');
            $table->dropIndex('idx_vps_provider_region');
        });

        Schema::table('invoices', function (Blueprint $table) {
            $table->dropIndex('idx_invoices_org_status');
            $table->dropIndex('idx_invoices_org_period');
        });

        Schema::table('subscriptions', function (Blueprint $table) {
            $table->dropIndex('idx_subscriptions_org_status');
            $table->dropIndex('idx_subscriptions_period');
        });

        Schema::table('site_backups', function (Blueprint $table) {
            $table->dropIndex('idx_backups_site_created');
            $table->dropIndex('idx_backups_expires_type');
        });

        Schema::table('vps_allocations', function (Blueprint $table) {
            $table->dropIndex('idx_vps_alloc_vps_tenant');
        });

        Schema::table('audit_logs', function (Blueprint $table) {
            $table->dropIndex('idx_audit_org_created');
            $table->dropIndex('idx_audit_user_action');
            $table->dropIndex('idx_audit_resource_lookup');
        });

        Schema::table('usage_records', function (Blueprint $table) {
            $table->dropIndex('idx_usage_tenant_metric_period');
        });

        Schema::table('operations', function (Blueprint $table) {
            $table->dropIndex('idx_operations_tenant_status');
            $table->dropIndex('idx_operations_tenant_created');
            $table->dropIndex('idx_operations_user_status');
        });

        Schema::table('sites', function (Blueprint $table) {
            $table->dropIndex('idx_sites_tenant_status');
            $table->dropIndex('idx_sites_tenant_created');
            $table->dropIndex('idx_sites_vps_status');
        });
    }
};
