<?php

namespace Tests\Unit\Models;

use App\Models\Organization;
use App\Models\Operation;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;
use PHPUnit\Framework\Attributes\Test;

class UserModelTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_has_correct_fillable_attributes()
    {
        $fillable = [
            'name',
            'email',
            'password',
            'organization_id',
            'role',
            'two_factor_enabled',
            'two_factor_secret',
            'two_factor_backup_codes',
            'two_factor_confirmed_at',
            'password_confirmed_at',
            'ssh_key_rotated_at',
        ];

        $user = new User();
        $this->assertEquals($fillable, $user->getFillable());
    }

    #[Test]
    public function it_hides_sensitive_attributes()
    {
        $user = User::factory()->create([
            'password' => 'secret-password',
            'two_factor_secret' => 'secret-2fa',
        ]);

        $array = $user->toArray();

        $this->assertArrayNotHasKey('password', $array);
        $this->assertArrayNotHasKey('remember_token', $array);
        $this->assertArrayNotHasKey('two_factor_secret', $array);
        $this->assertArrayNotHasKey('two_factor_backup_codes', $array);
    }

    #[Test]
    public function it_casts_attributes_correctly()
    {
        $user = User::factory()->create([
            'email_verified_at' => now(),
            'two_factor_enabled' => true,
            'two_factor_confirmed_at' => now(),
            'password_confirmed_at' => now(),
            'ssh_key_rotated_at' => now(),
        ]);

        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->email_verified_at);
        $this->assertTrue(is_bool($user->two_factor_enabled));
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->two_factor_confirmed_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->password_confirmed_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->ssh_key_rotated_at);
    }

    #[Test]
    public function it_hashes_password_automatically()
    {
        $user = User::factory()->create([
            'password' => 'plain-text-password',
        ]);

        $this->assertNotEquals('plain-text-password', $user->password);
        $this->assertTrue(Hash::check('plain-text-password', $user->password));
    }

    #[Test]
    public function it_encrypts_two_factor_secret()
    {
        $user = User::factory()->create([
            'two_factor_secret' => 'secret-value',
        ]);

        // Reload from database
        $user->refresh();

        // The value should be decrypted automatically
        $this->assertEquals('secret-value', $user->two_factor_secret);

        // Raw database value should be encrypted (different from plain text)
        $rawValue = \DB::table('users')->where('id', $user->id)->value('two_factor_secret');
        $this->assertNotEquals('secret-value', $rawValue);
    }

    #[Test]
    public function it_belongs_to_an_organization()
    {
        $organization = Organization::factory()->create();
        $user = User::factory()->create(['organization_id' => $organization->id]);

        $this->assertInstanceOf(Organization::class, $user->organization);
        $this->assertEquals($organization->id, $user->organization->id);
    }

    #[Test]
    public function it_has_many_operations()
    {
        $user = User::factory()->create();
        Operation::factory()->count(3)->create(['user_id' => $user->id]);

        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Collection::class, $user->operations);
        $this->assertCount(3, $user->operations);
        $this->assertInstanceOf(Operation::class, $user->operations->first());
    }

    #[Test]
    public function it_returns_current_tenant_through_organization()
    {
        $organization = Organization::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $organization->id]);
        $organization->update(['default_tenant_id' => $tenant->id]);

        $user = User::factory()->create(['organization_id' => $organization->id]);

        $currentTenant = $user->currentTenant();

        $this->assertInstanceOf(Tenant::class, $currentTenant);
        $this->assertEquals($tenant->id, $currentTenant->id);
    }

    #[Test]
    public function it_returns_null_for_current_tenant_when_no_organization()
    {
        $user = User::factory()->create(['organization_id' => null]);

        $this->assertNull($user->currentTenant());
    }

    #[Test]
    public function it_checks_if_user_is_owner()
    {
        $owner = User::factory()->create(['role' => 'owner']);
        $admin = User::factory()->create(['role' => 'admin']);

        $this->assertTrue($owner->isOwner());
        $this->assertFalse($admin->isOwner());
    }

    #[Test]
    public function it_checks_if_user_is_admin()
    {
        $owner = User::factory()->create(['role' => 'owner']);
        $admin = User::factory()->create(['role' => 'admin']);
        $member = User::factory()->create(['role' => 'member']);

        $this->assertTrue($owner->isAdmin());
        $this->assertTrue($admin->isAdmin());
        $this->assertFalse($member->isAdmin());
    }

    #[Test]
    public function it_checks_if_user_can_manage_sites()
    {
        $owner = User::factory()->create(['role' => 'owner']);
        $admin = User::factory()->create(['role' => 'admin']);
        $member = User::factory()->create(['role' => 'member']);
        $viewer = User::factory()->create(['role' => 'viewer']);

        $this->assertTrue($owner->canManageSites());
        $this->assertTrue($admin->canManageSites());
        $this->assertTrue($member->canManageSites());
        $this->assertFalse($viewer->canManageSites());
    }

    #[Test]
    public function it_checks_if_user_is_viewer()
    {
        $viewer = User::factory()->create(['role' => 'viewer']);
        $member = User::factory()->create(['role' => 'member']);

        $this->assertTrue($viewer->isViewer());
        $this->assertFalse($member->isViewer());
    }

    #[Test]
    public function it_confirms_password_and_checks_recent_confirmation()
    {
        $user = User::factory()->create(['password_confirmed_at' => null]);

        $this->assertFalse($user->hasRecentPasswordConfirmation());

        $user->confirmPassword();

        $this->assertTrue($user->hasRecentPasswordConfirmation());
    }

    #[Test]
    public function password_confirmation_expires_after_10_minutes()
    {
        $user = User::factory()->create([
            'password_confirmed_at' => now()->subMinutes(11),
        ]);

        $this->assertFalse($user->hasRecentPasswordConfirmation());
    }

    #[Test]
    public function it_checks_if_ssh_keys_need_rotation()
    {
        // User with no rotation history
        $userNeverRotated = User::factory()->create(['ssh_key_rotated_at' => null]);
        $this->assertTrue($userNeverRotated->needsKeyRotation());

        // User rotated recently
        $userRecentRotation = User::factory()->create(['ssh_key_rotated_at' => now()->subDays(30)]);
        $this->assertFalse($userRecentRotation->needsKeyRotation());

        // User rotated more than 90 days ago
        $userOldRotation = User::factory()->create(['ssh_key_rotated_at' => now()->subDays(91)]);
        $this->assertTrue($userOldRotation->needsKeyRotation());
    }

    #[Test]
    public function it_uses_uuid_as_primary_key()
    {
        $user = User::factory()->create();

        $this->assertIsString($user->id);
        $this->assertEquals(36, strlen($user->id)); // UUID length
        $this->assertMatchesRegularExpression(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $user->id
        );
    }

    #[Test]
    public function it_has_timestamps()
    {
        $user = User::factory()->create();

        $this->assertNotNull($user->created_at);
        $this->assertNotNull($user->updated_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->created_at);
        $this->assertInstanceOf(\Illuminate\Support\Carbon::class, $user->updated_at);
    }

    #[Test]
    public function it_can_mass_assign_allowed_attributes()
    {
        $data = [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password123',
            'role' => 'admin',
        ];

        $user = User::create($data);

        $this->assertEquals('Test User', $user->name);
        $this->assertEquals('test@example.com', $user->email);
        $this->assertEquals('admin', $user->role);
    }
}
