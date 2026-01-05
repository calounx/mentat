<?php

use App\Http\Controllers\Webhooks\StripeWebhookController;
use App\Livewire\Admin\AdminDashboard;
use App\Livewire\Admin\PlanManagement;
use App\Livewire\Admin\SiteOverview;
use App\Livewire\Admin\SystemSettings;
use App\Livewire\Admin\TenantManagement;
use App\Livewire\Admin\VpsManagement;
use App\Livewire\Backups\BackupList;
use App\Livewire\Dashboard\Overview;
use App\Livewire\Observability\MetricsDashboard;
use App\Livewire\Profile\ProfileSettings;
use App\Livewire\Sites\SiteCreate;
use App\Livewire\Sites\SiteList;
use App\Livewire\Team\TeamManager;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
*/

// Stripe Webhooks (must be before CSRF middleware)
Route::post('/stripe/webhook', [StripeWebhookController::class, 'handleWebhook'])
    ->name('stripe.webhook');

// Public routes
Route::get('/', function () {
    if (auth()->check()) {
        return redirect()->route('dashboard');
    }
    return view('welcome');
})->name('home');

// Authentication routes
Route::middleware('guest')->group(function () {
    Route::get('/login', function () {
        return view('auth.login');
    })->name('login');

    Route::post('/login', function () {
        $credentials = request()->validate([
            'email' => ['required', 'email'],
            'password' => ['required'],
        ]);

        if (auth()->attempt($credentials, request()->boolean('remember'))) {
            request()->session()->regenerate();

            // Super admins without tenant go to admin dashboard
            $user = auth()->user();
            if ($user->isSuperAdmin() && !$user->currentTenant()) {
                return redirect()->intended(route('admin.dashboard'));
            }

            return redirect()->intended(route('dashboard'));
        }

        return back()->withErrors([
            'email' => 'The provided credentials do not match our records.',
        ])->onlyInput('email');
    });

    Route::get('/register', function () {
        return view('auth.register');
    })->name('register');

    Route::post('/register', function () {
        $validated = request()->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users'],
            'password' => ['required', 'confirmed', 'min:8'],
            'organization_name' => ['required', 'string', 'max:255'],
        ]);

        $organization = \App\Models\Organization::create([
            'name' => $validated['organization_name'],
            'slug' => \Illuminate\Support\Str::slug($validated['organization_name']) . '-' . \Illuminate\Support\Str::random(6),
            'billing_email' => $validated['email'],
        ]);

        $tenant = \App\Models\Tenant::create([
            'organization_id' => $organization->id,
            'name' => 'Default',
            'slug' => 'default',
            'tier' => 'starter',
            'status' => 'active',
        ]);

        $user = \App\Models\User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => $validated['password'],
            'organization_id' => $organization->id,
            'role' => 'owner',
        ]);

        auth()->login($user);

        return redirect()->route('dashboard');
    });
});

Route::post('/logout', function () {
    auth()->logout();
    request()->session()->invalidate();
    request()->session()->regenerateToken();
    return redirect('/');
})->name('logout');

// Protected routes (require authentication)
Route::middleware('auth')->group(function () {
    // Dashboard - redirect super admins without tenant to admin dashboard
    Route::get('/dashboard', function () {
        $user = auth()->user();

        // Super admins without a tenant should go to admin dashboard
        if ($user->isSuperAdmin() && !$user->currentTenant()) {
            return redirect()->route('admin.dashboard');
        }

        return app(Overview::class);
    })->name('dashboard');

    // Routes that require a tenant
    Route::middleware('has-tenant')->group(function () {
        // Sites
        Route::prefix('sites')->name('sites.')->group(function () {
            Route::get('/', SiteList::class)->name('index');
            Route::get('/create', SiteCreate::class)->name('create');
        });

        // Backups
        Route::get('/backups', BackupList::class)->name('backups.index');

        // Observability
        Route::get('/metrics', MetricsDashboard::class)->name('metrics.index');

        // Team Management
        Route::get('/team', TeamManager::class)->name('team.index');
    });

    // Profile Settings (no tenant required)
    Route::get('/profile', ProfileSettings::class)->name('profile.index');
});

/*
|--------------------------------------------------------------------------
| Admin Routes (Super Admin Only)
|--------------------------------------------------------------------------
|
| These routes are protected by the super-admin middleware and provide
| system-wide management capabilities for VPS servers, tenants, sites,
| and system settings.
|
*/
Route::middleware(['auth', 'super-admin'])->prefix('admin')->name('admin.')->group(function () {
    // Admin Dashboard
    Route::get('/', AdminDashboard::class)->name('dashboard');

    // VPS Management
    Route::get('/vps', VpsManagement::class)->name('vps.index');

    // Tenant Management
    Route::get('/tenants', TenantManagement::class)->name('tenants.index');

    // Site Overview (all sites across all tenants)
    Route::get('/sites', SiteOverview::class)->name('sites.index');

    // Plan Management
    Route::get('/plans', PlanManagement::class)->name('plans.index');

    // System Settings
    Route::get('/settings', SystemSettings::class)->name('settings.index');
});
