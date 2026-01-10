<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        // Migrate existing user names
        $users = DB::table('users')->get();

        foreach ($users as $user) {
            // Split name into first and last
            $nameParts = explode(' ', trim($user->name), 2);
            $firstName = $nameParts[0] ?? 'User';
            $lastName = $nameParts[1] ?? $nameParts[0];

            // Generate username: sanitize(firstName.lastName) + random4
            $baseUsername = Str::slug($firstName . $lastName, '');
            $username = strtolower($baseUsername);

            // Ensure username is unique
            $counter = 1;
            while (DB::table('users')->where('username', $username)->exists()) {
                $username = strtolower($baseUsername) . rand(1000, 9999);
                $counter++;
                if ($counter > 10) {
                    // Fallback to completely random
                    $username = 'user' . Str::random(8);
                    break;
                }
            }

            // Update user with split name and approval info
            DB::table('users')
                ->where('id', $user->id)
                ->update([
                    'username' => $username,
                    'first_name' => $firstName,
                    'last_name' => $lastName,
                    'approval_status' => 'approved', // Grandfather existing users
                    'approved_at' => $user->created_at,
                    'approved_by' => null, // System approval
                ]);
        }
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        // Restore name field from first_name and last_name
        $users = DB::table('users')->get();

        foreach ($users as $user) {
            DB::table('users')
                ->where('id', $user->id)
                ->update([
                    'name' => trim("{$user->first_name} {$user->last_name}"),
                ]);
        }
    }
};
