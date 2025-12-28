<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // 1. Fix sites.vps_id constraint - allow null on delete since sites can exist without VPS temporarily
        Schema::table('sites', function (Blueprint $table) {
            $table->dropForeign(['vps_id']);
        });

        Schema::table('sites', function (Blueprint $table) {
            $table->foreignUuid('vps_id')
                ->nullable()
                ->change();
        });

        Schema::table('sites', function (Blueprint $table) {
            $table->foreign('vps_id')
                ->references('id')
                ->on('vps_servers')
                ->nullOnDelete();
        });

        // 2. Fix invoices.organization_id constraint - restrict delete to prevent deleting orgs with invoices
        Schema::table('invoices', function (Blueprint $table) {
            $table->dropForeign(['organization_id']);
        });

        Schema::table('invoices', function (Blueprint $table) {
            $table->foreign('organization_id')
                ->references('id')
                ->on('organizations')
                ->restrictOnDelete();
        });

        // 3. Add TierLimit foreign key enforcement - link tenants.tier to tier_limits.tier
        Schema::table('tenants', function (Blueprint $table) {
            $table->foreign('tier')
                ->references('tier')
                ->on('tier_limits')
                ->restrictOnDelete()
                ->cascadeOnUpdate();
        });

        // 4. Fix operations.user_id nullable FK - add proper nullOnDelete
        Schema::table('operations', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
        });

        Schema::table('operations', function (Blueprint $table) {
            $table->foreign('user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });

        // 5. Fix audit_logs.user_id nullable FK - add proper nullOnDelete
        Schema::table('audit_logs', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
        });

        Schema::table('audit_logs', function (Blueprint $table) {
            $table->foreign('user_id')
                ->references('id')
                ->on('users')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        // Restore audit_logs.user_id constraint
        Schema::table('audit_logs', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
        });

        Schema::table('audit_logs', function (Blueprint $table) {
            $table->foreign('user_id')
                ->references('id')
                ->on('users');
        });

        // Restore operations.user_id constraint
        Schema::table('operations', function (Blueprint $table) {
            $table->dropForeign(['user_id']);
        });

        Schema::table('operations', function (Blueprint $table) {
            $table->foreign('user_id')
                ->references('id')
                ->on('users');
        });

        // Remove tenants.tier foreign key
        Schema::table('tenants', function (Blueprint $table) {
            $table->dropForeign(['tier']);
        });

        // Restore invoices.organization_id constraint (no explicit delete behavior)
        Schema::table('invoices', function (Blueprint $table) {
            $table->dropForeign(['organization_id']);
        });

        Schema::table('invoices', function (Blueprint $table) {
            $table->foreign('organization_id')
                ->references('id')
                ->on('organizations');
        });

        // Restore sites.vps_id constraint (required, no null on delete)
        Schema::table('sites', function (Blueprint $table) {
            $table->dropForeign(['vps_id']);
        });

        Schema::table('sites', function (Blueprint $table) {
            $table->foreignUuid('vps_id')
                ->nullable(false)
                ->change();
        });

        Schema::table('sites', function (Blueprint $table) {
            $table->foreign('vps_id')
                ->references('id')
                ->on('vps_servers');
        });
    }
};
