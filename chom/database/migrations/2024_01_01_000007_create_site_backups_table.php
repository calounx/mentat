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
            $table->foreignUuid('site_id')->constrained('sites')->cascadeOnDelete();
            $table->string('filename')->nullable();
            $table->enum('backup_type', ['full', 'files', 'database', 'config', 'manual', 'scheduled'])->default('full');
            $table->enum('status', ['pending', 'in_progress', 'completed', 'failed'])->default('pending');
            $table->string('storage_path', 500)->nullable();
            $table->bigInteger('size_bytes')->nullable();
            $table->integer('size_mb')->nullable();
            $table->string('checksum', 64)->nullable();
            $table->integer('retention_days')->default(30);
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->text('error_message')->nullable();
            $table->timestamps();

            $table->index('site_id');
            $table->index('status');
            $table->index('expires_at');
            $table->index('created_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('site_backups');
    }
};
