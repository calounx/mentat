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
        Schema::create('system_settings', function (Blueprint $table) {
            $table->id();
            $table->string('key')->unique();
            $table->text('value')->nullable();
            $table->string('type')->default('string'); // string, integer, boolean, encrypted
            $table->text('description')->nullable();
            $table->timestamps();
        });

        // Seed default SMTP settings
        DB::table('system_settings')->insert([
            ['key' => 'mail.mailer', 'value' => 'smtp', 'type' => 'string', 'description' => 'Mail driver (smtp, sendmail, log)', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.host', 'value' => '127.0.0.1', 'type' => 'string', 'description' => 'SMTP host address', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.port', 'value' => '587', 'type' => 'integer', 'description' => 'SMTP port', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.username', 'value' => '', 'type' => 'string', 'description' => 'SMTP username', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.password', 'value' => '', 'type' => 'encrypted', 'description' => 'SMTP password (encrypted)', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.encryption', 'value' => 'tls', 'type' => 'string', 'description' => 'SMTP encryption (tls, ssl, null)', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.from_address', 'value' => 'noreply@example.com', 'type' => 'string', 'description' => 'From email address', 'created_at' => now(), 'updated_at' => now()],
            ['key' => 'mail.from_name', 'value' => 'CHOM', 'type' => 'string', 'description' => 'From name', 'created_at' => now(), 'updated_at' => now()],
        ]);
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('system_settings');
    }
};
