<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            // Add plan selection flag
            $table->boolean('requires_plan_selection')->default(true)->after('is_approved');

            // Add plan selected timestamp
            $table->timestamp('plan_selected_at')->nullable()->after('tier');

            // Make tier nullable (Laravel handles SQLite vs PostgreSQL differences)
            $table->string('tier')->nullable()->change();
        });

        // Grandfather existing tenants: they already have plans selected
        DB::table('tenants')->update([
            'requires_plan_selection' => false,
            'plan_selected_at' => DB::raw('created_at'),
        ]);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('tenants', function (Blueprint $table) {
            // Restore tier as NOT NULL with default (Laravel handles SQLite vs PostgreSQL differences)
            $table->string('tier')->default('starter')->nullable(false)->change();

            // Drop plan selection columns
            $table->dropColumn(['requires_plan_selection', 'plan_selected_at']);
        });
    }
};
