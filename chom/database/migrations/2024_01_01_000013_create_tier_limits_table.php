<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tier_limits', function (Blueprint $table) {
            $table->string('tier', 50)->primary();
            $table->string('name');
            $table->integer('max_sites'); // -1 for unlimited
            $table->integer('max_storage_gb'); // -1 for unlimited
            $table->integer('max_bandwidth_gb'); // -1 for unlimited
            $table->integer('backup_retention_days');
            $table->string('support_level', 50);
            $table->boolean('dedicated_ip')->default(false);
            $table->boolean('staging_environments')->default(false);
            $table->boolean('white_label')->default(false);
            $table->integer('api_rate_limit_per_hour'); // -1 for unlimited
            $table->integer('price_monthly_cents');
            $table->timestamps();
        });

        // Insert default tier limits
        DB::table('tier_limits')->insert([
            [
                'tier' => 'starter',
                'name' => 'Starter',
                'max_sites' => 5,
                'max_storage_gb' => 10,
                'max_bandwidth_gb' => 100,
                'backup_retention_days' => 7,
                'support_level' => 'community',
                'dedicated_ip' => false,
                'staging_environments' => false,
                'white_label' => false,
                'api_rate_limit_per_hour' => 1000,
                'price_monthly_cents' => 2900,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'tier' => 'pro',
                'name' => 'Pro',
                'max_sites' => 25,
                'max_storage_gb' => 100,
                'max_bandwidth_gb' => 500,
                'backup_retention_days' => 30,
                'support_level' => 'priority',
                'dedicated_ip' => false,
                'staging_environments' => true,
                'white_label' => false,
                'api_rate_limit_per_hour' => 5000,
                'price_monthly_cents' => 7900,
                'created_at' => now(),
                'updated_at' => now(),
            ],
            [
                'tier' => 'enterprise',
                'name' => 'Enterprise',
                'max_sites' => -1,
                'max_storage_gb' => -1,
                'max_bandwidth_gb' => -1,
                'backup_retention_days' => 90,
                'support_level' => 'dedicated',
                'dedicated_ip' => true,
                'staging_environments' => true,
                'white_label' => true,
                'api_rate_limit_per_hour' => -1,
                'price_monthly_cents' => 24900,
                'created_at' => now(),
                'updated_at' => now(),
            ],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('tier_limits');
    }
};
