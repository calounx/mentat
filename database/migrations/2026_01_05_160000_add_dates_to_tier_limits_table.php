<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tier_limits', function (Blueprint $table) {
            $table->date('start_date')->nullable()->after('price_monthly_cents');
            $table->date('end_date')->nullable()->after('start_date');
            $table->boolean('is_active')->default(true)->after('end_date');
            $table->text('description')->nullable()->after('name');
        });
    }

    public function down(): void
    {
        Schema::table('tier_limits', function (Blueprint $table) {
            $table->dropColumn(['start_date', 'end_date', 'is_active', 'description']);
        });
    }
};
