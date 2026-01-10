<?php

use App\Http\Controllers\Auth\ForgotPasswordController;
use App\Http\Controllers\Auth\ResetPasswordController;
use App\Http\Controllers\Webhooks\StripeWebhookController;
use App\Livewire\Admin\AdminDashboard;
use App\Livewire\Admin\OrganizationManagement;
use App\Livewire\Admin\PendingApprovals;
use App\Livewire\Admin\PlanManagement;
use App\Livewire\Admin\SiteOverview;
use App\Livewire\Admin\SystemSettings;
use App\Livewire\Admin\TenantManagement;
use App\Livewire\Admin\UserManagement;
use App\Livewire\Admin\VpsManagement;
use App\Livewire\Backups\BackupList;
use App\Livewire\Dashboard\Overview;
use App\Livewire\Observability\MetricsDashboard;
use App\Livewire\Profile\ProfileSettings;
use App\Livewire\Sites\SiteCreate;
use App\Livewire\Sites\SiteList;
use App\Livewire\Team\TeamManager;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Web Routes
|--------------------------------------------------------------------------
*/

// Health Check (must be public and unrestricted)
Route::get('/health', function () {
    try {
        // Test database connection
        DB::connection()->getPdo();
        $dbHealthy = true;
    } catch (\Exception $e) {
        $dbHealthy = false;
    }

    $status = $dbHealthy ? 200 : 503;

    return response()->json([
        'status' => $dbHealthy ? 'healthy' : 'unhealthy',
        'timestamp' => now()->toIso8601String(),
        'checks' => [
            'database' => $dbHealthy,
        ],
    ], $status);
})->name('health');

// Stripe Webhooks (must be before CSRF middleware)
Route::post('/stripe/webhook', [StripeWebhookController::class, 'handleWebhook'])
    ->name('stripe.webhook');

// Public routes
Route::get('/', function () {
    if (auth()->check()) {
        return redirect()->route('dashboard');
    }

    // Get active plans from database (not static config)
    $plans = \App\Models\TierLimit::active()
        ->currentlyValid()
        ->orderByRaw("CASE tier WHEN 'starter' THEN 1 WHEN 'pro' THEN 2 WHEN 'enterprise' THEN 3 ELSE 4 END")
        ->get();

    return view('welcome', ['plans' => $plans]);
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
        // Check for rejected email first
        $email = request()->input('email');
        if (\App\Models\RejectedEmail::isRejected($email)) {
            return back()->withErrors([
                'email' => 'This email address is not eligible for registration.',
            ])->onlyInput('email');
        }

        $validated = request()->validate([
            'username' => ['required', 'string', 'max:50', 'unique:users', 'regex:/^[a-zA-Z0-9_-]+$/'],
            'first_name' => ['required', 'string', 'max:100'],
            'last_name' => ['required', 'string', 'max:100'],
            'email' => ['required', 'string', 'email', 'max:255', 'unique:users'],
            'password' => ['required', 'confirmed', 'min:8'],
            'organization_name' => ['nullable', 'string', 'max:255'],
        ]);

        \DB::transaction(function () use ($validated) {
            // Determine organization
            if (!empty($validated['organization_name'])) {
                $organization = \App\Models\Organization::create([
                    'name' => $validated['organization_name'],
                    'slug' => \Illuminate\Support\Str::slug($validated['organization_name']) . '-' . \Illuminate\Support\Str::random(6),
                    'is_fictive' => false,
                    'is_approved' => false,
                    'status' => 'active',
                    'billing_email' => $validated['email'],
                ]);
            } else {
                // Create fictive organization
                $organization = \App\Models\Organization::create([
                    'name' => "Personal - {$validated['first_name']} {$validated['last_name']}",
                    'slug' => 'fictive-' . \Illuminate\Support\Str::random(12),
                    'is_fictive' => true,
                    'is_approved' => false,
                    'status' => 'active',
                    'billing_email' => $validated['email'],
                ]);
            }

            // Create tenant (NOT approved, NO tier assigned yet)
            $tenant = \App\Models\Tenant::create([
                'organization_id' => $organization->id,
                'name' => $organization->name,
                'slug' => $organization->slug,
                'status' => 'active',
                'is_approved' => false,
                'requires_plan_selection' => true,
                'tier' => null,
            ]);

            // Create user (pending approval)
            $user = \App\Models\User::create([
                'username' => $validated['username'],
                'first_name' => $validated['first_name'],
                'last_name' => $validated['last_name'],
                'email' => $validated['email'],
                'password' => \Hash::make($validated['password']),
                'organization_id' => $organization->id,
                'role' => 'owner',
                'approval_status' => 'pending',
            ]);

            // Send verification email (Laravel built-in)
            $user->sendEmailVerificationNotification();

            // Notify admins
            $admins = \App\Models\User::where('is_super_admin', true)->get();
            \Notification::send($admins, new \App\Notifications\NewUserRegistered($user, $organization));
        });

        // DO NOT log in the user
        return redirect()->route('login')->with('status',
            'Registration successful! Please check your email to verify your account. Once verified, an administrator will review your application.'
        );
    });

    // Password Reset Routes
    Route::get('/forgot-password', [ForgotPasswordController::class, 'showLinkRequestForm'])
        ->name('password.request');

    Route::post('/forgot-password', [ForgotPasswordController::class, 'sendResetLinkEmail'])
        ->name('password.email');

    Route::get('/reset-password/{token}', [ResetPasswordController::class, 'showResetForm'])
        ->name('password.reset');

    Route::post('/reset-password', [ResetPasswordController::class, 'reset'])
        ->name('password.update');
});

Route::post('/logout', function () {
    auth()->logout();
    request()->session()->invalidate();
    request()->session()->regenerateToken();
    return redirect('/');
})->name('logout');

// Protected routes (require authentication)
Route::middleware('auth')->group(function () {
    // Dashboard (super admin redirect handled in Overview component)
    Route::get('/dashboard', Overview::class)->name('dashboard');

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

    // Admin can view/edit other users' profiles (with authorization check)
    Route::get('/profile/{userId}', ProfileSettings::class)
        ->middleware('can:view,userId')
        ->name('profile.view');
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

    // Pending Approvals
    Route::get('/pending-approvals', PendingApprovals::class)->name('pending-approvals');

    // VPS Management
    Route::get('/vps', VpsManagement::class)->name('vps.index');

    // Organization Management
    Route::get('/organizations', OrganizationManagement::class)->name('organizations.index');

    // User Management
    Route::get('/users', UserManagement::class)->name('users.index');

    // Tenant Management
    Route::get('/tenants', TenantManagement::class)->name('tenants.index');

    // Site Overview (all sites across all tenants)
    Route::get('/sites', SiteOverview::class)->name('sites.index');

    // Plan Management
    Route::get('/plans', PlanManagement::class)->name('plans.index');

    // System Settings
    Route::get('/settings', SystemSettings::class)->name('settings.index');
});
