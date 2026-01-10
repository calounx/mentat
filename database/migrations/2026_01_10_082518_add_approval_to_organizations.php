<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::table('organizations', function (Blueprint $table) {
            // Add fictive organization flag
            $table->boolean('is_fictive')->default(false)->after('status');

            // Add approval workflow fields
            $table->boolean('is_approved')->default(false)->after('is_fictive');
            $table->timestamp('approved_at')->nullable()->after('is_approved');
            $table->uuid('approved_by')->nullable()->after('approved_at');
            $table->text('approval_notes')->nullable()->after('approved_by');
            $table->uuid('rejected_by')->nullable()->after('approval_notes');
            $table->text('rejection_reason')->nullable()->after('rejected_by');

            // Add foreign key constraints
            $table->foreign('approved_by')->references('id')->on('users')->nullOnDelete();
            $table->foreign('rejected_by')->references('id')->on('users')->nullOnDelete();
        });

        // Grandfather existing organizations as approved
        DB::table('organizations')->update([
            'is_approved' => true,
            'approved_at' => DB::raw('created_at'),
        ]);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::table('organizations', function (Blueprint $table) {
            // Drop foreign keys first
            $table->dropForeign(['approved_by']);
            $table->dropForeign(['rejected_by']);

            // Drop columns
            $table->dropColumn([
                'is_fictive',
                'is_approved',
                'approved_at',
                'approved_by',
                'approval_notes',
                'rejected_by',
                'rejection_reason',
            ]);
        });
    }
};
