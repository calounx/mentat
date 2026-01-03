<?php

namespace Tests\Unit\Repositories;

use App\Models\Tenant;
use App\Models\User;
use App\Repositories\UserRepository;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UserRepositoryTest extends TestCase
{
    use RefreshDatabase;

    private UserRepository $repository;
    private Tenant $tenant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->repository = new UserRepository(new User());

        $this->tenant = Tenant::factory()->create([
            'tier' => 'professional',
            'status' => 'active',
        ]);
    }

    public function test_it_finds_user_by_id_when_exists()
    {
        $user = User::factory()->create([
            'name' => 'John Doe',
            'email' => 'john@example.com',
        ]);

        $found = $this->repository->findById($user->id);

        $this->assertNotNull($found);
        $this->assertEquals($user->id, $found->id);
        $this->assertEquals('john@example.com', $found->email);
        $this->assertTrue($found->relationLoaded('tenants'));
    }

    public function test_it_returns_null_when_user_not_found()
    {
        $found = $this->repository->findById('non-existent-id');

        $this->assertNull($found);
    }

    public function test_it_finds_user_by_email()
    {
        $user = User::factory()->create([
            'email' => 'test@example.com',
        ]);

        $found = $this->repository->findByEmail('test@example.com');

        $this->assertNotNull($found);
        $this->assertEquals($user->id, $found->id);
        $this->assertEquals('test@example.com', $found->email);
    }

    public function test_it_returns_null_when_email_not_found()
    {
        $found = $this->repository->findByEmail('nonexistent@example.com');

        $this->assertNull($found);
    }

    public function test_it_finds_users_by_tenant_with_pagination()
    {
        $users = User::factory()->count(5)->create();

        foreach ($users as $user) {
            $this->repository->attachToTenant($user->id, $this->tenant->id, 'member');
        }

        $otherTenant = Tenant::factory()->create();
        $otherUsers = User::factory()->count(3)->create();

        foreach ($otherUsers as $user) {
            $this->repository->attachToTenant($user->id, $otherTenant->id, 'member');
        }

        $result = $this->repository->findByTenant($this->tenant->id, 10);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(5, $result->total());
    }

    public function test_it_creates_user_successfully()
    {
        $data = [
            'name' => 'Jane Doe',
            'email' => 'jane@example.com',
            'password' => 'password123',
        ];

        $user = $this->repository->create($data);

        $this->assertNotNull($user);
        $this->assertEquals('Jane Doe', $user->name);
        $this->assertEquals('jane@example.com', $user->email);
        $this->assertTrue(Hash::check('password123', $user->password));
        $this->assertDatabaseHas('users', [
            'email' => 'jane@example.com',
        ]);
    }

    public function test_it_creates_user_and_attaches_to_tenant()
    {
        $data = [
            'name' => 'Bob Smith',
            'email' => 'bob@example.com',
            'password' => 'password123',
            'tenant_id' => $this->tenant->id,
            'role' => 'admin',
        ];

        $user = $this->repository->create($data);

        $this->assertNotNull($user);
        $this->assertDatabaseHas('tenant_user', [
            'user_id' => $user->id,
            'tenant_id' => $this->tenant->id,
            'role' => 'admin',
        ]);
    }

    public function test_it_updates_user_successfully()
    {
        $user = User::factory()->create([
            'name' => 'Original Name',
        ]);

        $updated = $this->repository->update($user->id, [
            'name' => 'Updated Name',
        ]);

        $this->assertEquals('Updated Name', $updated->name);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Updated Name',
        ]);
    }

    public function test_it_hashes_password_when_updating()
    {
        $user = User::factory()->create();

        $updated = $this->repository->update($user->id, [
            'password' => 'newpassword123',
        ]);

        $this->assertTrue(Hash::check('newpassword123', $updated->password));
    }

    public function test_it_throws_exception_when_updating_nonexistent_user()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->update('non-existent-id', ['name' => 'Test']);
    }

    public function test_it_deletes_user_and_detaches_from_tenants()
    {
        $user = User::factory()->create();
        $this->repository->attachToTenant($user->id, $this->tenant->id, 'member');

        $deleted = $this->repository->delete($user->id);

        $this->assertTrue($deleted);
        $this->assertDatabaseMissing('users', ['id' => $user->id]);
        $this->assertDatabaseMissing('tenant_user', [
            'user_id' => $user->id,
            'tenant_id' => $this->tenant->id,
        ]);
    }

    public function test_it_throws_exception_when_deleting_nonexistent_user()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->delete('non-existent-id');
    }

    public function test_it_attaches_user_to_tenant_successfully()
    {
        $user = User::factory()->create();

        $result = $this->repository->attachToTenant($user->id, $this->tenant->id, 'member');

        $this->assertTrue($result);
        $this->assertDatabaseHas('tenant_user', [
            'user_id' => $user->id,
            'tenant_id' => $this->tenant->id,
            'role' => 'member',
        ]);
    }

    public function test_it_prevents_duplicate_tenant_attachment()
    {
        $user = User::factory()->create();

        $this->repository->attachToTenant($user->id, $this->tenant->id, 'member');
        $result = $this->repository->attachToTenant($user->id, $this->tenant->id, 'admin');

        $this->assertFalse($result);
        $this->assertEquals(1, \DB::table('tenant_user')
            ->where('user_id', $user->id)
            ->where('tenant_id', $this->tenant->id)
            ->count());
    }

    public function test_it_detaches_user_from_tenant_successfully()
    {
        $user = User::factory()->create();
        $this->repository->attachToTenant($user->id, $this->tenant->id, 'member');

        $result = $this->repository->detachFromTenant($user->id, $this->tenant->id);

        $this->assertTrue($result);
        $this->assertDatabaseMissing('tenant_user', [
            'user_id' => $user->id,
            'tenant_id' => $this->tenant->id,
        ]);
    }

    public function test_it_returns_false_when_detaching_nonexistent_relationship()
    {
        $user = User::factory()->create();

        $result = $this->repository->detachFromTenant($user->id, $this->tenant->id);

        $this->assertFalse($result);
    }

    public function test_it_verifies_user_email()
    {
        $user = User::factory()->create([
            'email_verified_at' => null,
        ]);

        $verified = $this->repository->verifyEmail($user->id);

        $this->assertNotNull($verified->email_verified_at);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
        ]);
        $this->assertNotNull($verified->fresh()->email_verified_at);
    }

    public function test_it_throws_exception_when_verifying_nonexistent_user()
    {
        $this->expectException(ModelNotFoundException::class);

        $this->repository->verifyEmail('non-existent-id');
    }

    public function test_it_gets_all_users_with_pagination()
    {
        User::factory()->count(25)->create();

        $result = $this->repository->findAll(15);

        $this->assertInstanceOf(LengthAwarePaginator::class, $result);
        $this->assertEquals(25, $result->total());
        $this->assertEquals(15, $result->perPage());
    }
}
