<?php

namespace Tests\Browser;

use App\Models\VpsServer;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * E2E Test Suite: VPS Management
 *
 * Covers complete VPS management workflows including:
 * - Adding VPS server with SSH key
 * - Viewing VPS statistics
 * - Updating VPS configuration
 * - Decommissioning VPS
 */
class VpsManagementTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * Test 1: Add VPS server with SSH key.
     *
     * @test
     */
    public function user_can_add_vps_server_with_ssh_key(): void
    {
        $user = $this->createUser();

        // Generate test SSH key pair
        $sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7... test@example.com';

        $this->browse(function (Browser $browser) use ($user, $sshPublicKey) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->assertSee('VPS Servers')
                ->click('@add-vps-button')
                ->waitForText('Add VPS Server', 10)
                ->type('name', 'Production Server 1')
                ->type('ip_address', '192.168.1.100')
                ->type('ssh_port', '22')
                ->type('ssh_user', 'root')
                ->textarea('ssh_public_key', $sshPublicKey)
                ->select('provider', 'digitalocean')
                ->type('cpu_cores', '4')
                ->type('ram_mb', '8192')
                ->type('disk_gb', '160')
                ->press('Add VPS Server')
                ->waitFor('.alert-success', 20)
                ->assertSee('VPS server added successfully');

            // Verify VPS was created
            $this->assertDatabaseHas('vps_servers', [
                'tenant_id' => $user->currentTenant()->id,
                'name' => 'Production Server 1',
                'ip_address' => '192.168.1.100',
                'ssh_port' => 22,
                'ssh_user' => 'root',
                'provider' => 'digitalocean',
                'cpu_cores' => 4,
                'ram_mb' => 8192,
                'disk_gb' => 160,
                'status' => 'pending',
            ]);

            // Verify SSH key was stored (encrypted)
            $vps = VpsServer::where('name', 'Production Server 1')->first();
            $this->assertNotNull($vps->ssh_public_key);

            // Verify operation was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'vps_create',
                'status' => 'completed',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'vps_server_added',
                'resource_type' => 'VpsServer',
                'resource_id' => $vps->id,
            ]);
        });
    }

    /**
     * Test 2: View VPS statistics.
     *
     * @test
     */
    public function user_can_view_vps_statistics(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'Stats Server',
            'ip_address' => '10.0.0.50',
            'cpu_cores' => 8,
            'ram_mb' => 16384,
            'disk_gb' => 500,
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->click('@view-stats-'.$vps->id)
                ->waitForText('VPS Statistics', 10)
                ->assertSee('Stats Server')
                ->assertSee('10.0.0.50')
                ->assertSee('CPU Cores: 8')
                ->assertSee('RAM: 16 GB')
                ->assertSee('Disk: 500 GB')
                ->assertSee('Status: Active');

            // Check for resource usage charts
            $browser->assertVisible('@cpu-usage-chart')
                ->assertVisible('@memory-usage-chart')
                ->assertVisible('@disk-usage-chart')
                ->assertVisible('@network-traffic-chart');

            // Verify current resource metrics
            $browser->assertSee('CPU Usage')
                ->assertSee('Memory Usage')
                ->assertSee('Disk Usage')
                ->assertSee('Network Traffic');

            // Verify uptime information
            $browser->assertSee('Uptime')
                ->assertSee('Last Checked');

            // Verify audit log for viewing stats
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'vps_view_statistics',
                'resource_type' => 'VpsServer',
                'resource_id' => $vps->id,
            ]);
        });
    }

    /**
     * Test 3: Update VPS configuration.
     *
     * @test
     */
    public function user_can_update_vps_configuration(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'Old Name',
            'ip_address' => '192.168.1.50',
            'ssh_port' => 22,
            'cpu_cores' => 2,
            'ram_mb' => 4096,
            'disk_gb' => 80,
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->click('@edit-vps-'.$vps->id)
                ->waitForText('Edit VPS Server', 10)
                ->clear('name')
                ->type('name', 'Updated Server Name')
                ->clear('ssh_port')
                ->type('ssh_port', '2222')
                ->clear('cpu_cores')
                ->type('cpu_cores', '4')
                ->clear('ram_mb')
                ->type('ram_mb', '8192')
                ->clear('disk_gb')
                ->type('disk_gb', '160')
                ->press('Update VPS')
                ->waitFor('.alert-success', 10)
                ->assertSee('VPS updated successfully');

            // Verify updates in database
            $this->assertDatabaseHas('vps_servers', [
                'id' => $vps->id,
                'name' => 'Updated Server Name',
                'ssh_port' => 2222,
                'cpu_cores' => 4,
                'ram_mb' => 8192,
                'disk_gb' => 160,
            ]);

            // Verify operation was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'vps_update',
                'status' => 'completed',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'vps_server_updated',
                'resource_type' => 'VpsServer',
                'resource_id' => $vps->id,
            ]);

            // Verify updated name is displayed
            $browser->visit('/vps')
                ->assertSee('Updated Server Name')
                ->assertDontSee('Old Name');
        });
    }

    /**
     * Test 4: Decommission VPS.
     *
     * @test
     */
    public function user_can_decommission_vps(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'Server to Decommission',
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->assertSee('Active')
                ->click('@decommission-vps-'.$vps->id)
                ->waitForText('Confirm Decommission', 10)
                ->assertSee('Are you sure you want to decommission this VPS?')
                ->assertSee('This will remove all sites hosted on this server')
                ->type('confirmation', $vps->name) // Require name confirmation
                ->press('Decommission')
                ->waitFor('.alert-success', 20)
                ->assertSee('VPS decommissioned successfully');

            // Verify VPS status was updated
            $this->assertDatabaseHas('vps_servers', [
                'id' => $vps->id,
                'status' => 'decommissioned',
            ]);

            // Verify operation was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'vps_decommission',
                'status' => 'completed',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'vps_server_decommissioned',
                'resource_type' => 'VpsServer',
                'resource_id' => $vps->id,
            ]);

            // Verify VPS no longer shows as active
            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->assertSee('Decommissioned')
                ->assertDontSee('Active');
        });
    }

    /**
     * Test: SSH key rotation workflow.
     *
     * @test
     */
    public function user_can_rotate_ssh_keys(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'Key Rotation Server',
        ]);

        $newSshKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC8... rotated@example.com';

        $this->browse(function (Browser $browser) use ($user, $vps, $newSshKey) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->click('@edit-vps-'.$vps->id)
                ->waitForText('Edit VPS Server', 10)
                ->click('@rotate-ssh-key-button')
                ->waitForText('Rotate SSH Key', 10)
                ->assertSee('Generate a new SSH key pair')
                ->textarea('new_ssh_public_key', $newSshKey)
                ->press('Rotate Key')
                ->waitFor('.alert-success', 15)
                ->assertSee('SSH key rotated successfully');

            // Verify key was updated
            $vps->refresh();
            $this->assertNotNull($vps->ssh_public_key);

            // Verify rotation timestamp
            $this->assertDatabaseHas('users', [
                'id' => $user->id,
            ]);
            $user->refresh();
            $this->assertNotNull($user->ssh_key_rotated_at);
        });
    }

    /**
     * Test: Cannot decommission VPS with active sites.
     *
     * @test
     */
    public function cannot_decommission_vps_with_active_sites(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'VPS with Sites',
            'status' => 'active',
        ]);

        // Create active site on this VPS
        \App\Models\Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'vps_id' => $vps->id,
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->click('@decommission-vps-'.$vps->id)
                ->waitForText('Cannot Decommission', 10)
                ->assertSee('This VPS has active sites')
                ->assertSee('Please remove or migrate all sites first')
                ->assertDisabled('@confirm-decommission-button');
        });
    }

    /**
     * Test: VPS health check monitoring.
     *
     * @test
     */
    public function user_can_view_vps_health_status(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'name' => 'Health Check Server',
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->click('@health-check-'.$vps->id)
                ->waitForText('Health Check', 10)
                ->assertSee('Running health check...')
                ->waitFor('.health-check-result', 15)
                ->assertSee('SSH Connection')
                ->assertSee('Disk Space')
                ->assertSee('CPU Load')
                ->assertSee('Memory Available')
                ->assertSee('Network Connectivity');

            // Verify status indicators
            $browser->assertVisible('@health-status-ssh')
                ->assertVisible('@health-status-disk')
                ->assertVisible('@health-status-cpu')
                ->assertVisible('@health-status-memory')
                ->assertVisible('@health-status-network');
        });
    }

    /**
     * Test: Member can view VPS but not modify.
     *
     * @test
     */
    public function member_can_view_but_not_modify_vps(): void
    {
        $owner = $this->createUser();
        $member = \App\Models\User::factory()->create([
            'organization_id' => $owner->organization_id,
            'role' => 'member',
        ]);

        $vps = VpsServer::factory()->create([
            'tenant_id' => $owner->currentTenant()->id,
            'name' => 'Read-Only VPS',
        ]);

        $this->browse(function (Browser $browser) use ($member, $vps) {
            $this->loginAs($browser, $member);

            $browser->visit('/vps')
                ->assertSee($vps->name)
                ->assertDontSee('@edit-vps-'.$vps->id)
                ->assertDontSee('@decommission-vps-'.$vps->id)
                ->assertVisible('@view-stats-'.$vps->id);
        });
    }
}
