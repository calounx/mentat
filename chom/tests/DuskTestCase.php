<?php

namespace Tests;

use App\Models\Organization;
use App\Models\Tenant;
use App\Models\User;
use Facebook\WebDriver\Chrome\ChromeOptions;
use Facebook\WebDriver\Remote\DesiredCapabilities;
use Facebook\WebDriver\Remote\RemoteWebDriver;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Laravel\Dusk\Browser;
use Laravel\Dusk\TestCase as BaseTestCase;
use PHPUnit\Framework\Attributes\BeforeClass;

abstract class DuskTestCase extends BaseTestCase
{
    use DatabaseMigrations;

    /**
     * Prepare for Dusk test execution.
     */
    #[BeforeClass]
    public static function prepare(): void
    {
        if (! static::runningInSail()) {
            static::startChromeDriver(['--port=9515']);
        }
    }

    /**
     * Setup the test case.
     */
    protected function setUp(): void
    {
        parent::setUp();

        // Run migrations fresh for each test
        Artisan::call('migrate:fresh');

        // Set APP_URL for proper routing in tests
        config(['app.url' => env('APP_URL', 'http://localhost:8000')]);
    }

    /**
     * Create the RemoteWebDriver instance.
     */
    protected function driver(): RemoteWebDriver
    {
        $options = (new ChromeOptions)->addArguments(collect([
            $this->shouldStartMaximized() ? '--start-maximized' : '--window-size=1920,1080',
            '--disable-search-engine-choice-screen',
            '--disable-smooth-scrolling',
        ])->unless($this->hasHeadlessDisabled(), function (Collection $items) {
            return $items->merge([
                '--disable-gpu',
                '--headless=new',
            ]);
        })->all());

        return RemoteWebDriver::create(
            $_ENV['DUSK_DRIVER_URL'] ?? env('DUSK_DRIVER_URL') ?? 'http://localhost:9515',
            DesiredCapabilities::chrome()->setCapability(
                ChromeOptions::CAPABILITY, $options
            )
        );
    }

    /**
     * Helper: Create a user with organization and tenant.
     */
    protected function createUser(array $attributes = []): User
    {
        $organization = Organization::factory()->create();
        $tenant = Tenant::factory()->create([
            'organization_id' => $organization->id,
        ]);
        $organization->update(['default_tenant_id' => $tenant->id]);

        return User::factory()->create(array_merge([
            'organization_id' => $organization->id,
            'role' => 'owner',
            'email_verified_at' => now(),
        ], $attributes));
    }

    /**
     * Helper: Create a user with admin role.
     */
    protected function createAdmin(array $attributes = []): User
    {
        return $this->createUser(array_merge(['role' => 'admin'], $attributes));
    }

    /**
     * Helper: Create a user with member role.
     */
    protected function createMember(array $attributes = []): User
    {
        return $this->createUser(array_merge(['role' => 'member'], $attributes));
    }

    /**
     * Helper: Create a user with viewer role.
     */
    protected function createViewer(array $attributes = []): User
    {
        return $this->createUser(array_merge(['role' => 'viewer'], $attributes));
    }

    /**
     * Helper: Login a user via the browser.
     */
    protected function loginAs(Browser $browser, User $user, string $password = 'password'): Browser
    {
        return $browser
            ->visit('/login')
            ->type('email', $user->email)
            ->type('password', $password)
            ->press('Log in')
            ->waitForLocation('/dashboard', 10)
            ->assertPathIs('/dashboard');
    }

    /**
     * Helper: Register a new user via the browser.
     */
    protected function registerUser(Browser $browser, array $data = []): Browser
    {
        $defaultData = [
            'name' => 'Test User',
            'email' => 'test@example.com',
            'password' => 'password',
            'password_confirmation' => 'password',
            'organization_name' => 'Test Organization',
        ];

        $data = array_merge($defaultData, $data);

        return $browser
            ->visit('/register')
            ->type('name', $data['name'])
            ->type('email', $data['email'])
            ->type('password', $data['password'])
            ->type('password_confirmation', $data['password_confirmation'])
            ->type('organization_name', $data['organization_name'])
            ->press('Register')
            ->waitForLocation('/email/verify', 10);
    }

    /**
     * Helper: Wait for Livewire to finish loading.
     */
    protected function waitForLivewire(Browser $browser, int $seconds = 5): Browser
    {
        return $browser->waitUsing($seconds, 100, function () use ($browser) {
            return $browser->script('return window.Livewire && !window.Livewire.isLoading');
        });
    }

    /**
     * Helper: Create an API token for a user.
     */
    protected function createApiToken(User $user, string $name = 'Test Token', array $abilities = ['*']): string
    {
        return $user->createToken($name, $abilities)->plainTextToken;
    }

    /**
     * Helper: Assert that element exists and is visible.
     */
    protected function assertVisible(Browser $browser, string $selector): void
    {
        $browser->assertVisible($selector);
    }

    /**
     * Helper: Assert that text exists on the page.
     */
    protected function assertSeeText(Browser $browser, string $text): void
    {
        $browser->assertSee($text);
    }

    /**
     * Helper: Take a screenshot with a descriptive name.
     */
    protected function screenshot(Browser $browser, string $name): void
    {
        $browser->screenshot($name);
    }

    /**
     * Helper: Pause execution for debugging (only in non-headless mode).
     */
    protected function pause(Browser $browser, int $milliseconds = 1000): void
    {
        if ($this->hasHeadlessDisabled()) {
            $browser->pause($milliseconds);
        }
    }

    /**
     * Helper: Execute JavaScript and wait for completion.
     */
    protected function executeScript(Browser $browser, string $script): mixed
    {
        return $browser->script($script);
    }

    /**
     * Helper: Clear database between tests.
     */
    protected function clearDatabase(): void
    {
        DB::statement('PRAGMA foreign_keys = OFF');

        $tables = ['users', 'organizations', 'tenants', 'sites', 'site_backups',
                   'vps_servers', 'operations', 'audit_logs', 'team_invitations'];

        foreach ($tables as $table) {
            DB::table($table)->truncate();
        }

        DB::statement('PRAGMA foreign_keys = ON');
    }
}
