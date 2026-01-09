# Health Endpoint Fix - Deployment Guide

## Issue Summary
**Priority**: P2 HIGH
**Problem**: Blackbox monitoring shows https://chom.arewel.com/health endpoint returns failure (probe_success=0)
**Root Cause**: The /health endpoint was only available at /api/v1/health/, but blackbox monitoring was checking /health at the root level

## Solution Implemented
Added a public `/health` endpoint at the root level in `routes/web.php` that:
- Returns 200 OK when database is healthy
- Returns 503 Service Unavailable when database check fails
- Includes JSON response with status, timestamp, and check results
- No authentication required (public endpoint for monitoring)
- Tests database connectivity with a simple query

## Commit Information
- Commit: 1581d1eb28115d09419a16dc2d3f1802bb686b19
- Branch: main
- File Changed: routes/web.php
- Lines Added: 37

## Deployment Instructions

### Option 1: Using Git Pull (Recommended)

1. SSH to the production server (landsraad.arewel.com):
   ```bash
   ssh stilgar@landsraad.arewel.com
   ```

2. Navigate to the application directory:
   ```bash
   cd /var/www/chom
   ```

3. Pull the latest changes:
   ```bash
   git fetch origin
   git pull origin main
   ```

4. Clear Laravel caches:
   ```bash
   php artisan route:clear
   php artisan cache:clear
   php artisan config:clear
   ```

5. Verify the route is registered:
   ```bash
   php artisan route:list --path=health
   ```

### Option 2: Using Deployment Script

Run the automated deployment script from mentat server:
```bash
cd /home/calounx/repositories/mentat/deploy
./deploy-chom.sh --environment=production --branch=main
```

### Option 3: Manual File Update (If git pull fails)

1. SSH to production server
2. Backup current routes file:
   ```bash
   cp /var/www/chom/routes/web.php /var/www/chom/routes/web.php.backup
   ```

3. Edit the routes file:
   ```bash
   nano /var/www/chom/routes/web.php
   ```

4. Add the health check endpoint after the imports section and before the Stripe webhook route:
   ```php
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
   ```

5. Ensure the DB facade is imported at the top of the file:
   ```php
   use Illuminate\Support\Facades\DB;
   ```

6. Clear caches:
   ```bash
   php artisan route:clear
   php artisan cache:clear
   php artisan config:clear
   ```

## Testing Instructions

### 1. Test the endpoint directly:
```bash
curl https://chom.arewel.com/health
```

**Expected Response (when healthy):**
```json
{
  "status": "healthy",
  "timestamp": "2026-01-09T12:23:00+00:00",
  "checks": {
    "database": true
  }
}
```

**Expected HTTP Status**: 200 OK

### 2. Test with verbose output:
```bash
curl -v https://chom.arewel.com/health
```

### 3. Verify Prometheus Blackbox Monitoring:

Wait 1-2 minutes for the next scrape, then check:

#### From Grafana (https://mentat.arewel.com/grafana):
- Navigate to Blackbox Exporter dashboard
- Find the `chom.arewel.com/health` probe
- Verify `probe_success` metric changes from 0 to 1

#### From Prometheus (https://mentat.arewel.com/prometheus):
Query:
```promql
probe_success{instance="https://chom.arewel.com/health"}
```
Expected result: 1 (success)

#### Direct Blackbox Exporter Test:
```bash
curl -s 'https://mentat.arewel.com/blackbox/probe?module=http_2xx&target=https://chom.arewel.com/health' | grep probe_success
```

Expected output:
```
probe_success 1
```

### 4. Test failure scenario (optional):

To verify the endpoint correctly reports unhealthy status when database is down:
```bash
# Temporarily stop PostgreSQL
sudo systemctl stop postgresql

# Test endpoint
curl https://chom.arewel.com/health

# Should return 503 with:
# {"status":"unhealthy","timestamp":"...","checks":{"database":false}}

# Restart PostgreSQL
sudo systemctl start postgresql
```

## Rollback Instructions

If issues occur after deployment:

### Quick Rollback:
```bash
cd /var/www/chom
git checkout HEAD~1 routes/web.php
php artisan route:clear
php artisan cache:clear
```

### Full Rollback:
```bash
cd /var/www/chom
git reset --hard HEAD~1
php artisan route:clear
php artisan cache:clear
php artisan config:clear
```

## Verification Checklist

- [ ] Endpoint returns 200 OK with JSON response
- [ ] Response includes "status": "healthy"
- [ ] Response includes timestamp
- [ ] Response includes database check result
- [ ] Prometheus shows probe_success=1 for chom.arewel.com/health
- [ ] No authentication required (public access)
- [ ] Endpoint responds within 5 seconds
- [ ] Laravel route cache cleared
- [ ] Monitoring alert resolved

## Related Routes

The application also has these health check endpoints:
- `/health` - Simple public health check (NEW - this fix)
- `/api/v1/health/` - Detailed API health check
- `/api/v1/health/liveness` - Kubernetes-style liveness probe
- `/api/v1/health/readiness` - Kubernetes-style readiness probe

## Security Notes

- This endpoint is intentionally public (no authentication)
- It only reveals basic health status (healthy/unhealthy)
- Database check uses a simple connection test, no sensitive data exposed
- The endpoint is designed for external monitoring tools
- Rate limiting is not applied to avoid false negatives in monitoring

## Monitoring Configuration

If blackbox monitoring configuration needs updating:

### Prometheus blackbox_exporter config:
```yaml
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200]
      method: GET
      fail_if_not_ssl: true
      preferred_ip_protocol: ip4
```

### Prometheus scrape config:
```yaml
- job_name: 'blackbox-chom'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - https://chom.arewel.com/health
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: mentat.arewel.com:9115
```

## Contact

For issues or questions:
- Check Laravel logs: `/var/www/chom/storage/logs/laravel.log`
- Check Nginx logs: `/var/log/nginx/chom-error.log`
- Check PHP-FPM logs: `/var/log/php8.2-fpm.log`
