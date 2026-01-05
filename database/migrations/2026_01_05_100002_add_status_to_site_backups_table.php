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
        Schema::table('site_backups', function (Blueprint $table) {
            $table->string('status')->default('completed')->after('retention_days');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('site_backups', function (Blueprint $table) {
            $table->dropColumn('status');
        });
    }
};
