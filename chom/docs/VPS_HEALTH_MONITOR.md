# VPS Health Monitor Component

## Overview

The VPS Health Monitor is a Livewire 3 component that provides real-time monitoring of VPS infrastructure in the CHOM UI. It displays health metrics, statistics, alerts, and site information in a responsive dashboard layout.

## Features

- **Real-time Health Monitoring**: Displays VPS health status with color-coded indicators
- **Service Status**: Shows status of Nginx, PHP-FPM, MariaDB, and Redis services
- **Resource Monitoring**: Visual progress bars for CPU, Memory, and Disk usage
- **Load Average Display**: Shows system load average (1m, 5m, 15m)
- **Statistics Charts**: CPU and Memory usage trends over the last 24 hours
- **Disk I/O & Network Stats**: Displays read/write operations and network traffic
- **Alerts Panel**: Shows recent warnings and critical issues
- **Site Management**: Lists all sites on the VPS with SSL status
- **Auto-refresh**: Automatically polls data every 30 seconds
- **Export Functionality**: Export health reports as PDF or CSV

## Files Created

### Component
- `/app/Livewire/VpsHealthMonitor.php` - Main Livewire component class

### View
- `/resources/views/livewire/vps-health-monitor.blade.php` - Blade template with dashboard UI

### Policy
- `/app/Policies/VpsServerPolicy.php` - Authorization policy for VPS server access

### Tests
- `/tests/Unit/Livewire/VpsHealthMonitorTest.php` - Comprehensive unit tests (20 tests)

## Installation

1. Ensure Livewire 3 is installed:
```bash
composer require livewire/livewire
```

2. Ensure Alpine.js and Chart.js are available (loaded via CDN in the view)

3. Configure API credentials in `.env`:
```env
API_URL=https://api.example.com
API_TOKEN=your-api-token-here
```

4. Register the policy in `AuthServiceProvider`:
```php
use App\Models\VpsServer;
use App\Policies\VpsServerPolicy;

protected $policies = [
    VpsServer::class => VpsServerPolicy::class,
];
```

## Usage

### Basic Usage

Include the component in a Blade view:

```blade
<livewire:vps-health-monitor :vps="$vpsServer" />
```

### With Route

```php
Route::get('/vps/{vps}/health', function (VpsServer $vps) {
    return view('vps.health', ['vps' => $vps]);
})->middleware(['auth']);
```

### In Controller

```php
public function show(VpsServer $vps)
{
    $this->authorize('viewHealth', $vps);

    return view('vps.health', [
        'vps' => $vps,
    ]);
}
```

## Authorization

The component uses Laravel's policy system to control access:

- **viewHealth**: Member role or higher
- **viewStats**: Member role or higher
- **manage**: Admin role or higher

Users must have at least "member" role to view VPS health data.

## API Endpoints

The component expects these API endpoints to be available:

### Health Endpoint
```
GET /api/v1/vps/{id}/health
```

Response format:
```json
{
  "status": "healthy",
  "services": {
    "nginx": true,
    "php-fpm": true,
    "mariadb": true,
    "redis": true
  },
  "resources": {
    "cpu_percent": 34,
    "memory_percent": 62,
    "disk_percent": 48,
    "load_average": [1.2, 0.8, 0.6]
  },
  "uptime_seconds": 3888000,
  "sites_count": 12
}
```

### Statistics Endpoint
```
GET /api/v1/vps/{id}/stats
```

Response format:
```json
{
  "cpu_usage": {
    "00:00": 20,
    "06:00": 35,
    "12:00": 50,
    "18:00": 30
  },
  "memory_usage": {
    "00:00": 55,
    "06:00": 60,
    "12:00": 65,
    "18:00": 62
  },
  "disk_io": {
    "read": "500 MB/s",
    "write": "300 MB/s",
    "iops": 1500
  },
  "network": {
    "inbound": "1.2 GB",
    "outbound": "800 MB",
    "connections": 450
  }
}
```

## Component Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `$vpsId` | string | - | VPS server ID |
| `$vps` | VpsServer | - | VPS server model instance |
| `$healthData` | array\|null | null | Current health data from API |
| `$stats` | array\|null | null | Statistics data from API |
| `$refreshInterval` | int | 30 | Auto-refresh interval in seconds |
| `$processing` | bool | false | Loading state indicator |
| `$error` | string\|null | null | Error message if API call fails |

## Component Methods

### Public Methods

- `mount(VpsServer $vps)` - Initialize component with VPS server
- `loadHealth()` - Fetch health data from API
- `loadStats()` - Fetch statistics data from API
- `refresh()` - Manually refresh all data
- `exportPdf()` - Export health report as PDF
- `exportCsv()` - Export health report as CSV

### Computed Properties

- `getHealthStatusAttribute()` - Returns health status with color and icon
- `getSitesProperty()` - Returns sites on this VPS for current tenant
- `getAlertsProperty()` - Returns recent alerts based on health data

## Customization

### Change Refresh Interval

Set a custom refresh interval (in seconds):

```blade
<livewire:vps-health-monitor :vps="$vpsServer" :refreshInterval="60" />
```

### Custom Styling

The component uses Tailwind CSS 4. Override classes as needed:

```css
.vps-health-monitor {
  /* Custom styles */
}
```

### Health Status Thresholds

Modify warning/critical thresholds in the component:

```php
// In VpsHealthMonitor.php, modify getAlertsProperty()
if (($resources['disk_percent'] ?? 0) > 80) {  // Change threshold
    // Alert logic
}
```

## Color Coding

The component uses the following color scheme:

- **Green** (`text-green-500`): Healthy status, normal operations
- **Yellow** (`text-yellow-500`): Warning status, attention needed
- **Red** (`text-red-500`): Critical status, immediate action required
- **Gray** (`text-gray-500`): Unknown status or no data

## Responsive Design

The component is fully responsive:

- **Mobile (< 768px)**: Single column layout
- **Tablet (768px - 1024px)**: 2-column grid
- **Desktop (> 1024px)**: 3-column grid with expanded statistics

## Error Handling

The component gracefully handles errors:

1. **API Failures**: Displays error message in red alert box
2. **Network Timeouts**: 10-second timeout for HTTP requests
3. **Invalid Data**: Falls back to loading skeletons
4. **Authorization Errors**: Throws `AuthorizationException`

## Testing

Run the comprehensive test suite:

```bash
# Run all VPS Health Monitor tests
php artisan test --filter=VpsHealthMonitorTest

# Run specific test
php artisan test --filter=it_loads_health_data_from_api_successfully
```

The test suite includes 20+ tests covering:
- Authorization checks
- Data loading (success/failure)
- Health status computation
- Alert generation
- Export functionality
- View rendering
- Tenant isolation

## Performance Considerations

1. **Auto-refresh**: Set appropriate `refreshInterval` to balance real-time updates with server load
2. **API Caching**: Consider caching API responses for 30-60 seconds
3. **Lazy Loading**: Charts are loaded only when data is available
4. **Efficient Queries**: Sites query is scoped to current tenant only

## Troubleshooting

### Component Not Rendering

1. Check Livewire is properly installed: `composer show livewire/livewire`
2. Ensure Livewire scripts are included in layout: `@livewireScripts`
3. Verify API credentials in `.env`

### API Errors

1. Check API endpoint URLs in config
2. Verify API authentication token
3. Review Laravel logs: `tail -f storage/logs/laravel.log`

### Charts Not Displaying

1. Ensure Chart.js is loaded: Check browser console
2. Verify stats data structure matches expected format
3. Check for JavaScript errors in browser console

### Authorization Issues

1. Verify user has required role (minimum: member)
2. Check policy is registered in `AuthServiceProvider`
3. Ensure user has `current_tenant_id` set

## Production Checklist

Before deploying to production:

- [ ] Configure API credentials securely
- [ ] Set appropriate refresh interval for production load
- [ ] Implement proper error monitoring (Sentry, etc.)
- [ ] Configure API rate limiting
- [ ] Set up proper caching strategy
- [ ] Test all authorization scenarios
- [ ] Verify responsive design on mobile devices
- [ ] Test export functionality (PDF/CSV)
- [ ] Configure CORS if API is on different domain
- [ ] Implement proper logging for debugging

## Browser Support

- Chrome/Edge: Latest 2 versions
- Firefox: Latest 2 versions
- Safari: Latest 2 versions
- Mobile Safari: iOS 14+
- Chrome Mobile: Latest version

## Dependencies

- **Laravel**: 10.x or higher
- **Livewire**: 3.x
- **Tailwind CSS**: 4.x (via CDN or compiled)
- **Alpine.js**: 3.x (loaded via CDN)
- **Chart.js**: 4.x (loaded via CDN)

## License

This component is part of the CHOM project and follows the same license.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review test cases for usage examples
3. Consult Laravel Livewire documentation
4. Contact the development team

## Changelog

### Version 1.0.0 (2026-01-09)
- Initial release
- Real-time health monitoring
- Statistics visualization with Chart.js
- Export functionality (PDF/CSV)
- Comprehensive test coverage
- Responsive dashboard layout
