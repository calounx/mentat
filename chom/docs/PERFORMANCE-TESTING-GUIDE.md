# CHOM Performance Testing Guide

## Overview

This guide provides load testing strategies, benchmarking tools, and performance validation for the CHOM platform.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Baseline Performance Metrics](#baseline-performance-metrics)
3. [Load Testing Tools](#load-testing-tools)
4. [Test Scenarios](#test-scenarios)
5. [Benchmarking Scripts](#benchmarking-scripts)
6. [Metrics Collection](#metrics-collection)
7. [Performance Regression Testing](#performance-regression-testing)

---

## Prerequisites

### Install Testing Tools

```bash
# Install Apache Bench (ab)
sudo apt-get install apache2-utils

# Install wrk (modern HTTP benchmarking tool)
sudo apt-get install wrk

# Install Laravel Dusk for browser testing
composer require --dev laravel/dusk
php artisan dusk:install

# Install k6 for advanced load testing
curl -L https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz | tar xvz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
```

---

## Baseline Performance Metrics

### Record Current Performance

**File:** `tests/Performance/BaselineTest.php`

```php
<?php

namespace Tests\Performance;

use Tests\TestCase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use App\Models\User;
use App\Models\Tenant;
use App\Models\Site;

class BaselineTest extends TestCase
{
    /**
     * Measure database query performance
     */
    public function test_database_query_baseline()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $user->organization_id]);
        Site::factory()->count(100)->create(['tenant_id' => $tenant->id]);

        // Measure site list query
        $start = microtime(true);
        DB::enableQueryLog();

        $sites = Site::where('tenant_id', $tenant->id)
            ->with('vpsServer')
            ->get();

        $queries = DB::getQueryLog();
        $duration = (microtime(true) - $start) * 1000;

        $this->assertLessThan(200, $duration, "Site list query took {$duration}ms (target: <200ms)");
        $this->assertLessThanOrEqual(2, count($queries), "Expected <=2 queries, got " . count($queries));

        dump([
            'test' => 'site_list_query',
            'duration_ms' => round($duration, 2),
            'query_count' => count($queries),
            'result_count' => $sites->count(),
        ]);
    }

    /**
     * Measure cache performance
     */
    public function test_cache_performance_baseline()
    {
        $key = 'test_key';
        $value = str_repeat('x', 10000); // 10KB value

        // Write performance
        $start = microtime(true);
        Cache::put($key, $value, 60);
        $write_duration = (microtime(true) - $start) * 1000;

        // Read performance
        $start = microtime(true);
        $result = Cache::get($key);
        $read_duration = (microtime(true) - $start) * 1000;

        $cache_driver = config('cache.default');

        dump([
            'test' => 'cache_performance',
            'driver' => $cache_driver,
            'write_ms' => round($write_duration, 2),
            'read_ms' => round($read_duration, 2),
        ]);

        // Redis should be <1ms, database cache <50ms
        if ($cache_driver === 'redis') {
            $this->assertLessThan(1, $write_duration);
            $this->assertLessThan(1, $read_duration);
        } else {
            $this->assertLessThan(50, $write_duration);
            $this->assertLessThan(50, $read_duration);
        }
    }

    /**
     * Measure API endpoint performance
     */
    public function test_api_endpoint_baseline()
    {
        $user = User::factory()->create();
        $this->actingAs($user, 'sanctum');

        $start = microtime(true);
        $response = $this->getJson('/api/v1/sites');
        $duration = (microtime(true) - $start) * 1000;

        $response->assertStatus(200);

        dump([
            'test' => 'api_sites_list',
            'duration_ms' => round($duration, 2),
            'status' => $response->status(),
        ]);

        $this->assertLessThan(200, $duration, "API endpoint took {$duration}ms (target: <200ms)");
    }
}
```

**Run Baseline Tests:**
```bash
php artisan test --filter=BaselineTest
```

---

## Load Testing Tools

### 1. Apache Bench (Simple HTTP Testing)

**Test Dashboard Endpoint:**
```bash
# 1000 requests, 10 concurrent
ab -n 1000 -c 10 http://localhost:8000/dashboard

# With authentication (get token first)
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}' \
  | jq -r '.data.token')

ab -n 1000 -c 10 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v1/sites
```

### 2. wrk (Advanced HTTP Benchmarking)

**Create wrk script:** `tests/Performance/load-test.lua`

```lua
-- Load testing script for CHOM API

-- Get auth token
token = ""

setup = function(thread)
   thread:set("token", token)
end

init = function(args)
   -- Login and get token
   local method = "POST"
   local path = "/api/v1/auth/login"
   local headers = {
      ["Content-Type"] = "application/json"
   }
   local body = '{"email":"admin@example.com","password":"password"}'

   return wrk.format(method, path, headers, body)
end

request = function()
   local headers = {
      ["Authorization"] = "Bearer " .. token,
      ["Content-Type"] = "application/json"
   }
   return wrk.format("GET", "/api/v1/sites", headers, nil)
end

response = function(status, headers, body)
   -- Extract token from login response
   if status == 200 and token == "" then
      local json = require("json")
      local data = json.decode(body)
      if data.data and data.data.token then
         token = data.data.token
      end
   end
end

done = function(summary, latency, requests)
   io.write("------------------------------\n")
   io.write(string.format("Requests/sec: %.2f\n", summary.requests / summary.duration * 1e6))
   io.write(string.format("Transfer/sec: %s\n", format_bytes(summary.bytes / summary.duration * 1e6)))
   io.write(string.format("Avg latency: %.2fms\n", latency.mean / 1000))
   io.write(string.format("Max latency: %.2fms\n", latency.max / 1000))
   io.write(string.format("Requests: %d\n", summary.requests))
   io.write(string.format("Errors: %d\n", summary.errors.connect + summary.errors.read + summary.errors.write + summary.errors.status + summary.errors.timeout))
end

function format_bytes(bytes)
   if bytes < 1024 then
      return string.format("%.2fB", bytes)
   elseif bytes < 1048576 then
      return string.format("%.2fKB", bytes / 1024)
   else
      return string.format("%.2fMB", bytes / 1048576)
   end
end
```

**Run wrk test:**
```bash
# 10 threads, 100 connections, 30 seconds
wrk -t10 -c100 -d30s \
  -s tests/Performance/load-test.lua \
  http://localhost:8000
```

### 3. k6 (Modern Load Testing)

**Create k6 script:** `tests/Performance/k6-load-test.js`

```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  stages: [
    { duration: '2m', target: 50 },  // Ramp up to 50 users
    { duration: '5m', target: 50 },  // Stay at 50 users
    { duration: '2m', target: 100 }, // Ramp up to 100 users
    { duration: '5m', target: 100 }, // Stay at 100 users
    { duration: '2m', target: 0 },   // Ramp down to 0 users
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500'],  // 95% of requests must complete below 500ms
    'errors': ['rate<0.1'],              // Error rate must be below 10%
  },
};

const BASE_URL = 'http://localhost:8000';
let authToken = '';

export function setup() {
  // Login once to get auth token
  const loginRes = http.post(`${BASE_URL}/api/v1/auth/login`, JSON.stringify({
    email: 'admin@example.com',
    password: 'password',
  }), {
    headers: { 'Content-Type': 'application/json' },
  });

  check(loginRes, {
    'login successful': (r) => r.status === 200,
  });

  const authToken = JSON.parse(loginRes.body).data.token;
  return { authToken };
}

export default function(data) {
  const params = {
    headers: {
      'Authorization': `Bearer ${data.authToken}`,
      'Content-Type': 'application/json',
    },
  };

  // Test 1: List sites
  let res = http.get(`${BASE_URL}/api/v1/sites`, params);
  check(res, {
    'list sites status 200': (r) => r.status === 200,
    'list sites duration < 200ms': (r) => r.timings.duration < 200,
  }) || errorRate.add(1);

  sleep(1);

  // Test 2: Get site details
  const sites = JSON.parse(res.body).data;
  if (sites && sites.length > 0) {
    res = http.get(`${BASE_URL}/api/v1/sites/${sites[0].id}`, params);
    check(res, {
      'get site status 200': (r) => r.status === 200,
      'get site duration < 150ms': (r) => r.timings.duration < 150,
    }) || errorRate.add(1);
  }

  sleep(1);

  // Test 3: Dashboard
  res = http.get(`${BASE_URL}/dashboard`, params);
  check(res, {
    'dashboard status 200': (r) => r.status === 200,
    'dashboard duration < 300ms': (r) => r.timings.duration < 300,
  }) || errorRate.add(1);

  sleep(2);
}

export function teardown(data) {
  // Logout
  http.post(`${BASE_URL}/api/v1/auth/logout`, null, {
    headers: {
      'Authorization': `Bearer ${data.authToken}`,
    },
  });
}
```

**Run k6 test:**
```bash
k6 run tests/Performance/k6-load-test.js

# With output to InfluxDB (for Grafana visualization)
k6 run --out influxdb=http://localhost:8086/k6 tests/Performance/k6-load-test.js
```

---

## Test Scenarios

### Scenario 1: Dashboard Load Test

**Goal:** Measure dashboard performance under load

```bash
#!/bin/bash
# tests/Performance/dashboard-load-test.sh

echo "=== Dashboard Load Test ==="

# Get auth token
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}' \
  | jq -r '.data.token')

echo "Testing with cache warming..."
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8000/dashboard > /dev/null

echo "Running load test (1000 requests, 10 concurrent)..."
ab -n 1000 -c 10 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/dashboard \
  | grep -E "Requests per second|Time per request|Transfer rate"

echo ""
echo "Testing with cold cache..."
php artisan cache:clear

ab -n 100 -c 10 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/dashboard \
  | grep -E "Requests per second|Time per request"
```

### Scenario 2: API Stress Test

**Goal:** Test API under heavy concurrent load

```bash
#!/bin/bash
# tests/Performance/api-stress-test.sh

echo "=== API Stress Test ==="

TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}' \
  | jq -r '.data.token')

# Test different concurrency levels
for CONCURRENCY in 10 25 50 100 200; do
  echo ""
  echo "Testing with $CONCURRENCY concurrent users..."

  ab -n 1000 -c $CONCURRENCY \
    -H "Authorization: Bearer $TOKEN" \
    http://localhost:8000/api/v1/sites \
    | grep -E "Requests per second|Failed requests|Time per request"

  sleep 5
done
```

### Scenario 3: Metrics Dashboard Load Test

**Goal:** Test Prometheus query performance under load

```bash
#!/bin/bash
# tests/Performance/metrics-load-test.sh

echo "=== Metrics Dashboard Load Test ==="

TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}' \
  | jq -r '.data.token')

echo "Testing metrics dashboard (sequential queries)..."
time curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/observability/metrics > /dev/null

echo ""
echo "Load testing (100 requests, 5 concurrent)..."
ab -n 100 -c 5 \
  -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/observability/metrics \
  | grep -E "Requests per second|Time per request|Failed requests"
```

### Scenario 4: Database Query Performance

**Create test:** `tests/Performance/DatabasePerformanceTest.php`

```php
<?php

namespace Tests\Performance;

use Tests\TestCase;
use Illuminate\Support\Facades\DB;
use App\Models\{User, Tenant, Site, SiteBackup};

class DatabasePerformanceTest extends TestCase
{
    public function test_n_plus_one_queries()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $user->organization_id]);
        Site::factory()->count(50)->create(['tenant_id' => $tenant->id]);

        DB::enableQueryLog();

        // Test for N+1 queries
        $sites = Site::where('tenant_id', $tenant->id)->get();

        foreach ($sites as $site) {
            // This would trigger N+1 without eager loading
            $vps = $site->vpsServer;
        }

        $queries = DB::getQueryLog();

        // With eager loading: should be 1 query
        // Without eager loading: should be 51 queries (1 + 50)
        $this->assertLessThanOrEqual(2, count($queries),
            "N+1 query detected! Expected <=2 queries, got " . count($queries)
        );
    }

    public function test_large_dataset_pagination()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $user->organization_id]);
        Site::factory()->count(1000)->create(['tenant_id' => $tenant->id]);

        $start = microtime(true);
        DB::enableQueryLog();

        $sites = Site::where('tenant_id', $tenant->id)
            ->with('vpsServer')
            ->paginate(20);

        $queries = DB::getQueryLog();
        $duration = (microtime(true) - $start) * 1000;

        dump([
            'test' => 'large_dataset_pagination',
            'total_records' => 1000,
            'page_size' => 20,
            'duration_ms' => round($duration, 2),
            'query_count' => count($queries),
        ]);

        // With proper indexes: <100ms
        $this->assertLessThan(100, $duration);
        $this->assertLessThanOrEqual(3, count($queries));
    }

    public function test_complex_aggregation_query()
    {
        $user = User::factory()->create();
        $tenant = Tenant::factory()->create(['organization_id' => $user->organization_id]);
        Site::factory()->count(200)->create(['tenant_id' => $tenant->id]);

        $start = microtime(true);

        // Complex aggregation (like dashboard stats)
        $stats = DB::table('sites')
            ->where('tenant_id', $tenant->id)
            ->selectRaw('
                COUNT(*) as total_sites,
                SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) as active_sites,
                SUM(storage_used_mb) as total_storage_mb
            ', ['active'])
            ->first();

        $duration = (microtime(true) - $start) * 1000;

        dump([
            'test' => 'complex_aggregation',
            'record_count' => 200,
            'duration_ms' => round($duration, 2),
        ]);

        // With proper indexes: <50ms
        $this->assertLessThan(50, $duration);
    }
}
```

---

## Benchmarking Scripts

### Complete Performance Test Suite

**File:** `tests/Performance/run-all-tests.sh`

```bash
#!/bin/bash

# CHOM Complete Performance Test Suite
# This script runs all performance tests and generates a report

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         CHOM Performance Test Suite                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Configuration
BASE_URL="http://localhost:8000"
API_URL="$BASE_URL/api/v1"
RESULTS_DIR="tests/Performance/results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="$RESULTS_DIR/report_$TIMESTAMP.txt"

# Create results directory
mkdir -p $RESULTS_DIR

# Start report
echo "Performance Test Report - $TIMESTAMP" > $REPORT_FILE
echo "========================================" >> $REPORT_FILE
echo "" >> $REPORT_FILE

# Get auth token
echo "→ Authenticating..."
TOKEN=$(curl -s -X POST $API_URL/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@example.com","password":"password"}' \
  | jq -r '.data.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "✗ Authentication failed!"
  exit 1
fi

echo "✓ Authentication successful"
echo ""

# Test 1: Cache Performance
echo "TEST 1: Cache Performance"
echo "========================" >> $REPORT_FILE

php artisan tinker <<EOF >> $REPORT_FILE
\$start = microtime(true);
Cache::put('perf_test', str_repeat('x', 10000), 60);
\$write = (microtime(true) - \$start) * 1000;

\$start = microtime(true);
\$val = Cache::get('perf_test');
\$read = (microtime(true) - \$start) * 1000;

echo "Cache Driver: " . config('cache.default') . "\n";
echo "Write Time: " . round(\$write, 2) . "ms\n";
echo "Read Time: " . round(\$read, 2) . "ms\n";
EOF

echo "" >> $REPORT_FILE

# Test 2: Dashboard Performance
echo "TEST 2: Dashboard Performance"
echo "============================" >> $REPORT_FILE

echo "→ Warming cache..."
curl -s -H "Authorization: Bearer $TOKEN" $BASE_URL/dashboard > /dev/null

echo "→ Testing with warm cache..."
ab -n 100 -c 10 -q \
  -H "Authorization: Bearer $TOKEN" \
  $BASE_URL/dashboard \
  >> $REPORT_FILE 2>&1

echo "" >> $REPORT_FILE

# Test 3: API Performance
echo "TEST 3: API Endpoint Performance"
echo "================================" >> $REPORT_FILE

for ENDPOINT in "sites" "backups"; do
  echo "→ Testing /api/v1/$ENDPOINT"
  echo "" >> $REPORT_FILE
  echo "Endpoint: /api/v1/$ENDPOINT" >> $REPORT_FILE

  ab -n 200 -c 20 -q \
    -H "Authorization: Bearer $TOKEN" \
    $API_URL/$ENDPOINT \
    >> $REPORT_FILE 2>&1

  echo "" >> $REPORT_FILE
done

# Test 4: Database Performance
echo "TEST 4: Database Query Performance"
echo "==================================" >> $REPORT_FILE

php artisan test --filter=DatabasePerformanceTest >> $REPORT_FILE 2>&1

echo "" >> $REPORT_FILE

# Test 5: Stress Test (increasing load)
echo "TEST 5: Stress Test (Increasing Concurrency)"
echo "============================================" >> $REPORT_FILE

for CONCURRENCY in 10 25 50 100; do
  echo "→ Testing with $CONCURRENCY concurrent users..."
  echo "Concurrency: $CONCURRENCY users" >> $REPORT_FILE

  ab -n 500 -c $CONCURRENCY -q \
    -H "Authorization: Bearer $TOKEN" \
    $API_URL/sites \
    >> $REPORT_FILE 2>&1

  echo "" >> $REPORT_FILE
  sleep 2
done

# Generate summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Test Summary                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Extract key metrics from report
echo "Dashboard Performance:"
grep "Requests per second" $REPORT_FILE | head -1

echo ""
echo "API Performance:"
grep "Requests per second" $REPORT_FILE | tail -5 | head -2

echo ""
echo "Full report saved to: $REPORT_FILE"
echo ""
echo "✓ All performance tests completed!"
```

**Run all tests:**
```bash
chmod +x tests/Performance/run-all-tests.sh
./tests/Performance/run-all-tests.sh
```

---

## Metrics Collection

### Monitor Performance Metrics During Tests

**Create monitoring script:** `tests/Performance/monitor-metrics.sh`

```bash
#!/bin/bash

# Monitor system metrics during performance tests

DURATION=${1:-60}  # Default 60 seconds
INTERVAL=1

echo "Monitoring system metrics for ${DURATION} seconds..."
echo "timestamp,cpu_percent,mem_percent,disk_io,network_rx,network_tx" > metrics.csv

for i in $(seq 1 $DURATION); do
  TIMESTAMP=$(date +%s)

  # CPU usage
  CPU=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

  # Memory usage
  MEM=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')

  # Disk I/O (reads + writes)
  DISK=$(iostat -d -x 1 2 | tail -1 | awk '{print $4 + $5}')

  # Network (bytes received + transmitted)
  NET_RX=$(cat /sys/class/net/eth0/statistics/rx_bytes 2>/dev/null || echo 0)
  NET_TX=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null || echo 0)

  echo "$TIMESTAMP,$CPU,$MEM,$DISK,$NET_RX,$NET_TX" >> metrics.csv

  sleep $INTERVAL
done

echo "Metrics saved to metrics.csv"
```

### Visualize Metrics

**Python script to plot metrics:** `tests/Performance/plot-metrics.py`

```python
#!/usr/bin/env python3

import pandas as pd
import matplotlib.pyplot as plt
import sys

if len(sys.argv) < 2:
    print("Usage: ./plot-metrics.py metrics.csv")
    sys.exit(1)

# Read metrics
df = pd.read_csv(sys.argv[1])
df['timestamp'] = pd.to_datetime(df['timestamp'], unit='s')

# Create subplots
fig, axes = plt.subplots(2, 2, figsize=(15, 10))
fig.suptitle('Performance Monitoring', fontsize=16)

# CPU
axes[0, 0].plot(df['timestamp'], df['cpu_percent'], color='blue')
axes[0, 0].set_title('CPU Usage')
axes[0, 0].set_ylabel('CPU %')
axes[0, 0].grid(True)

# Memory
axes[0, 1].plot(df['timestamp'], df['mem_percent'], color='green')
axes[0, 1].set_title('Memory Usage')
axes[0, 1].set_ylabel('Memory %')
axes[0, 1].grid(True)

# Disk I/O
axes[1, 0].plot(df['timestamp'], df['disk_io'], color='red')
axes[1, 0].set_title('Disk I/O')
axes[1, 0].set_ylabel('I/O Operations')
axes[1, 0].grid(True)

# Network
axes[1, 1].plot(df['timestamp'], df['network_rx'], label='RX', color='purple')
axes[1, 1].plot(df['timestamp'], df['network_tx'], label='TX', color='orange')
axes[1, 1].set_title('Network Traffic')
axes[1, 1].set_ylabel('Bytes')
axes[1, 1].legend()
axes[1, 1].grid(True)

plt.tight_layout()
plt.savefig('performance-metrics.png')
print("Chart saved to performance-metrics.png")
```

---

## Performance Regression Testing

### Automated Performance CI/CD

**File:** `.github/workflows/performance.yml`

```yaml
name: Performance Tests

on:
  pull_request:
    branches: [ main, develop ]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM

jobs:
  performance:
    runs-on: ubuntu-latest

    services:
      redis:
        image: redis:7-alpine
        ports:
          - 6379:6379

      mysql:
        image: mysql:8.0
        env:
          MYSQL_ROOT_PASSWORD: password
          MYSQL_DATABASE: chom_test
        ports:
          - 3306:3306

    steps:
    - uses: actions/checkout@v3

    - name: Setup PHP
      uses: shivammathur/setup-php@v2
      with:
        php-version: 8.2
        extensions: redis, pdo_mysql

    - name: Install Dependencies
      run: |
        composer install --no-interaction --prefer-dist
        npm install

    - name: Setup Environment
      run: |
        cp .env.example .env
        php artisan key:generate
        php artisan migrate --force

    - name: Seed Test Data
      run: php artisan db:seed --force

    - name: Run Performance Tests
      run: |
        php artisan test --filter=Performance
        php artisan test --filter=Baseline

    - name: Upload Results
      uses: actions/upload-artifact@v3
      with:
        name: performance-results
        path: tests/Performance/results/
```

### Compare Performance Between Versions

**Script:** `tests/Performance/compare-versions.sh`

```bash
#!/bin/bash

# Compare performance between two git branches

BRANCH1=${1:-main}
BRANCH2=${2:-develop}

echo "Comparing performance: $BRANCH1 vs $BRANCH2"

# Test branch 1
git checkout $BRANCH1
composer install --quiet
php artisan migrate:fresh --force --quiet
php artisan db:seed --quiet

echo "Testing $BRANCH1..."
php artisan test --filter=BaselineTest > results_${BRANCH1}.txt 2>&1

# Test branch 2
git checkout $BRANCH2
composer install --quiet
php artisan migrate:fresh --force --quiet
php artisan db:seed --quiet

echo "Testing $BRANCH2..."
php artisan test --filter=BaselineTest > results_${BRANCH2}.txt 2>&1

# Compare results
echo ""
echo "Performance Comparison:"
echo "======================="
diff -y results_${BRANCH1}.txt results_${BRANCH2}.txt || true
```

---

## Performance Targets

### Target Metrics

| Metric | Target | Critical |
|--------|--------|----------|
| Dashboard load (warm cache) | <100ms | <200ms |
| Dashboard load (cold cache) | <300ms | <500ms |
| API list endpoints | <150ms | <300ms |
| API detail endpoints | <100ms | <200ms |
| Cache read (Redis) | <1ms | <5ms |
| Cache write (Redis) | <1ms | <5ms |
| Database query (indexed) | <20ms | <50ms |
| External API (Prometheus) | <100ms | <300ms |
| Queue job dispatch | <10ms | <50ms |

### Acceptance Criteria

Before deploying optimizations:

1. All baseline tests must pass
2. No performance regression >10%
3. Cache hit rate >80% after warmup
4. Database query count <10 per request
5. No N+1 queries detected
6. Error rate <1% under load
7. p95 latency <500ms for all endpoints

---

## Troubleshooting

### High Response Times

```bash
# Check slow queries
tail -f storage/logs/laravel.log | grep "Slow query"

# Monitor database
mysql -u root -p -e "SHOW PROCESSLIST;"

# Check cache hit rate
php artisan tinker
>>> Cache::getStore()->getRedis()->info('stats')
```

### Memory Issues

```bash
# Monitor PHP memory
php -r "echo ini_get('memory_limit') . PHP_EOL;"

# Check Laravel memory usage
php artisan tinker
>>> memory_get_peak_usage(true) / 1024 / 1024 . " MB"
```

### Queue Bottlenecks

```bash
# Monitor queue depth
php artisan queue:monitor

# Check failed jobs
php artisan queue:failed
```

---

## Next Steps

1. Run baseline tests before optimizations
2. Implement optimizations from implementation guide
3. Run tests again to measure improvements
4. Document results and update targets
5. Set up continuous performance monitoring
6. Integrate into CI/CD pipeline

