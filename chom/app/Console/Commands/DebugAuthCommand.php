<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

class DebugAuthCommand extends Command
{
    protected $signature = 'debug:auth {email : User email to debug}';

    protected $description = 'Debug authentication issues for a user';

    public function handle(): int
    {
        $email = $this->argument('email');

        $this->components->info("Debugging authentication for: {$email}");
        $this->newLine();

        // Find user
        $user = User::where('email', $email)->first();

        if (! $user) {
            $this->components->error("User not found: {$email}");

            return self::FAILURE;
        }

        // Display user information
        $this->components->info('User Information:');
        $this->table(
            ['Property', 'Value'],
            [
                ['ID', $user->id],
                ['Name', $user->name],
                ['Email', $user->email],
                ['Role', $user->role],
                ['Email Verified', $user->email_verified_at ? 'Yes' : 'No'],
                ['Created At', $user->created_at],
                ['Organization ID', $user->organization_id ?? 'None'],
            ]
        );

        // Check organization
        if ($user->organization_id) {
            $org = $user->organization;
            $this->newLine();
            $this->components->info('Organization:');
            $this->table(
                ['Property', 'Value'],
                [
                    ['ID', $org->id],
                    ['Name', $org->name],
                    ['Slug', $org->slug],
                    ['Status', $org->status],
                ]
            );
        } else {
            $this->newLine();
            $this->components->warn('User has no organization assigned!');
        }

        // Check 2FA status
        $this->newLine();
        $this->components->info('Two-Factor Authentication:');
        $this->table(
            ['Property', 'Value'],
            [
                ['Enabled', $user->two_factor_enabled ? 'Yes' : 'No'],
                ['Required', $user->requires2FA() ? 'Yes' : 'No'],
                ['In Grace Period', $user->isIn2FAGracePeriod() ? 'Yes' : 'No'],
                ['Confirmed At', $user->two_factor_confirmed_at ?? 'Never'],
            ]
        );

        // Check password
        $this->newLine();
        if ($this->confirm('Would you like to test password authentication?')) {
            $password = $this->secret('Enter password to test');

            if (Hash::check($password, $user->password)) {
                $this->components->info('Password is correct!');
            } else {
                $this->components->error('Password is incorrect!');
            }
        }

        // Check active tokens
        $this->newLine();
        $tokens = $user->tokens()->where('expires_at', '>', now())->orWhereNull('expires_at')->get();
        $this->components->info("Active API Tokens: {$tokens->count()}");

        if ($tokens->count() > 0) {
            $this->table(
                ['ID', 'Name', 'Abilities', 'Last Used', 'Expires At'],
                $tokens->map(fn ($token) => [
                    substr($token->id, 0, 8).'...',
                    $token->name,
                    implode(', ', $token->abilities),
                    $token->last_used_at ?? 'Never',
                    $token->expires_at ?? 'Never',
                ])
            );
        }

        // Recommendations
        $this->newLine();
        $this->components->info('Recommendations:');

        $issues = [];

        if (! $user->email_verified_at) {
            $issues[] = 'Email not verified - user may not be able to reset password';
        }

        if (! $user->organization_id) {
            $issues[] = 'No organization assigned - user may not have access to resources';
        }

        if ($user->requires2FA() && ! $user->two_factor_enabled && ! $user->isIn2FAGracePeriod()) {
            $issues[] = '2FA is required but not enabled - user may be blocked from sensitive operations';
        }

        if (count($issues) > 0) {
            foreach ($issues as $issue) {
                $this->components->warn("- {$issue}");
            }
        } else {
            $this->components->info('No issues found!');
        }

        return self::SUCCESS;
    }
}
