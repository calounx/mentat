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
        // Create rejected_emails table for spam tracking
        Schema::create('rejected_emails', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('email', 255);
            $table->uuid('user_id')->nullable();
            $table->text('rejection_reason')->nullable();
            $table->timestamp('rejected_at')->useCurrent();
            $table->uuid('rejected_by')->nullable();
            $table->integer('attempts')->default(1);

            // Indexes
            $table->index('email');

            // Foreign keys
            $table->foreign('user_id')->references('id')->on('users')->nullOnDelete();
            $table->foreign('rejected_by')->references('id')->on('users')->nullOnDelete();
        });

        // Create plan_change_requests table
        Schema::create('plan_change_requests', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->uuid('tenant_id');
            $table->uuid('user_id');
            $table->enum('current_tier', ['starter', 'pro', 'enterprise']);
            $table->enum('requested_tier', ['starter', 'pro', 'enterprise']);
            $table->text('reason')->nullable();
            $table->enum('status', ['pending', 'approved', 'rejected'])->default('pending');
            $table->timestamp('requested_at')->useCurrent();
            $table->timestamp('reviewed_at')->nullable();
            $table->uuid('reviewed_by')->nullable();
            $table->text('reviewer_notes')->nullable();

            // Indexes
            $table->index(['tenant_id', 'status']);
            $table->index('status');

            // Foreign keys
            $table->foreign('tenant_id')->references('id')->on('tenants')->cascadeOnDelete();
            $table->foreign('user_id')->references('id')->on('users')->cascadeOnDelete();
            $table->foreign('reviewed_by')->references('id')->on('users')->nullOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('plan_change_requests');
        Schema::dropIfExists('rejected_emails');
    }
};
