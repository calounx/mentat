<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vps_servers', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('hostname')->unique();
            $table->string('ip_address', 45); // IPv4 or IPv6
            $table->string('provider', 50); // hetzner, digitalocean, vultr, custom
            $table->string('provider_id')->nullable();
            $table->string('region', 50)->nullable();
            $table->integer('spec_cpu');
            $table->integer('spec_memory_mb');
            $table->integer('spec_disk_gb');
            $table->enum('status', ['provisioning', 'active', 'maintenance', 'failed', 'decommissioned'])->default('provisioning');
            $table->enum('allocation_type', ['shared', 'dedicated'])->default('shared');
            $table->string('vpsmanager_version', 20)->nullable();
            $table->boolean('observability_configured')->default(false);
            $table->uuid('ssh_key_id')->nullable();
            $table->timestamp('last_health_check_at')->nullable();
            $table->enum('health_status', ['healthy', 'degraded', 'unhealthy', 'unknown'])->default('unknown');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vps_servers');
    }
};
