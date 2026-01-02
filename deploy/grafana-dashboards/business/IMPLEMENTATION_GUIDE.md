# Business Metrics Implementation Guide

This guide explains how to implement the metrics required for the CHOM Business Intelligence dashboards.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Metric Collection Strategy](#metric-collection-strategy)
3. [Implementation by Dashboard](#implementation-by-dashboard)
4. [Code Examples](#code-examples)
5. [Testing & Validation](#testing--validation)
6. [Performance Optimization](#performance-optimization)

---

## Architecture Overview

### Components

```
┌─────────────────┐
│  CHOM Platform  │
│   (Laravel)     │
└────────┬────────┘
         │
         │ Pushes Metrics
         ▼
┌─────────────────┐
│   Prometheus    │ ◄── Scrapes metrics
│   (Port 9090)   │
└────────┬────────┘
         │
         │ Queries
         ▼
┌─────────────────┐
│    Grafana      │
│   (Port 3000)   │
└─────────────────┘
```

### Metric Types

1. **Counter** - Monotonically increasing value (e.g., total sign-ups)
2. **Gauge** - Can go up or down (e.g., current MRR, active users)
3. **Histogram** - Distribution of values (e.g., response times)
4. **Summary** - Similar to histogram with percentiles

### Storage Strategy

- **Redis** - Fast, in-memory storage for real-time metrics
- **Prometheus** - Time-series database with data retention policies
- **PostgreSQL** - Source of truth for calculated metrics

---

## Metric Collection Strategy

### 1. Real-time vs Batch

**Real-time Metrics** (collected on event occurrence):
- User sign-ups
- Support ticket creation
- Feature usage
- API requests

**Batch Metrics** (calculated periodically):
- MRR (daily calculation)
- Customer health scores (hourly)
- Cohort retention (daily)
- Churn rate (daily)

### 2. Calculation Location

**Application-side** (Laravel):
- Simple event counts
- User actions
- Real-time state changes

**Database queries** (Scheduled jobs):
- Aggregated metrics
- Complex calculations
- Historical analysis

**Prometheus** (Recording rules):
- Derived metrics
- Rate calculations
- Aggregations across labels

---

## Implementation by Dashboard

### Dashboard 1: Business KPI Dashboard

#### Required Metrics

```php
// app/Services/MetricsService.php

namespace App\Services;

use Prometheus\CollectorRegistry;
use Prometheus\Storage\Redis;

class MetricsService
{
    private $registry;

    public function __construct()
    {
        $this->registry = new CollectorRegistry(new Redis([
            'host' => env('REDIS_HOST', '127.0.0.1'),
            'port' => env('REDIS_PORT', 6379),
            'database' => env('REDIS_METRICS_DB', 2),
        ]));
    }

    /**
     * Track Monthly Recurring Revenue
     */
    public function trackMRR()
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'revenue_mrr',
            'Monthly Recurring Revenue by tier',
            ['tier']
        );

        $tiers = ['starter', 'professional', 'enterprise'];

        foreach ($tiers as $tier) {
            $mrr = \DB::table('subscriptions')
                ->where('tier', $tier)
                ->where('status', 'active')
                ->sum('monthly_amount');

            $gauge->set($mrr, [$tier]);
        }
    }

    /**
     * Track total customers
     */
    public function trackCustomers()
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'customers_total',
            'Total active customers',
            []
        );

        $total = \DB::table('organizations')
            ->where('status', 'active')
            ->count();

        $gauge->set($total, []);
    }

    /**
     * Track new customer sign-ups (counter)
     */
    public function incrementNewCustomer()
    {
        $counter = $this->registry->getOrRegisterCounter(
            'chom',
            'customers_new_total',
            'Total new customers',
            []
        );

        $counter->inc([]);
    }

    /**
     * Track customer churn (counter)
     */
    public function incrementChurnedCustomer()
    {
        $counter = $this->registry->getOrRegisterCounter(
            'chom',
            'customers_churned_total',
            'Total churned customers',
            []
        );

        $counter->inc([]);
    }

    /**
     * Calculate and track churn rate
     */
    public function trackChurnRate()
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'churn_rate_monthly',
            'Monthly customer churn rate percentage',
            []
        );

        // Get customers churned in last 30 days
        $churned = \DB::table('organizations')
            ->where('status', 'churned')
            ->where('churned_at', '>=', now()->subDays(30))
            ->count();

        // Get total customers at start of period
        $totalAtStart = \DB::table('organizations')
            ->where('created_at', '<', now()->subDays(30))
            ->count();

        $churnRate = $totalAtStart > 0 ? ($churned / $totalAtStart) * 100 : 0;

        $gauge->set($churnRate, []);
    }

    /**
     * Track active users (DAU, WAU, MAU)
     */
    public function trackActiveUsers()
    {
        $gaugeDAU = $this->registry->getOrRegisterGauge(
            'chom',
            'users_active_daily',
            'Daily active users',
            []
        );

        $gaugeWAU = $this->registry->getOrRegisterGauge(
            'chom',
            'users_active_weekly',
            'Weekly active users',
            []
        );

        $gaugeMAU = $this->registry->getOrRegisterGauge(
            'chom',
            'users_active_monthly',
            'Monthly active users',
            []
        );

        $dau = \DB::table('user_activity')
            ->where('last_active_at', '>=', now()->subDay())
            ->distinct('user_id')
            ->count();

        $wau = \DB::table('user_activity')
            ->where('last_active_at', '>=', now()->subDays(7))
            ->distinct('user_id')
            ->count();

        $mau = \DB::table('user_activity')
            ->where('last_active_at', '>=', now()->subDays(30))
            ->distinct('user_id')
            ->count();

        $gaugeDAU->set($dau, []);
        $gaugeWAU->set($wau, []);
        $gaugeMAU->set($mau, []);
    }

    /**
     * Track conversion funnel metrics
     */
    public function trackFunnelMetrics()
    {
        $metrics = [
            'signups' => \DB::table('users')->count(),
            'activated' => \DB::table('users')->whereNotNull('activated_at')->count(),
            'trial_started' => \DB::table('users')->whereNotNull('trial_started_at')->count(),
            'paid' => \DB::table('subscriptions')->where('status', 'active')->count(),
        ];

        foreach ($metrics as $stage => $count) {
            $counter = $this->registry->getOrRegisterCounter(
                'chom',
                "funnel_{$stage}_total",
                "Total users in {$stage} stage",
                []
            );

            // Note: This sets the counter to the current value
            // For proper implementation, increment on events
        }
    }

    /**
     * Track marketing spend
     */
    public function trackMarketingSpend(string $period, float $amount)
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'marketing_spend_total',
            'Total marketing spend',
            ['period']
        );

        $gauge->set($amount, [$period]);
    }
}
```

#### Scheduled Jobs

```php
// app/Console/Kernel.php

protected function schedule(Schedule $schedule)
{
    // Update metrics every 5 minutes
    $schedule->call(function () {
        $metrics = app(MetricsService::class);
        $metrics->trackMRR();
        $metrics->trackCustomers();
        $metrics->trackActiveUsers();
        $metrics->trackChurnRate();
    })->everyFiveMinutes();

    // Update funnel metrics hourly
    $schedule->call(function () {
        $metrics = app(MetricsService::class);
        $metrics->trackFunnelMetrics();
    })->hourly();

    // Update marketing spend daily
    $schedule->call(function () {
        $metrics = app(MetricsService::class);

        // Calculate 7-day and 30-day spend
        $spend7d = \DB::table('marketing_expenses')
            ->where('date', '>=', now()->subDays(7))
            ->sum('amount');

        $spend30d = \DB::table('marketing_expenses')
            ->where('date', '>=', now()->subDays(30))
            ->sum('amount');

        $metrics->trackMarketingSpend('7d', $spend7d);
        $metrics->trackMarketingSpend('30d', $spend30d);
    })->daily();
}
```

### Dashboard 2: Customer Success Dashboard

#### Customer Health Score Calculation

```php
// app/Services/CustomerHealthService.php

namespace App\Services;

class CustomerHealthService
{
    /**
     * Calculate comprehensive customer health score (0-100)
     */
    public function calculateHealthScore($organization): float
    {
        $scores = [
            'usage' => $this->calculateUsageScore($organization),
            'adoption' => $this->calculateFeatureAdoptionScore($organization),
            'support' => $this->calculateSupportScore($organization),
            'payment' => $this->calculatePaymentScore($organization),
            'engagement' => $this->calculateEngagementScore($organization),
        ];

        $weights = [
            'usage' => 0.30,
            'adoption' => 0.25,
            'support' => 0.15,
            'payment' => 0.15,
            'engagement' => 0.15,
        ];

        $totalScore = 0;
        foreach ($scores as $metric => $score) {
            $totalScore += $score * $weights[$metric];
        }

        return round($totalScore, 2);
    }

    private function calculateUsageScore($organization): float
    {
        // Based on login frequency
        $logins = \DB::table('user_activity')
            ->whereIn('user_id', $organization->users->pluck('id'))
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        $expectedLogins = $organization->users->count() * 20; // 20 logins per user per month
        $score = min(($logins / $expectedLogins) * 100, 100);

        return $score;
    }

    private function calculateFeatureAdoptionScore($organization): float
    {
        $totalFeatures = 10; // Total available features
        $usedFeatures = \DB::table('feature_usage')
            ->where('organization_id', $organization->id)
            ->distinct('feature_name')
            ->count();

        return ($usedFeatures / $totalFeatures) * 100;
    }

    private function calculateSupportScore($organization): float
    {
        // Lower support tickets = higher score
        $tickets = \DB::table('support_tickets')
            ->where('organization_id', $organization->id)
            ->where('created_at', '>=', now()->subDays(30))
            ->count();

        // More than 5 tickets = 0, 0 tickets = 100
        $score = max(100 - ($tickets * 20), 0);

        return $score;
    }

    private function calculatePaymentScore($organization): float
    {
        // Check for payment failures
        $failures = \DB::table('payment_attempts')
            ->where('organization_id', $organization->id)
            ->where('status', 'failed')
            ->where('created_at', '>=', now()->subDays(90))
            ->count();

        return $failures === 0 ? 100 : max(100 - ($failures * 25), 0);
    }

    private function calculateEngagementScore($organization): float
    {
        // Based on various engagement signals
        $signals = [
            'team_members' => $organization->users->count() > 1 ? 20 : 0,
            'api_usage' => $organization->api_calls_count > 100 ? 20 : 0,
            'sites_managed' => min(($organization->sites_count / 10) * 20, 20),
            'backups_created' => $organization->backups_count > 0 ? 20 : 0,
            'recent_activity' => $organization->last_activity_at > now()->subDays(7) ? 20 : 0,
        ];

        return array_sum($signals);
    }
}
```

#### Tracking Customer Success Metrics

```php
// In MetricsService.php

public function trackCustomerHealthScores()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'customer_health_score',
        'Customer health score',
        ['organization']
    );

    $healthService = app(CustomerHealthService::class);

    $organizations = \App\Models\Organization::where('status', 'active')->get();

    foreach ($organizations as $org) {
        $score = $healthService->calculateHealthScore($org);
        $gauge->set($score, [$org->name]);
    }
}

public function trackNPS()
{
    // Track overall NPS
    $gaugeNPS = $this->registry->getOrRegisterGauge(
        'chom',
        'nps_score',
        'Net Promoter Score',
        []
    );

    // Get NPS responses from last 90 days
    $responses = \DB::table('nps_responses')
        ->where('created_at', '>=', now()->subDays(90))
        ->pluck('score');

    if ($responses->isEmpty()) {
        return;
    }

    $promoters = $responses->filter(fn($s) => $s >= 9)->count();
    $detractors = $responses->filter(fn($s) => $s <= 6)->count();
    $total = $responses->count();

    $nps = (($promoters - $detractors) / $total) * 100;

    $gaugeNPS->set($nps, []);

    // Track distribution
    $gaugeResponses = $this->registry->getOrRegisterGauge(
        'chom',
        'nps_responses',
        'NPS response counts by category',
        ['category']
    );

    $passives = $responses->filter(fn($s) => $s >= 7 && $s <= 8)->count();

    $gaugeResponses->set($promoters, ['promoter']);
    $gaugeResponses->set($passives, ['passive']);
    $gaugeResponses->set($detractors, ['detractor']);
}

public function trackCSAT()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'csat_score',
        'Customer satisfaction score',
        []
    );

    $avgScore = \DB::table('csat_responses')
        ->where('created_at', '>=', now()->subDays(30))
        ->avg('score');

    $gauge->set($avgScore ?? 0, []);
}

public function trackFeatureAdoption()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'feature_users',
        'Number of users using each feature',
        ['feature']
    );

    $features = [
        'site_management',
        'backup_automation',
        'team_collaboration',
        'api_access',
        'monitoring_alerts'
    ];

    foreach ($features as $feature) {
        $users = \DB::table('feature_usage')
            ->where('feature_name', $feature)
            ->where('last_used_at', '>=', now()->subDays(30))
            ->distinct('user_id')
            ->count();

        $gauge->set($users, [$feature]);
    }
}

public function trackSupportMetrics()
{
    // Ticket volume
    $tickets = \DB::table('support_tickets')
        ->where('created_at', '>=', now()->subDay())
        ->get();

    $counterTickets = $this->registry->getOrRegisterCounter(
        'chom',
        'support_tickets_total',
        'Total support tickets',
        ['status', 'priority']
    );

    // Track by status and priority
    $grouped = $tickets->groupBy(['status', 'priority']);

    foreach ($grouped as $status => $priorityGroup) {
        foreach ($priorityGroup as $priority => $tickets) {
            // This would need proper counter implementation
            // Increment counters in real-time as tickets are created
        }
    }

    // Resolution time
    $gaugeResolutionTime = $this->registry->getOrRegisterGauge(
        'chom',
        'support_resolution_time_hours',
        'Average ticket resolution time in hours',
        ['priority']
    );

    $priorities = ['critical', 'high', 'medium', 'low'];

    foreach ($priorities as $priority) {
        $avgTime = \DB::table('support_tickets')
            ->where('priority', $priority)
            ->where('status', 'resolved')
            ->where('resolved_at', '>=', now()->subDays(30))
            ->avg(\DB::raw('TIMESTAMPDIFF(HOUR, created_at, resolved_at)'));

        $gaugeResolutionTime->set($avgTime ?? 0, [$priority]);
    }
}

public function trackTimeToFirstValue()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'time_to_first_value_days',
        'Average days to first value milestone',
        []
    );

    $avgDays = \DB::table('users')
        ->whereNotNull('first_value_at')
        ->where('created_at', '>=', now()->subDays(90))
        ->avg(\DB::raw('DATEDIFF(first_value_at, created_at)'));

    $gauge->set($avgDays ?? 0, []);
}
```

### Dashboard 3: Growth & Marketing Dashboard

```php
// In MetricsService.php

public function incrementSignup(string $channel)
{
    $counter = $this->registry->getOrRegisterCounter(
        'chom',
        'users_signups_total',
        'Total user sign-ups',
        ['channel']
    );

    $counter->inc([$channel]);

    // Also update total users gauge
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'users_total',
        'Total users',
        []
    );

    $total = \DB::table('users')->count();
    $gauge->set($total, []);
}

public function incrementActivation()
{
    $counter = $this->registry->getOrRegisterCounter(
        'chom',
        'users_activated_total',
        'Total activated users',
        []
    );

    $counter->inc([]);
}

public function trackMarketingSpendByChannel()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'marketing_spend_total',
        'Marketing spend by channel',
        ['channel', 'period']
    );

    $channels = ['organic', 'paid', 'social', 'referral'];
    $periods = ['7d', '30d'];

    foreach ($channels as $channel) {
        foreach ($periods as $period) {
            $days = $period === '7d' ? 7 : 30;

            $spend = \DB::table('marketing_expenses')
                ->where('channel', $channel)
                ->where('date', '>=', now()->subDays($days))
                ->sum('amount');

            $gauge->set($spend, [$channel, $period]);
        }
    }
}

public function trackRevenueByChannel()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'revenue_by_channel',
        'Revenue attributed to each channel',
        ['channel']
    );

    $channels = ['organic', 'paid', 'referral', 'direct', 'social'];

    foreach ($channels as $channel) {
        $revenue = \DB::table('subscriptions')
            ->join('users', 'subscriptions.user_id', '=', 'users.id')
            ->where('users.signup_channel', $channel)
            ->where('subscriptions.status', 'active')
            ->sum('subscriptions.monthly_amount');

        $gauge->set($revenue, [$channel]);
    }
}

public function incrementReferral(string $type)
{
    $counter = $this->registry->getOrRegisterCounter(
        'chom',
        "referrals_{$type}_total",
        "Total referrals {$type}",
        []
    );

    $counter->inc([]);
}

public function trackEmailCampaignMetrics(string $campaign)
{
    $stats = \DB::table('email_campaigns')
        ->where('campaign', $campaign)
        ->first();

    if (!$stats) {
        return;
    }

    $metrics = ['sent', 'opened', 'clicked', 'converted'];

    foreach ($metrics as $metric) {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            "email_campaign_{$metric}",
            "Email campaign {$metric} count",
            ['campaign']
        );

        $gauge->set($stats->$metric, [$campaign]);
    }
}

public function trackLandingPageMetrics(string $page)
{
    $stats = \DB::table('landing_page_stats')
        ->where('page', $page)
        ->where('date', '>=', now()->subDays(30))
        ->selectRaw('SUM(visits) as visits, SUM(conversions) as conversions')
        ->first();

    $gaugeVisits = $this->registry->getOrRegisterGauge(
        'chom',
        'landing_page_visits',
        'Landing page visits',
        ['page']
    );

    $gaugeConversions = $this->registry->getOrRegisterGauge(
        'chom',
        'landing_page_conversions',
        'Landing page conversions',
        ['page']
    );

    $gaugeVisits->set($stats->visits ?? 0, [$page]);
    $gaugeConversions->set($stats->conversions ?? 0, [$page]);
}

public function trackCohortRetention()
{
    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'cohort_retention',
        'Cohort retention percentage',
        ['cohort', 'month_0', 'month_1', 'month_3', 'month_6', 'month_12']
    );

    // Get cohorts from last 12 months
    $cohorts = \DB::table('users')
        ->selectRaw('DATE_FORMAT(created_at, "%Y-%m") as cohort')
        ->where('created_at', '>=', now()->subMonths(12))
        ->groupBy('cohort')
        ->pluck('cohort');

    foreach ($cohorts as $cohort) {
        $cohortDate = \Carbon\Carbon::parse($cohort . '-01');

        $retention = [];

        foreach ([0, 1, 3, 6, 12] as $month) {
            $endDate = $cohortDate->copy()->addMonths($month);

            if ($endDate->isFuture()) {
                $retention["month_{$month}"] = null;
                continue;
            }

            $total = \DB::table('users')
                ->whereBetween('created_at', [
                    $cohortDate->startOfMonth(),
                    $cohortDate->endOfMonth()
                ])
                ->count();

            $active = \DB::table('users')
                ->whereBetween('created_at', [
                    $cohortDate->copy()->startOfMonth(),
                    $cohortDate->copy()->endOfMonth()
                ])
                ->where('last_active_at', '>=', $endDate)
                ->count();

            $retention["month_{$month}"] = $total > 0 ? ($active / $total) * 100 : 0;
        }

        // Set gauge with retention data as labels
        $gauge->set(
            100, // Dummy value since we're using labels for data
            array_merge(
                ['cohort' => $cohort],
                $retention
            )
        );
    }
}
```

---

## Event-Based Tracking

### User Registration

```php
// app/Events/UserRegistered.php

namespace App\Events;

use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class UserRegistered
{
    use Dispatchable, SerializesModels;

    public $user;
    public $channel;

    public function __construct($user, $channel)
    {
        $this->user = $user;
        $this->channel = $channel;
    }
}

// app/Listeners/TrackUserRegistration.php

namespace App\Listeners;

use App\Events\UserRegistered;
use App\Services\MetricsService;

class TrackUserRegistration
{
    private $metrics;

    public function __construct(MetricsService $metrics)
    {
        $this->metrics = $metrics;
    }

    public function handle(UserRegistered $event)
    {
        $this->metrics->incrementSignup($event->channel);
    }
}
```

### Subscription Created

```php
// app/Events/SubscriptionCreated.php

namespace App\Events;

class SubscriptionCreated
{
    public $subscription;

    public function __construct($subscription)
    {
        $this->subscription = $subscription;
    }
}

// app/Listeners/TrackNewCustomer.php

namespace App\Listeners;

class TrackNewCustomer
{
    private $metrics;

    public function __construct(MetricsService $metrics)
    {
        $this->metrics = $metrics;
    }

    public function handle(SubscriptionCreated $event)
    {
        $this->metrics->incrementNewCustomer();
    }
}
```

### Feature Usage

```php
// Track feature usage in controllers or services

public function useFeature($featureName)
{
    // Your feature logic here

    // Track usage
    \DB::table('feature_usage')->insert([
        'user_id' => auth()->id(),
        'organization_id' => auth()->user()->organization_id,
        'feature_name' => $featureName,
        'last_used_at' => now(),
    ]);

    // Increment counter
    $counter = app(MetricsService::class)->registry->getOrRegisterCounter(
        'chom',
        'feature_usage_total',
        'Total feature usage count',
        ['feature']
    );

    $counter->inc([$featureName]);
}
```

---

## Prometheus Configuration

### prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'chom'
    static_configs:
      - targets: ['localhost:9091']
    metrics_path: '/metrics'

# Recording rules for derived metrics
rule_files:
  - '/etc/prometheus/rules/*.yml'
```

### Recording Rules

```yaml
# /etc/prometheus/rules/chom_business.yml

groups:
  - name: chom_business_metrics
    interval: 1m
    rules:
      # Calculate LTV
      - record: chom:ltv
        expr: (sum(chom_revenue_mrr) / sum(chom_customers_total)) / (chom_churn_rate_monthly / 100)

      # Calculate CAC
      - record: chom:cac
        expr: sum(chom_marketing_spend_total{period="30d"}) / sum(increase(chom_customers_new_total[30d]))

      # Calculate LTV:CAC ratio
      - record: chom:ltv_cac_ratio
        expr: chom:ltv / chom:cac

      # DAU/MAU ratio
      - record: chom:dau_mau_ratio
        expr: (chom_users_active_daily / chom_users_active_monthly) * 100

      # Activation rate
      - record: chom:activation_rate
        expr: (sum(increase(chom_users_activated_total[7d])) / sum(increase(chom_users_signups_total[7d]))) * 100
```

---

## Testing & Validation

### Unit Tests

```php
// tests/Unit/MetricsServiceTest.php

namespace Tests\Unit;

use Tests\TestCase;
use App\Services\MetricsService;
use Illuminate\Foundation\Testing\RefreshDatabase;

class MetricsServiceTest extends TestCase
{
    use RefreshDatabase;

    private $metrics;

    protected function setUp(): void
    {
        parent::setUp();
        $this->metrics = new MetricsService();
    }

    public function test_it_tracks_mrr_correctly()
    {
        // Create test subscriptions
        \App\Models\Subscription::factory()->create([
            'tier' => 'professional',
            'monthly_amount' => 99,
            'status' => 'active'
        ]);

        $this->metrics->trackMRR();

        // Verify metric was set
        // This requires accessing Prometheus storage
        // or using a test double
    }

    public function test_it_increments_new_customers()
    {
        $initialCount = $this->getMetricValue('chom_customers_new_total');

        $this->metrics->incrementNewCustomer();

        $newCount = $this->getMetricValue('chom_customers_new_total');

        $this->assertEquals($initialCount + 1, $newCount);
    }

    private function getMetricValue($metricName)
    {
        // Implementation depends on your Prometheus client
        // This is a simplified example
        return 0;
    }
}
```

### Integration Tests

```php
// tests/Feature/MetricsEndpointTest.php

namespace Tests\Feature;

use Tests\TestCase;

class MetricsEndpointTest extends TestCase
{
    public function test_metrics_endpoint_returns_valid_data()
    {
        $response = $this->get('/metrics');

        $response->assertStatus(200);
        $response->assertHeader('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');

        $content = $response->getContent();

        // Verify key metrics are present
        $this->assertStringContainsString('chom_revenue_mrr', $content);
        $this->assertStringContainsString('chom_customers_total', $content);
        $this->assertStringContainsString('chom_users_active_daily', $content);
    }
}
```

---

## Performance Optimization

### 1. Use Queued Jobs for Heavy Calculations

```php
// app/Jobs/CalculateMetrics.php

namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Queue\InteractsWithQueue;
use App\Services\MetricsService;

class CalculateMetrics implements ShouldQueue
{
    use InteractsWithQueue, Queueable;

    private $metricType;

    public function __construct($metricType)
    {
        $this->metricType = $metricType;
    }

    public function handle(MetricsService $metrics)
    {
        switch ($this->metricType) {
            case 'customer_health':
                $metrics->trackCustomerHealthScores();
                break;
            case 'cohort_retention':
                $metrics->trackCohortRetention();
                break;
            // Add more cases as needed
        }
    }
}

// Dispatch from scheduler
$schedule->job(new CalculateMetrics('customer_health'))->hourly();
$schedule->job(new CalculateMetrics('cohort_retention'))->daily();
```

### 2. Cache Expensive Queries

```php
public function trackMRR()
{
    $mrr = \Cache::remember('mrr_calculation', 300, function () {
        return \DB::table('subscriptions')
            ->where('status', 'active')
            ->sum('monthly_amount');
    });

    $gauge = $this->registry->getOrRegisterGauge(
        'chom',
        'revenue_mrr',
        'Monthly Recurring Revenue',
        []
    );

    $gauge->set($mrr, []);
}
```

### 3. Database Indexes

```sql
-- Optimize metrics queries

CREATE INDEX idx_subscriptions_status_tier ON subscriptions(status, tier);
CREATE INDEX idx_users_last_active ON user_activity(last_active_at);
CREATE INDEX idx_support_tickets_created ON support_tickets(created_at, status, priority);
CREATE INDEX idx_users_signup_channel ON users(signup_channel, created_at);
```

### 4. Batch Processing

```php
// Process metrics in batches to avoid memory issues

public function trackCustomerHealthScores()
{
    \App\Models\Organization::where('status', 'active')
        ->chunk(100, function ($organizations) {
            foreach ($organizations as $org) {
                $score = $this->calculateHealthScore($org);
                $this->setHealthScoreMetric($org->name, $score);
            }
        });
}
```

---

## Monitoring & Alerts

### Grafana Alerts Configuration

```json
{
  "alert": {
    "name": "High Churn Rate",
    "conditions": [
      {
        "evaluator": {
          "params": [7],
          "type": "gt"
        },
        "query": {
          "model": {
            "expr": "chom_churn_rate_monthly"
          }
        }
      }
    ],
    "frequency": "5m",
    "for": "10m",
    "notifications": [
      {
        "uid": "slack-notifications"
      }
    ]
  }
}
```

---

## Troubleshooting

### Issue: Metrics Not Appearing

**Solutions:**
1. Check Redis connection
2. Verify Prometheus is scraping endpoint
3. Check metric naming conventions
4. Review Prometheus logs

### Issue: Incorrect Values

**Solutions:**
1. Validate source data in database
2. Check calculation logic
3. Verify time zones
4. Review aggregation periods

### Issue: Performance Degradation

**Solutions:**
1. Add database indexes
2. Use caching for expensive queries
3. Queue heavy calculations
4. Use Prometheus recording rules

---

## Next Steps

1. **Implement core metrics** for Dashboard 1 (Business KPIs)
2. **Set up scheduled jobs** to calculate metrics
3. **Create event listeners** for real-time tracking
4. **Configure Prometheus** scraping and recording rules
5. **Import Grafana dashboards**
6. **Validate metrics** with test data
7. **Set up alerts** for critical thresholds
8. **Document custom business logic** specific to CHOM

---

Last Updated: 2026-01-02
Version: 1.0
