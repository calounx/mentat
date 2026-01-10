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
        // Change columns to NOT NULL using raw SQL
        // (Laravel doesn't support changing nullable to not null via Blueprint)
        DB::statement('ALTER TABLE users ALTER COLUMN username SET NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN first_name SET NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN last_name SET NOT NULL');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Revert columns to nullable
        DB::statement('ALTER TABLE users ALTER COLUMN username DROP NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN first_name DROP NOT NULL');
        DB::statement('ALTER TABLE users ALTER COLUMN last_name DROP NOT NULL');
    }
};
