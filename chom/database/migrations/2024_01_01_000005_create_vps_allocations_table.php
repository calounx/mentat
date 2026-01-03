<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('vps_allocations', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('vps_id')->constrained('vps_servers')->cascadeOnDelete();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->integer('sites_allocated')->default(0);
            $table->integer('storage_mb_allocated')->default(0);
            $table->integer('memory_mb_allocated')->default(0);
            $table->timestamps();

            $table->unique(['vps_id', 'tenant_id']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('vps_allocations');
    }
};
