<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * This migration adds a unique constraint to the vps_servers.ip_address column
     * to prevent duplicate IP addresses from being assigned to multiple VPS servers,
     * ensuring data integrity and preventing network conflicts.
     */
    public function up(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->unique('ip_address', 'vps_servers_ip_address_unique');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropUnique('vps_servers_ip_address_unique');
        });
    }
};
