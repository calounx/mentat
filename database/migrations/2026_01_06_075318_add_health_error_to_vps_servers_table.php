<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->text('health_error')->nullable()->after('health_status');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('vps_servers', function (Blueprint $table) {
            $table->dropColumn('health_error');
        });
    }
};
