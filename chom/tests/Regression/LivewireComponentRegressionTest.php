<?php

namespace Tests\Regression;

use App\Livewire\Backups\BackupList;
use App\Livewire\Dashboard\Overview;
use App\Livewire\Observability\MetricsDashboard;
use App\Livewire\Sites\SiteCreate;
use App\Livewire\Sites\SiteList;
use App\Livewire\Team\TeamManager;
use App\Models\Site;
use App\Models\SiteBackup;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class LivewireComponentRegressionTest extends TestCase
{
    use RefreshDatabase;

    protected User $user;

    protected function setUp(): void
    {
        parent::setUp();
        $this->user = User::factory()->create();
    }

    #[Test]
    public function dashboard_overview_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(Overview::class)
            ->assertStatus(200);
    }

    #[Test]
    public function site_list_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(SiteList::class)
            ->assertStatus(200);
    }

    #[Test]
    public function site_list_displays_user_sites(): void
    {
        $tenant = $this->user->currentTenant();

        Site::factory(3)->create([
            'tenant_id' => $tenant->id,
            'domain' => 'test.example.com',
        ]);

        Livewire::actingAs($this->user)
            ->test(SiteList::class)
            ->assertSee('test.example.com');
    }

    #[Test]
    public function site_create_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(SiteCreate::class)
            ->assertStatus(200);
    }

    #[Test]
    public function site_create_validates_required_fields(): void
    {
        Livewire::actingAs($this->user)
            ->test(SiteCreate::class)
            ->set('domain', '')
            ->call('create')
            ->assertHasErrors(['domain']);
    }

    #[Test]
    public function backup_list_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(BackupList::class)
            ->assertStatus(200);
    }

    #[Test]
    public function backup_list_displays_backups(): void
    {
        $tenant = $this->user->currentTenant();
        $site = Site::factory()->create(['tenant_id' => $tenant->id]);

        SiteBackup::factory()->create([
            'site_id' => $site->id,
            'filename' => 'test-backup.tar.gz',
        ]);

        Livewire::actingAs($this->user)
            ->test(BackupList::class)
            ->assertSee('test-backup.tar.gz');
    }

    #[Test]
    public function team_manager_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(TeamManager::class)
            ->assertStatus(200);
    }

    #[Test]
    public function team_manager_displays_team_members(): void
    {
        $teammate = User::factory()->create([
            'organization_id' => $this->user->organization_id,
            'name' => 'Team Member',
            'email' => 'teammate@example.com',
        ]);

        Livewire::actingAs($this->user)
            ->test(TeamManager::class)
            ->assertSee('Team Member')
            ->assertSee('teammate@example.com');
    }

    #[Test]
    public function metrics_dashboard_component_renders(): void
    {
        Livewire::actingAs($this->user)
            ->test(MetricsDashboard::class)
            ->assertStatus(200);
    }

    #[Test]
    public function unauthenticated_user_cannot_access_livewire_components(): void
    {
        $this->get(route('dashboard'))
            ->assertRedirect(route('login'));

        $this->get(route('sites.index'))
            ->assertRedirect(route('login'));

        $this->get(route('backups.index'))
            ->assertRedirect(route('login'));
    }

    #[Test]
    public function authenticated_user_can_navigate_to_components(): void
    {
        $this->actingAs($this->user)
            ->get(route('dashboard'))
            ->assertStatus(200);

        $this->actingAs($this->user)
            ->get(route('sites.index'))
            ->assertStatus(200);

        $this->actingAs($this->user)
            ->get(route('backups.index'))
            ->assertStatus(200);

        $this->actingAs($this->user)
            ->get(route('team.index'))
            ->assertStatus(200);
    }

    #[Test]
    public function livewire_components_use_wire_model_correctly(): void
    {
        Livewire::actingAs($this->user)
            ->test(SiteCreate::class)
            ->assertSeeHtml('wire:model');
    }

    #[Test]
    public function livewire_components_handle_wire_click_events(): void
    {
        Livewire::actingAs($this->user)
            ->test(SiteList::class)
            ->assertSeeHtml('wire:click');
    }
}
