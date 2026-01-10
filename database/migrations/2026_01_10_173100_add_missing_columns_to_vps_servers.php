<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->string('ssh_user')->default('root')->after('ssh_key_id');
            $table->integer('ssh_port')->default(22)->after('ssh_user');
            // Note: health_error column already added by 2026_01_06_075318 migration
        });
    }

    public function down(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropColumn(['ssh_user', 'ssh_port']);
            // Note: health_error removed by 2026_01_06_075318 migration rollback
        });
    }
};
