<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('sites', function (Blueprint $table) {
            $table->text('failure_reason')->nullable()->after('status');
            $table->json('healing_attempts')->nullable()->after('failure_reason');
            $table->timestamp('last_healing_at')->nullable()->after('healing_attempts');
            $table->unsignedTinyInteger('provision_attempts')->default(0)->after('last_healing_at');
        });
    }

    public function down(): void
    {
        Schema::table('sites', function (Blueprint $table) {
            $table->dropColumn(['failure_reason', 'healing_attempts', 'last_healing_at', 'provision_attempts']);
        });
    }
};
