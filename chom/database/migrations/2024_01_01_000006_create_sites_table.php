<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sites', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('vps_id')->constrained('vps_servers');
            $table->string('domain', 253);
            $table->enum('site_type', ['wordpress', 'html', 'laravel'])->default('wordpress');
            $table->string('php_version', 10)->default('8.2');
            $table->boolean('ssl_enabled')->default(false);
            $table->timestamp('ssl_expires_at')->nullable();
            $table->enum('status', ['creating', 'active', 'disabled', 'failed', 'deleting'])->default('creating');
            $table->string('document_root', 500)->nullable();
            $table->string('db_name', 64)->nullable();
            $table->string('db_user', 32)->nullable();
            $table->bigInteger('storage_used_mb')->default(0);
            $table->json('settings')->nullable();
            $table->timestamps();
            $table->softDeletes();

            $table->unique(['tenant_id', 'domain']);
            $table->index('vps_id');
            $table->index('status');
            $table->index('domain');
            $table->index(['tenant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sites');
    }
};
