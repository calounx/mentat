<?php

use App\Http\Controllers\Webhooks\StripeWebhookController;
use App\Livewire\Backups\BackupList;
use App\Livewire\Dashboard\Overview;
use App\Livewire\Observability\MetricsDashboard;
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
            'slug' => \Illuminate\Support\Str::slug($validated['organization_name']).'-'.\Illuminate\Support\Str::random(6),
            'billing_email' => $validated['email'],
        ]);

        $tenant = \App\Models\Tenant::create([
            'organization_id' => $organization->id,
            'name' => 'Default',
            'slug' => 'default',
            'tier' => 'starter',
            'status' => 'active',
        ]);

        $organization->update(['default_tenant_id' => $tenant->id]);

        $user = \App\Models\User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => $validated['password'],
            'organization_id' => $organization->id,
            'role' => 'owner',
            'email_verified_at' => null,
        ]);

        auth()->login($user);

        return redirect()->route('verification.notice');
    });
});

// Email Verification routes
Route::middleware('auth')->group(function () {
    Route::get('/email/verify', function () {
        return view('auth.verify-email');
    })->name('verification.notice');

    Route::get('/email/verify/{id}/{hash}', function ($id, $hash) {
        $user = \App\Models\User::findOrFail($id);

        if (! hash_equals((string) $hash, sha1($user->email))) {
            abort(403);
        }

        if ($user->hasVerifiedEmail()) {
            return redirect()->route('dashboard');
        }

        $user->markEmailAsVerified();

        return redirect()->route('dashboard');
    })->name('verification.verify');

    Route::post('/email/verification-notification', function () {
        request()->user()->sendEmailVerificationNotification();

        return back()->with('status', 'verification-link-sent');
    })->name('verification.send');
});

Route::post('/logout', function () {
    auth()->logout();
    request()->session()->invalidate();
    request()->session()->regenerateToken();

    return redirect('/');
})->name('logout');

// Protected routes (require authentication)
Route::middleware('auth')->group(function () {
    // Dashboard
    Route::get('/dashboard', Overview::class)->name('dashboard');

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

    // API Tokens
    Route::prefix('user')->name('user.')->group(function () {
        Route::post('/api-tokens', function () {
            $validated = request()->validate([
                'name' => 'required|string|max:255',
                'abilities' => 'array',
            ]);

            $token = request()->user()->createToken(
                $validated['name'],
                $validated['abilities'] ?? ['*']
            );

            return response()->json([
                'token' => $token,
                'plainTextToken' => $token->plainTextToken,
            ]);
        })->name('api-tokens.store');
    });
});
