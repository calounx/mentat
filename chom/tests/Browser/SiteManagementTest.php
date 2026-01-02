<?php

namespace Tests\Browser;

use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Laravel\Dusk\Browser;
use Tests\DuskTestCase;

/**
 * E2E Test Suite: Site Management
 *
 * Covers complete site management workflows including:
 * - Creating WordPress and Laravel sites
 * - Updating site configuration
 * - Deleting sites
 * - Creating backups
 * - Downloading backup files
 * - Restoring from backups
 * - Viewing site metrics
 */
class SiteManagementTest extends DuskTestCase
{
    use DatabaseMigrations;

    /**
     * Test 1: Create WordPress site.
     *
     * @test
     */
    public function user_can_create_wordpress_site(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites/create')
                ->assertSee('Create New Site')
                ->select('site_type', 'wordpress')
                ->type('domain', 'wordpress-test.com')
                ->select('vps_id', $vps->id)
                ->select('php_version', '8.2')
                ->check('ssl_enabled')
                ->press('Create Site')
                ->waitFor('.alert-success', 15)
                ->assertSee('Site created successfully');

            // Verify site was created in database
            $this->assertDatabaseHas('sites', [
                'tenant_id' => $user->currentTenant()->id,
                'domain' => 'wordpress-test.com',
                'site_type' => 'wordpress',
                'php_version' => '8.2',
                'ssl_enabled' => true,
                'vps_id' => $vps->id,
            ]);

            // Verify operation was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'site_create',
                'status' => 'completed',
            ]);
        });
    }

    /**
     * Test 2: Create Laravel site.
     *
     * @test
     */
    public function user_can_create_laravel_site(): void
    {
        $user = $this->createUser();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($user, $vps) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites/create')
                ->assertSee('Create New Site')
                ->select('site_type', 'laravel')
                ->type('domain', 'laravel-app.com')
                ->select('vps_id', $vps->id)
                ->select('php_version', '8.3')
                ->check('ssl_enabled')
                ->press('Create Site')
                ->waitFor('.alert-success', 15)
                ->assertSee('Site created successfully');

            // Verify site was created
            $this->assertDatabaseHas('sites', [
                'tenant_id' => $user->currentTenant()->id,
                'domain' => 'laravel-app.com',
                'site_type' => 'laravel',
                'php_version' => '8.3',
                'ssl_enabled' => true,
            ]);
        });
    }

    /**
     * Test 3: Update site configuration.
     *
     * @test
     */
    public function user_can_update_site_configuration(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'original-domain.com',
            'php_version' => '8.2',
        ]);

        $this->browse(function (Browser $browser) use ($user, $site) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites')
                ->assertSee($site->domain)
                ->click('@edit-site-'.$site->id)
                ->waitForText('Edit Site', 10)
                ->type('domain', 'updated-domain.com')
                ->select('php_version', '8.3')
                ->press('Update Site')
                ->waitFor('.alert-success', 10)
                ->assertSee('Site updated successfully');

            // Verify changes in database
            $this->assertDatabaseHas('sites', [
                'id' => $site->id,
                'domain' => 'updated-domain.com',
                'php_version' => '8.3',
            ]);
        });
    }

    /**
     * Test 4: Delete site.
     *
     * @test
     */
    public function user_can_delete_site(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'to-delete.com',
        ]);

        $this->browse(function (Browser $browser) use ($user, $site) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites')
                ->assertSee($site->domain)
                ->click('@delete-site-'.$site->id)
                ->waitForText('Confirm Deletion', 10)
                ->assertSee('Are you sure you want to delete this site?')
                ->press('Delete')
                ->waitFor('.alert-success', 15)
                ->assertSee('Site deleted successfully')
                ->assertDontSee($site->domain);

            // Verify site was soft-deleted
            $this->assertSoftDeleted('sites', [
                'id' => $site->id,
            ]);

            // Verify deletion was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'site_delete',
            ]);
        });
    }

    /**
     * Test 5: Create full backup.
     *
     * @test
     */
    public function user_can_create_full_backup(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'backup-test.com',
        ]);

        $this->browse(function (Browser $browser) use ($user, $site) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites')
                ->assertSee($site->domain)
                ->click('@backup-site-'.$site->id)
                ->waitForText('Create Backup', 10)
                ->select('backup_type', 'full')
                ->type('description', 'Full backup before update')
                ->press('Create Backup')
                ->waitFor('.alert-success', 20)
                ->assertSee('Backup created successfully');

            // Verify backup was created
            $this->assertDatabaseHas('site_backups', [
                'site_id' => $site->id,
                'backup_type' => 'full',
                'description' => 'Full backup before update',
                'status' => 'completed',
            ]);

            // Verify backup operation was logged
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'backup_create',
                'status' => 'completed',
            ]);
        });
    }

    /**
     * Test 6: Download backup file.
     *
     * @test
     */
    public function user_can_download_backup_file(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
        ]);
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'status' => 'completed',
            'file_path' => '/backups/test-backup.tar.gz',
            'file_size_mb' => 150,
        ]);

        $this->browse(function (Browser $browser) use ($user, $backup) {
            $this->loginAs($browser, $user);

            $browser->visit('/backups')
                ->assertSee($backup->description)
                ->click('@download-backup-'.$backup->id)
                ->pause(2000); // Allow download to start

            // Verify download was logged
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'backup_download',
                'resource_type' => 'SiteBackup',
                'resource_id' => $backup->id,
            ]);
        });
    }

    /**
     * Test 7: Restore site from backup.
     *
     * @test
     */
    public function user_can_restore_site_from_backup(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'restore-test.com',
        ]);
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'status' => 'completed',
            'backup_type' => 'full',
        ]);

        $this->browse(function (Browser $browser) use ($user, $site, $backup) {
            $this->loginAs($browser, $user);

            $browser->visit('/backups')
                ->assertSee($backup->description)
                ->click('@restore-backup-'.$backup->id)
                ->waitForText('Confirm Restore', 10)
                ->assertSee('This will replace all current site data')
                ->press('Restore')
                ->waitFor('.alert-success', 30)
                ->assertSee('Restore completed successfully');

            // Verify restore operation was created
            $this->assertDatabaseHas('operations', [
                'user_id' => $user->id,
                'operation_type' => 'backup_restore',
                'status' => 'completed',
            ]);

            // Verify audit log
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'backup_restore',
                'resource_type' => 'SiteBackup',
                'resource_id' => $backup->id,
            ]);
        });
    }

    /**
     * Test 8: View site metrics.
     *
     * @test
     */
    public function user_can_view_site_metrics(): void
    {
        $user = $this->createUser();
        $site = Site::factory()->create([
            'tenant_id' => $user->currentTenant()->id,
            'domain' => 'metrics-test.com',
            'storage_used_mb' => 500,
        ]);

        $this->browse(function (Browser $browser) use ($user, $site) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites')
                ->assertSee($site->domain)
                ->click('@view-metrics-'.$site->id)
                ->waitForText('Site Metrics', 10)
                ->assertSee('metrics-test.com')
                ->assertSee('Storage Used')
                ->assertSee('500 MB')
                ->assertSee('PHP Version')
                ->assertSee($site->php_version)
                ->assertSee('SSL Status');

            // Verify SSL status display
            if ($site->ssl_enabled) {
                $browser->assertSee('Enabled');
            } else {
                $browser->assertSee('Disabled');
            }

            // Verify metrics were logged
            $this->assertDatabaseHas('audit_logs', [
                'user_id' => $user->id,
                'action' => 'site_view_metrics',
                'resource_type' => 'Site',
                'resource_id' => $site->id,
            ]);
        });
    }

    /**
     * Test: Cannot create site without active VPS.
     *
     * @test
     */
    public function cannot_create_site_without_active_vps(): void
    {
        $user = $this->createUser();

        $this->browse(function (Browser $browser) use ($user) {
            $this->loginAs($browser, $user);

            $browser->visit('/sites/create')
                ->assertSee('No active VPS servers available')
                ->assertDisabled('@create-site-button');
        });
    }

    /**
     * Test: Member role can create sites.
     *
     * @test
     */
    public function member_can_create_sites(): void
    {
        $member = $this->createMember();
        $vps = VpsServer::factory()->create([
            'tenant_id' => $member->currentTenant()->id,
            'status' => 'active',
        ]);

        $this->browse(function (Browser $browser) use ($member, $vps) {
            $this->loginAs($browser, $member);

            $browser->visit('/sites/create')
                ->assertSee('Create New Site')
                ->select('site_type', 'wordpress')
                ->type('domain', 'member-site.com')
                ->select('vps_id', $vps->id)
                ->press('Create Site')
                ->waitFor('.alert-success', 15)
                ->assertSee('Site created successfully');

            $this->assertDatabaseHas('sites', [
                'domain' => 'member-site.com',
            ]);
        });
    }

    /**
     * Test: Viewer role cannot create sites.
     *
     * @test
     */
    public function viewer_cannot_create_sites(): void
    {
        $viewer = $this->createViewer();

        $this->browse(function (Browser $browser) use ($viewer) {
            $this->loginAs($browser, $viewer);

            $browser->visit('/sites/create')
                ->assertSee('Unauthorized')
                ->assertPathIs('/dashboard');
        });
    }
}
