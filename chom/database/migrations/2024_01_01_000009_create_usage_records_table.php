<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('usage_records', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('metric_type', 50); // sites, storage_gb, bandwidth_gb, backups
            $table->decimal('quantity', 10, 2);
            $table->decimal('unit_price', 10, 4)->nullable();
            $table->date('period_start');
            $table->date('period_end');
            $table->string('stripe_usage_record_id')->nullable();
            $table->timestamps();

            $table->index(['tenant_id', 'period_start', 'period_end']);
            $table->index('metric_type');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('usage_records');
    }
};
