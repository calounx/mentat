<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('tenant_user', function (Blueprint $table) {
            $table->id();
            $table->foreignUuid('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignUuid('user_id')->constrained()->cascadeOnDelete();
            $table->string('role')->nullable(); // Future: per-tenant role override
            $table->timestamp('created_at')->nullable();

            $table->unique(['tenant_id', 'user_id']);
            $table->index('tenant_id');
            $table->index('user_id');
        });

        // Seed existing users to their organization's default tenant
        DB::table('users')
            ->whereNotNull('organization_id')
            ->get()
            ->each(function ($user) {
                $defaultTenant = DB::table('tenants')
                    ->where('organization_id', $user->organization_id)
                    ->where('slug', 'default')
                    ->first();

                if ($defaultTenant) {
                    DB::table('tenant_user')->insert([
                        'tenant_id' => $defaultTenant->id,
                        'user_id' => $user->id,
                        'created_at' => now(),
                    ]);
                }
            });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('tenant_user');
    }
};
