<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('site_backups', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('site_id')->constrained()->cascadeOnDelete();
            $table->enum('backup_type', ['full', 'files', 'database', 'config'])->default('full');
            $table->string('storage_path', 500);
            $table->bigInteger('size_bytes');
            $table->string('checksum', 64)->nullable();
            $table->integer('retention_days')->default(30);
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->index('site_id');
            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('site_backups');
    }
};
