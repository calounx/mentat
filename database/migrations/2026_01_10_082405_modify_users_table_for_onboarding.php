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
        Schema::table('users', function (Blueprint $table) {
            // Add new name fields (nullable initially, will be populated by next migration)
            $table->string('username', 50)->nullable()->unique()->after('id');
            $table->string('first_name', 100)->nullable()->after('username');
            $table->string('last_name', 100)->nullable()->after('first_name');

            // Add approval workflow fields
            $table->enum('approval_status', ['pending', 'approved', 'rejected'])
                  ->default('pending')
                  ->after('role');
            $table->timestamp('approved_at')->nullable()->after('approval_status');
            $table->uuid('approved_by')->nullable()->after('approved_at');
            $table->timestamp('rejected_at')->nullable()->after('approved_by');
            $table->uuid('rejected_by')->nullable()->after('rejected_at');
            $table->text('rejection_reason')->nullable()->after('rejected_by');

            // Add foreign key constraints
            $table->foreign('approved_by')->references('id')->on('users')->nullOnDelete();
            $table->foreign('rejected_by')->references('id')->on('users')->nullOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            // Drop foreign keys first
            $table->dropForeign(['approved_by']);
            $table->dropForeign(['rejected_by']);

            // Drop columns
            $table->dropColumn([
                'username',
                'first_name',
                'last_name',
                'approval_status',
                'approved_at',
                'approved_by',
                'rejected_at',
                'rejected_by',
                'rejection_reason',
            ]);
        });
    }
};
