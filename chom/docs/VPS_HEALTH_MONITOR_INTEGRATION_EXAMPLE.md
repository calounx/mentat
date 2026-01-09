# VPS Health Monitor Integration Example

## Quick Start Integration

This guide shows how to integrate the VPS Health Monitor component into your CHOM application.

## Step 1: Add Route

Add this route to `/routes/web.php`:

```php
use App\Models\VpsServer;
use Illuminate\Support\Facades\Route;

Route::middleware(['auth'])->group(function () {
    Route::get('/vps/{vps}/health', function (VpsServer $vps) {
        return view('vps.health-monitor', [
            'vps' => $vps,
        ]);
    })->name('vps.health');
});
```

## Step 2: Create View File

Create `/resources/views/vps/health-monitor.blade.php`:

```blade
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS Health Monitor - {{ $vps->hostname }}</title>

    <!-- Tailwind CSS -->
    <script src="https://cdn.tailwindcss.com"></script>

    <!-- Livewire Styles -->
    @livewireStyles
</head>
<body class="bg-gray-100">
    <div class="container mx-auto px-4 py-8">
        <!-- Navigation -->
        <div class="mb-6">
            <a href="/dashboard" class="text-blue-600 hover:text-blue-800">&larr; Back to Dashboard</a>
        </div>

        <!-- VPS Health Monitor Component -->
        <livewire:vps-health-monitor :vps="$vps" />
    </div>

    <!-- Livewire Scripts -->
    @livewireScripts

    <!-- Alpine.js (for dropdowns) -->
    <script defer src="https://cdn.jsdelivr.net/npm/alpinejs@3.x.x/dist/cdn.min.js"></script>

    <!-- Chart.js (for statistics charts) -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
</body>
</html>
```

## Step 3: Add to Navigation Menu

Add a link to your VPS listing page:

```blade
@foreach($vpsServers as $vps)
    <div class="vps-card">
        <h3>{{ $vps->hostname }}</h3>
        <p>{{ $vps->ip_address }}</p>

        <div class="actions">
            <a href="{{ route('vps.health', $vps) }}" class="btn btn-primary">
                View Health Monitor
            </a>
        </div>
    </div>
@endforeach
```

## Step 4: Configure API Endpoints

Update your `.env` file with API configuration:

```env
# API Configuration
API_URL=https://api.your-domain.com
API_TOKEN=your-secret-api-token-here

# Service Configuration
SERVICES_API_URL="${API_URL}"
SERVICES_API_TOKEN="${API_TOKEN}"
```

Update `config/services.php`:

```php
return [
    // ... other services

    'api' => [
        'url' => env('SERVICES_API_URL', 'http://localhost'),
        'token' => env('SERVICES_API_TOKEN'),
    ],
];
```

## Step 5: Register Policy (if not already done)

In `app/Providers/AuthServiceProvider.php`:

```php
use App\Models\VpsServer;
use App\Policies\VpsServerPolicy;

class AuthServiceProvider extends ServiceProvider
{
    protected $policies = [
        VpsServer::class => VpsServerPolicy::class,
    ];

    public function boot(): void
    {
        $this->registerPolicies();
    }
}
```

## Advanced Integration Examples

### Example 1: Embed in Dashboard

```blade
<!-- resources/views/dashboard.blade.php -->

<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
    @foreach($vpsServers as $vps)
        <div class="bg-white rounded-lg shadow p-6">
            <h3 class="text-lg font-semibold mb-4">{{ $vps->hostname }}</h3>

            <!-- Compact Health Monitor -->
            <livewire:vps-health-monitor
                :vps="$vps"
                :refreshInterval="60"
                wire:key="vps-{{ $vps->id }}" />
        </div>
    @endforeach
</div>
```

### Example 2: With Custom Refresh Interval

```blade
<!-- For high-priority VPS, refresh every 15 seconds -->
<livewire:vps-health-monitor
    :vps="$productionVps"
    :refreshInterval="15" />

<!-- For dev VPS, refresh every 2 minutes -->
<livewire:vps-health-monitor
    :vps="$devVps"
    :refreshInterval="120" />
```

### Example 3: Modal Integration

```blade
<div x-data="{ showHealthMonitor: false }">
    <!-- Trigger Button -->
    <button @click="showHealthMonitor = true" class="btn btn-primary">
        View Health
    </button>

    <!-- Modal -->
    <div x-show="showHealthMonitor"
         x-cloak
         class="fixed inset-0 z-50 overflow-y-auto"
         @click.away="showHealthMonitor = false">

        <div class="flex items-center justify-center min-h-screen p-4">
            <div class="bg-white rounded-lg shadow-xl max-w-7xl w-full p-6">
                <div class="flex justify-between items-center mb-4">
                    <h2 class="text-2xl font-bold">VPS Health Monitor</h2>
                    <button @click="showHealthMonitor = false" class="text-gray-500">
                        <svg class="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
                        </svg>
                    </button>
                </div>

                <livewire:vps-health-monitor :vps="$vps" />
            </div>
        </div>
    </div>
</div>
```

### Example 4: API Controller Integration

```php
// app/Http/Controllers/VpsHealthController.php

namespace App\Http\Controllers;

use App\Models\VpsServer;
use Illuminate\Http\Request;

class VpsHealthController extends Controller
{
    public function show(VpsServer $vps)
    {
        $this->authorize('viewHealth', $vps);

        return view('vps.health-monitor', [
            'vps' => $vps,
            'breadcrumbs' => [
                ['label' => 'Dashboard', 'url' => route('dashboard')],
                ['label' => 'VPS Servers', 'url' => route('vps.index')],
                ['label' => $vps->hostname, 'url' => route('vps.show', $vps)],
                ['label' => 'Health Monitor', 'url' => null],
            ],
        ]);
    }

    public function index()
    {
        $this->authorize('viewAny', VpsServer::class);

        $vpsServers = VpsServer::where('status', 'active')
            ->orderBy('hostname')
            ->get();

        return view('vps.health-index', [
            'vpsServers' => $vpsServers,
        ]);
    }
}
```

### Example 5: With Layout Integration

```blade
<!-- resources/views/vps/health-monitor.blade.php -->

@extends('layouts.app')

@section('title', 'VPS Health Monitor - ' . $vps->hostname)

@section('content')
    <div class="container mx-auto px-4 py-8">
        <!-- Breadcrumbs -->
        <nav class="mb-6 text-sm">
            <a href="{{ route('dashboard') }}" class="text-blue-600 hover:text-blue-800">Dashboard</a>
            <span class="mx-2 text-gray-400">/</span>
            <a href="{{ route('vps.index') }}" class="text-blue-600 hover:text-blue-800">VPS Servers</a>
            <span class="mx-2 text-gray-400">/</span>
            <span class="text-gray-600">{{ $vps->hostname }}</span>
        </nav>

        <!-- Health Monitor -->
        <livewire:vps-health-monitor :vps="$vps" />
    </div>
@endsection

@push('scripts')
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
@endpush
```

## Testing Integration

### Example Test for Route

```php
// tests/Feature/VpsHealthMonitorIntegrationTest.php

namespace Tests\Feature;

use App\Models\User;
use App\Models\VpsServer;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class VpsHealthMonitorIntegrationTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function authenticated_user_can_view_vps_health_monitor()
    {
        $user = User::factory()->create(['role' => 'member']);
        $vps = VpsServer::factory()->create();

        $response = $this->actingAs($user)
            ->get(route('vps.health', $vps));

        $response->assertStatus(200);
        $response->assertSeeLivewire(VpsHealthMonitor::class);
    }

    /** @test */
    public function guest_cannot_view_vps_health_monitor()
    {
        $vps = VpsServer::factory()->create();

        $response = $this->get(route('vps.health', $vps));

        $response->assertRedirect(route('login'));
    }
}
```

## API Mock Server Example

For development/testing, create a mock API controller:

```php
// app/Http/Controllers/Api/V1/VpsHealthApiController.php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\VpsServer;
use Illuminate\Http\JsonResponse;

class VpsHealthApiController extends Controller
{
    public function health(VpsServer $vps): JsonResponse
    {
        return response()->json([
            'status' => 'healthy',
            'services' => [
                'nginx' => true,
                'php-fpm' => true,
                'mariadb' => true,
                'redis' => true,
            ],
            'resources' => [
                'cpu_percent' => rand(20, 80),
                'memory_percent' => rand(40, 85),
                'disk_percent' => rand(30, 70),
                'load_average' => [
                    round(rand(0, 200) / 100, 2),
                    round(rand(0, 200) / 100, 2),
                    round(rand(0, 200) / 100, 2),
                ],
            ],
            'uptime_seconds' => 3888000,
            'sites_count' => $vps->sites()->count(),
        ]);
    }

    public function stats(VpsServer $vps): JsonResponse
    {
        $cpuUsage = [];
        $memoryUsage = [];

        for ($i = 0; $i < 24; $i++) {
            $hour = str_pad($i, 2, '0', STR_PAD_LEFT) . ':00';
            $cpuUsage[$hour] = rand(20, 80);
            $memoryUsage[$hour] = rand(40, 85);
        }

        return response()->json([
            'cpu_usage' => $cpuUsage,
            'memory_usage' => $memoryUsage,
            'disk_io' => [
                'read' => rand(100, 1000) . ' MB/s',
                'write' => rand(50, 500) . ' MB/s',
                'iops' => rand(500, 2000),
            ],
            'network' => [
                'inbound' => round(rand(100, 5000) / 1000, 1) . ' GB',
                'outbound' => round(rand(50, 3000) / 1000, 1) . ' GB',
                'connections' => rand(100, 1000),
            ],
        ]);
    }
}
```

Add mock routes in `routes/api.php`:

```php
Route::prefix('v1')->middleware(['auth:sanctum'])->group(function () {
    Route::get('/vps/{vps}/health', [VpsHealthApiController::class, 'health']);
    Route::get('/vps/{vps}/stats', [VpsHealthApiController::class, 'stats']);
});
```

## Troubleshooting Common Integration Issues

### Issue 1: Livewire Scripts Not Loading

**Solution**: Ensure layout includes Livewire scripts:

```blade
<!DOCTYPE html>
<html>
<head>
    @livewireStyles
</head>
<body>
    {{ $slot }}

    @livewireScripts
</body>
</html>
```

### Issue 2: Charts Not Rendering

**Solution**: Load Chart.js before Livewire scripts:

```blade
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
@livewireScripts
```

### Issue 3: API 401 Unauthorized

**Solution**: Check API token configuration:

```php
// In .env
SERVICES_API_TOKEN=your-token-here

// Test token
dd(config('services.api.token'));
```

### Issue 4: Multiple Components on Same Page

**Solution**: Add unique wire:key to each component:

```blade
@foreach($vpsServers as $vps)
    <livewire:vps-health-monitor
        :vps="$vps"
        wire:key="vps-health-{{ $vps->id }}" />
@endforeach
```

## Performance Tips

1. **Use API Caching**: Cache API responses for 30-60 seconds
2. **Limit Concurrent Components**: Show max 3-4 monitors per page
3. **Adjust Refresh Intervals**: Use longer intervals for low-priority VPS
4. **Lazy Load Charts**: Load Chart.js only when needed
5. **Use Production Assets**: Compile Tailwind CSS for production

## Next Steps

1. Implement API endpoints on your VPS management system
2. Configure authentication and authorization
3. Customize styling to match your brand
4. Add custom alerts and notifications
5. Integrate with monitoring systems (Prometheus, Grafana)
6. Deploy to production with proper caching

## Support

For integration help, refer to:
- [VPS_HEALTH_MONITOR.md](./VPS_HEALTH_MONITOR.md) - Main documentation
- Laravel Livewire docs: https://livewire.laravel.com
- Tailwind CSS docs: https://tailwindcss.com
