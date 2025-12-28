<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // SQLite doesn't support modifying primary keys, so we need to recreate the table
        if (DB::getDriverName() === 'sqlite') {
            // For SQLite: Drop and recreate users table with UUID
            Schema::dropIfExists('password_reset_tokens');
            Schema::dropIfExists('sessions');
            Schema::dropIfExists('users');

            Schema::create('users', function (Blueprint $table) {
                $table->uuid('id')->primary();
                $table->foreignUuid('organization_id')->nullable()->constrained()->cascadeOnDelete();
                $table->string('name');
                $table->string('email')->unique();
                $table->timestamp('email_verified_at')->nullable();
                $table->string('password');
                $table->enum('role', ['owner', 'admin', 'member', 'viewer'])->default('member');
                $table->rememberToken();
                $table->boolean('two_factor_enabled')->default(false);
                $table->text('two_factor_secret')->nullable();
                $table->timestamps();

                $table->index('organization_id');
            });

            // Recreate password_reset_tokens
            Schema::create('password_reset_tokens', function (Blueprint $table) {
                $table->string('email')->primary();
                $table->string('token');
                $table->timestamp('created_at')->nullable();
            });

            // Recreate sessions
            Schema::create('sessions', function (Blueprint $table) {
                $table->string('id')->primary();
                $table->foreignUuid('user_id')->nullable()->index();
                $table->string('ip_address', 45)->nullable();
                $table->text('user_agent')->nullable();
                $table->longText('payload');
                $table->integer('last_activity')->index();
            });
        } else {
            // For MySQL/PostgreSQL: Modify the existing table
            Schema::table('users', function (Blueprint $table) {
                $table->dropColumn('id');
            });

            Schema::table('users', function (Blueprint $table) {
                $table->uuid('id')->primary()->first();
                $table->foreignUuid('organization_id')->nullable()->after('id')->constrained()->cascadeOnDelete();
                $table->enum('role', ['owner', 'admin', 'member', 'viewer'])->default('member')->after('email');
                $table->boolean('two_factor_enabled')->default(false)->after('remember_token');
                $table->text('two_factor_secret')->nullable()->after('two_factor_enabled');

                $table->index('organization_id');
            });
        }
    }

    public function down(): void
    {
        if (DB::getDriverName() === 'sqlite') {
            // For SQLite: recreate original structure
            Schema::dropIfExists('sessions');
            Schema::dropIfExists('password_reset_tokens');
            Schema::dropIfExists('users');

            Schema::create('users', function (Blueprint $table) {
                $table->id();
                $table->string('name');
                $table->string('email')->unique();
                $table->timestamp('email_verified_at')->nullable();
                $table->string('password');
                $table->rememberToken();
                $table->timestamps();
            });

            Schema::create('password_reset_tokens', function (Blueprint $table) {
                $table->string('email')->primary();
                $table->string('token');
                $table->timestamp('created_at')->nullable();
            });

            Schema::create('sessions', function (Blueprint $table) {
                $table->string('id')->primary();
                $table->foreignId('user_id')->nullable()->index();
                $table->string('ip_address', 45)->nullable();
                $table->text('user_agent')->nullable();
                $table->longText('payload');
                $table->integer('last_activity')->index();
            });
        } else {
            Schema::table('users', function (Blueprint $table) {
                $table->dropColumn(['organization_id', 'role', 'two_factor_enabled', 'two_factor_secret']);
            });
        }
    }
};
