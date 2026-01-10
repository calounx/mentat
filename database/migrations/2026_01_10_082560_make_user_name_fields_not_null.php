<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * This migration makes username, first_name, and last_name NOT NULL
     * after they have been populated by the previous migration.
     */
    public function up(): void
    {
        // Change columns to NOT NULL using Schema builder (handles SQLite vs PostgreSQL)
        Schema::table('users', function (Blueprint $table) {
            $table->string('username')->nullable(false)->change();
            $table->string('first_name')->nullable(false)->change();
            $table->string('last_name')->nullable(false)->change();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Revert columns to nullable
        Schema::table('users', function (Blueprint $table) {
            $table->string('username')->nullable()->change();
            $table->string('first_name')->nullable()->change();
            $table->string('last_name')->nullable()->change();
        });
    }
};
