# CHOM Cost Analysis & Capacity Planning Dashboards

## Overview

This directory contains two comprehensive Grafana dashboards for financial operations (FinOps) and capacity planning:

1. **Cost Analysis Dashboard** - Real-time cost tracking, budget management, and optimization insights
2. **Capacity Planning Dashboard** - Resource utilization forecasting and scaling recommendations

## Dashboard Files

```
cost/
├── cost-analysis.json                      # Cost tracking and budget dashboard
├── capacity-planning.json                  # Capacity forecasting dashboard
├── COST-OPTIMIZATION-RECOMMENDATIONS.md    # Detailed cost optimization guide
└── README.md                              # This file
```

---

## Cost Analysis Dashboard

### Features

**Financial Metrics:**
- Total monthly infrastructure cost
- Budget utilization percentage
- Cost trend vs. budget (30-day view)
- Cost breakdown by category
- Infrastructure cost by resource type
- Cost per tenant (top 10)

**Storage & Growth:**
- Storage growth and 30-day projection
- Projected storage costs
- Storage capacity planning

**Network:**
- Bandwidth usage (ingress/egress)
- Projected bandwidth costs

**Email Services:**
- Daily email usage by type
- Monthly email service cost

**Optimization:**
- Resource utilization vs. cost efficiency
- Cost anomaly detection
- Cost optimization opportunities table
- Infrastructure ROI calculation

**Alerts:**
- Budget exceeded alerts
- Cost anomalies
- Threshold violations

### Key Panels

#### 1. Total Monthly Cost (Gauge)
- Shows current month's total infrastructure cost
- Thresholds: Yellow at 80% of budget, Red at 100%

#### 2. Budget Utilization (Gauge)
- Percentage of monthly budget consumed
- Real-time tracking against allocated budget

#### 3. Cost Trend vs Budget (Timeseries)
- 30-day cost trend with budget overlay
- Identifies when costs exceed budget

#### 4. Cost Breakdown (Pie Chart)
- Visual breakdown by category (VPS, Storage, Bandwidth, Email, etc.)
- Percentage and dollar amounts

#### 5. Cost per Tenant (Table)
- Top 10 tenants by monthly cost
- Helps identify high-cost customers
- Useful for chargeback/showback

#### 6. Cost Optimization Opportunities (Table)
- Actionable recommendations
- Potential savings amounts
- Priority ranking

---

## Capacity Planning Dashboard

### Features

**Current Utilization:**
- CPU utilization gauge
- Memory utilization gauge
- Disk utilization gauge
- Database connection pool usage
- Storage capacity headroom

**Forecasting (30/60/90 day):**
- CPU utilization trends and projections
- Memory utilization trends and projections
- Storage growth projections
- Database size growth projections
- Network bandwidth trends
- Tenant growth forecast

**Planning Tools:**
- Tenant storage consumption breakdown
- Tenant resource consumption table
- Peak usage pattern analysis
- Scaling recommendations table
- Capacity headroom by resource

**Alerts:**
- Capacity threshold exceeded
- Resource exhaustion warnings
- Scaling recommendations

### Key Panels

#### 1. Resource Utilization Gauges
- Real-time CPU, Memory, Disk, DB connections
- Color-coded thresholds (Green < 60%, Yellow < 75%, Orange < 85%, Red > 85%)

#### 2. Storage Capacity Headroom
- Days until storage exhaustion
- Based on 7-day growth trend
- Red < 30 days, Orange < 60 days, Yellow < 90 days

#### 3. CPU/Memory Trend & Forecast
- Current utilization line
- 30/60/90-day projections (dashed lines)
- Helps plan scaling activities

#### 4. Storage Growth & Capacity Planning
- Historical storage usage
- Multi-period forecasts
- Capacity limit overlay

#### 5. Tenant Resource Consumption
- Storage, site count, VPS count per tenant
- Sorted by resource usage
- Identifies resource-heavy tenants

#### 6. Scaling Recommendations
- Automated recommendations
- Priority and ETA for action
- Threshold and action details

---

## Required Metrics

Both dashboards require Prometheus metrics to be exposed. Here are the metrics needed:

### Cost Metrics

```prometheus
# Total monthly infrastructure cost
chom_infrastructure_cost_monthly{service="chom",category="compute|storage|network|email",resource_type="vps|disk|bandwidth|ses"}

# Budget tracking
chom_cost_budget_monthly{service="chom"}

# Tenant-specific costs
chom_tenant_cost_monthly{service="chom",tenant_id="<id>"}

# Storage costs
chom_storage_cost_total{service="chom"}
chom_storage_bytes_total{service="chom"}

# Network costs
chom_bandwidth_cost_total{service="chom"}
chom_network_transmit_bytes_total{service="chom"}
chom_network_receive_bytes_total{service="chom"}

# Email costs
chom_email_service_cost_monthly{service="chom"}
chom_email_sent_total{service="chom",type="transactional|marketing"}

# Cost optimization
chom_cost_optimization_opportunity{service="chom",category="<category>",priority="High|Medium|Low",description="<desc>"}

# Anomaly detection
chom_cost_anomaly_detected{service="chom",category="<category>"}

# ROI metrics
chom_revenue_monthly{service="chom"}
```

### Capacity Metrics

```prometheus
# CPU metrics (from node_exporter)
node_cpu_seconds_total{service="chom",mode="idle|user|system"}

# Memory metrics (from node_exporter)
node_memory_MemTotal_bytes{service="chom"}
node_memory_MemAvailable_bytes{service="chom"}

# Disk metrics (from node_exporter)
node_filesystem_size_bytes{service="chom",mountpoint="/"}
node_filesystem_avail_bytes{service="chom",mountpoint="/"}

# Database metrics (from mysqld_exporter)
mysql_global_status_threads_connected{service="chom"}
mysql_global_variables_max_connections{service="chom"}
mysql_global_status_innodb_data_written{service="chom"}

# Application metrics
chom_http_requests_total{service="chom"}
chom_tenant_id{service="chom"}
chom_tenant_storage_bytes{service="chom",tenant_id="<id>"}
chom_site_count{service="chom",tenant_id="<id>"}
chom_vps_count{service="chom",tenant_id="<id>"}

# Capacity planning
chom_capacity_threshold_exceeded{service="chom",resource="cpu|memory|disk|database"}
chom_capacity_recommendation{service="chom",resource="<resource>",action="scale_up|scale_down",priority="Critical|High|Medium|Low",eta_days="<days>"}
chom_capacity_headroom{service="chom",resource="<resource>",current_utilization="<percent>",unit="percent|bytes|count"}
```

---

## Implementing Metrics Collection

### Step 1: Create Metrics Exporter

Create a custom Prometheus exporter for CHOM-specific metrics:

```php
// app/Services/MetricsExporter.php
<?php

namespace App\Services;

use Illuminate\Support\Facades\DB;
use App\Models\Tenant;
use App\Models\Site;
use App\Models\Vps;

class MetricsExporter
{
    public function export(): string
    {
        $metrics = [];

        // Cost metrics
        $metrics[] = $this->exportCostMetrics();
        $metrics[] = $this->exportTenantCostMetrics();
        $metrics[] = $this->exportStorageMetrics();
        $metrics[] = $this->exportBandwidthMetrics();
        $metrics[] = $this->exportEmailMetrics();

        // Capacity metrics
        $metrics[] = $this->exportTenantMetrics();
        $metrics[] = $this->exportCapacityMetrics();

        return implode("\n", array_filter($metrics));
    }

    private function exportCostMetrics(): string
    {
        // Calculate costs based on your pricing model
        $computeCost = Vps::count() * config('pricing.vps_base_cost');
        $storageCost = DB::table('sites')->sum('storage_used_bytes') / (1024**3) * config('pricing.storage_per_gb');

        return <<<METRICS
# HELP chom_infrastructure_cost_monthly Monthly infrastructure cost in USD
# TYPE chom_infrastructure_cost_monthly gauge
chom_infrastructure_cost_monthly{service="chom",category="compute",resource_type="vps"} {$computeCost}
chom_infrastructure_cost_monthly{service="chom",category="storage",resource_type="disk"} {$storageCost}
METRICS;
    }

    private function exportTenantCostMetrics(): string
    {
        $metrics = [];
        $metrics[] = '# HELP chom_tenant_cost_monthly Monthly cost per tenant in USD';
        $metrics[] = '# TYPE chom_tenant_cost_monthly gauge';

        foreach (Tenant::all() as $tenant) {
            $cost = $this->calculateTenantCost($tenant);
            $metrics[] = "chom_tenant_cost_monthly{service=\"chom\",tenant_id=\"{$tenant->id}\"} {$cost}";
        }

        return implode("\n", $metrics);
    }

    private function exportStorageMetrics(): string
    {
        $totalStorage = DB::table('sites')->sum('storage_used_bytes');

        return <<<METRICS
# HELP chom_storage_bytes_total Total storage used in bytes
# TYPE chom_storage_bytes_total gauge
chom_storage_bytes_total{service="chom"} {$totalStorage}
METRICS;
    }

    private function exportTenantMetrics(): string
    {
        $metrics = [];
        $metrics[] = '# HELP chom_tenant_storage_bytes Storage used by tenant in bytes';
        $metrics[] = '# TYPE chom_tenant_storage_bytes gauge';

        foreach (Tenant::all() as $tenant) {
            $storage = DB::table('sites')
                ->where('team_id', $tenant->id)
                ->sum('storage_used_bytes');

            $siteCount = Site::where('team_id', $tenant->id)->count();
            $vpsCount = Vps::where('team_id', $tenant->id)->count();

            $metrics[] = "chom_tenant_storage_bytes{service=\"chom\",tenant_id=\"{$tenant->id}\"} {$storage}";
            $metrics[] = "chom_site_count{service=\"chom\",tenant_id=\"{$tenant->id}\"} {$siteCount}";
            $metrics[] = "chom_vps_count{service=\"chom\",tenant_id=\"{$tenant->id}\"} {$vpsCount}";
        }

        return implode("\n", $metrics);
    }

    private function exportCapacityMetrics(): string
    {
        // Example: Calculate capacity headroom
        $diskUsage = disk_total_space('/') - disk_free_space('/');
        $diskTotal = disk_total_space('/');
        $diskUtilization = ($diskUsage / $diskTotal) * 100;

        return <<<METRICS
# HELP chom_capacity_headroom Capacity headroom percentage
# TYPE chom_capacity_headroom gauge
chom_capacity_headroom{service="chom",resource="disk",unit="percent",current_utilization="{$diskUtilization}"} {100 - $diskUtilization}
METRICS;
    }

    private function calculateTenantCost(Tenant $tenant): float
    {
        // Implement your cost calculation logic
        $storage = DB::table('sites')->where('team_id', $tenant->id)->sum('storage_used_bytes');
        $vpsCount = Vps::where('team_id', $tenant->id)->count();

        $storageCost = ($storage / (1024**3)) * config('pricing.storage_per_gb');
        $vpsCost = $vpsCount * config('pricing.vps_base_cost');

        return $storageCost + $vpsCost;
    }

    // Add other export methods...
}
```

### Step 2: Create Metrics Endpoint

```php
// routes/web.php
Route::get('/metrics', function () {
    $exporter = new \App\Services\MetricsExporter();
    return response($exporter->export())
        ->header('Content-Type', 'text/plain; version=0.0.4');
});
```

### Step 3: Configure Prometheus

```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'chom'
    scrape_interval: 30s
    static_configs:
      - targets: ['chom.example.com:80']
    metrics_path: '/metrics'
```

---

## Installation

### 1. Import Dashboards into Grafana

**Using Grafana UI:**
1. Navigate to Grafana
2. Click "+" → "Import"
3. Upload `cost-analysis.json`
4. Select Prometheus data source
5. Click "Import"
6. Repeat for `capacity-planning.json`

**Using Grafana CLI:**
```bash
# Copy dashboards to Grafana provisioning directory
cp cost-analysis.json /etc/grafana/provisioning/dashboards/
cp capacity-planning.json /etc/grafana/provisioning/dashboards/

# Restart Grafana
systemctl restart grafana-server
```

**Using Grafana API:**
```bash
# Cost Analysis Dashboard
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @cost-analysis.json \
  http://grafana.example.com/api/dashboards/db

# Capacity Planning Dashboard
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d @capacity-planning.json \
  http://grafana.example.com/api/dashboards/db
```

### 2. Configure Data Sources

Ensure Prometheus is configured as a data source:

1. Navigate to Configuration → Data Sources
2. Click "Add data source"
3. Select "Prometheus"
4. Set URL: `http://prometheus:9090`
5. Click "Save & Test"

### 3. Set Up Alerts

Configure Grafana alerting for budget and capacity alerts:

```yaml
# grafana/provisioning/alerting/chom-alerts.yml
apiVersion: 1

groups:
  - name: cost-alerts
    interval: 5m
    rules:
      - uid: budget-exceeded
        title: Budget Exceeded
        condition: A
        data:
          - refId: A
            queryType: ''
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: prometheus
            model:
              expr: '(sum(chom_infrastructure_cost_monthly{service="chom"}) / sum(chom_cost_budget_monthly{service="chom"})) * 100 > 100'
        noDataState: NoData
        execErrState: Alerting
        for: 5m
        annotations:
          description: 'Monthly budget has been exceeded'
        labels:
          severity: critical

  - name: capacity-alerts
    interval: 5m
    rules:
      - uid: storage-capacity-warning
        title: Storage Capacity Warning
        condition: A
        data:
          - refId: A
            queryType: ''
            relativeTimeRange:
              from: 600
              to: 0
            datasourceUid: prometheus
            model:
              expr: '(node_filesystem_size_bytes{service="chom",mountpoint="/"} - node_filesystem_avail_bytes{service="chom",mountpoint="/"}) / node_filesystem_size_bytes{service="chom",mountpoint="/"} * 100 > 80'
        noDataState: NoData
        execErrState: Alerting
        for: 10m
        annotations:
          description: 'Storage utilization exceeds 80%'
        labels:
          severity: warning
```

---

## Configuration

### Dashboard Variables

Both dashboards support time range variables:

**Cost Analysis:**
- `time_range`: Select analysis period (1h, 6h, 24h, 7d, 30d, 90d)
- Default: 7d

**Capacity Planning:**
- `forecast_period`: Select forecast horizon (7d, 14d, 30d, 60d, 90d)
- Default: 30d

### Thresholds

Customize thresholds in each panel:

**Cost Analysis Thresholds:**
- Budget Warning: 80% (Yellow)
- Budget Critical: 100% (Red)
- Budget Exceeded: 120% (Red + Alert)

**Capacity Planning Thresholds:**
- Utilization Warning: 60% (Yellow)
- Utilization High: 75% (Orange)
- Utilization Critical: 85% (Red)

---

## Usage Guide

### Daily Operations

1. **Morning Review:**
   - Check Cost Analysis dashboard
   - Verify no budget alerts
   - Review cost anomalies

2. **Weekly Planning:**
   - Review Capacity Planning dashboard
   - Check growth forecasts
   - Plan scaling activities

3. **Monthly Review:**
   - Generate cost reports
   - Review optimization opportunities
   - Update budgets for next month

### Cost Optimization Workflow

1. Open **Cost Analysis Dashboard**
2. Review **Cost Optimization Opportunities** table
3. Sort by **Potential Savings** (highest first)
4. For each opportunity:
   - Review details and priority
   - Check feasibility
   - Implement changes
   - Monitor savings

### Capacity Planning Workflow

1. Open **Capacity Planning Dashboard**
2. Review **Scaling Recommendations** table
3. Check forecast charts for confirmation
4. For each recommendation:
   - Verify ETA is accurate
   - Plan implementation
   - Execute scaling
   - Validate results

---

## Troubleshooting

### No Data Showing

**Problem:** Panels show "No data"

**Solutions:**
1. Verify Prometheus is scraping metrics:
   ```bash
   curl http://prometheus:9090/api/v1/targets
   ```

2. Check if metrics endpoint is accessible:
   ```bash
   curl http://chom.example.com/metrics
   ```

3. Verify data source configuration in Grafana

### Incorrect Costs

**Problem:** Cost calculations seem incorrect

**Solutions:**
1. Verify pricing configuration:
   ```php
   // config/pricing.php
   return [
       'vps_base_cost' => 10.00,      // Per VPS per month
       'storage_per_gb' => 0.15,      // Per GB per month
       'bandwidth_per_gb' => 0.08,    // Per GB
       'email_per_1000' => 0.10,      // Per 1000 emails
   ];
   ```

2. Check metrics calculation logic in `MetricsExporter`

3. Validate tenant cost allocation

### Forecast Inaccuracies

**Problem:** Capacity forecasts are not accurate

**Solutions:**
1. Increase historical data period for `predict_linear()`
2. Exclude anomalous periods from forecast
3. Use different forecast period (7d, 14d, 30d)
4. Consider seasonal variations

---

## Maintenance

### Regular Updates

**Weekly:**
- Review dashboard accuracy
- Update thresholds if needed
- Validate alerts

**Monthly:**
- Update budget allocations
- Review optimization progress
- Refine cost allocation

**Quarterly:**
- Review dashboard effectiveness
- Update pricing models
- Add new metrics as needed

### Dashboard Updates

When updating dashboards:

1. Export current dashboard from Grafana
2. Make changes in JSON file
3. Test in development environment
4. Import updated version
5. Document changes

---

## Best Practices

### Cost Management

1. **Set Realistic Budgets**
   - Base on historical data
   - Include growth buffer (15-20%)
   - Review quarterly

2. **Monitor Daily**
   - Check dashboard each morning
   - Investigate anomalies immediately
   - Track optimization progress

3. **Implement Automation**
   - Auto-scaling based on demand
   - Automated cleanup of unused resources
   - Budget alerts and notifications

### Capacity Planning

1. **Plan Ahead**
   - Review forecasts weekly
   - Plan scaling 30 days in advance
   - Test scaling procedures

2. **Monitor Trends**
   - Track growth patterns
   - Identify seasonal variations
   - Adjust forecasts accordingly

3. **Maintain Headroom**
   - Keep 20-30% capacity buffer
   - Plan for unexpected growth
   - Test at peak capacity

---

## Integration with Other Systems

### Slack Notifications

```yaml
# Grafana notification channel
apiVersion: 1
notifiers:
  - name: slack-chom-costs
    type: slack
    uid: slack-chom
    is_default: false
    settings:
      url: https://hooks.slack.com/services/YOUR/WEBHOOK/URL
      recipient: '#infrastructure-costs'
      mention_users: '@infrastructure-team'
```

### Email Reports

```php
// Schedule daily cost summary
Schedule::daily(function () {
    $summary = [
        'total_cost' => Metrics::getTotalCost(),
        'budget_utilization' => Metrics::getBudgetUtilization(),
        'anomalies' => Metrics::getCostAnomalies(),
        'top_tenants' => Metrics::getTopTenants(10),
    ];

    Mail::to(config('cost.report_recipients'))
        ->send(new DailyCostSummary($summary));
})->at('08:00');
```

### JIRA Integration

Automatically create JIRA tickets for scaling recommendations:

```php
// When capacity threshold exceeded
if ($capacityHeadroom < 30) {
    Jira::createIssue([
        'project' => 'INFRA',
        'type' => 'Task',
        'summary' => "Scale up {$resource} - {$capacityHeadroom} days remaining",
        'description' => "Capacity planning recommends scaling up {$resource}",
        'priority' => $this->calculatePriority($capacityHeadroom),
    ]);
}
```

---

## Additional Resources

- [Cost Optimization Recommendations](./COST-OPTIMIZATION-RECOMMENDATIONS.md) - Detailed optimization guide
- [Grafana Dashboard Documentation](../IMPORT_GUIDE.md) - General dashboard import guide
- [FinOps Best Practices](https://www.finops.org/framework/) - Industry standards

---

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review Grafana logs: `/var/log/grafana/grafana.log`
3. Check Prometheus metrics: `http://prometheus:9090/targets`
4. Contact infrastructure team

---

**Version:** 1.0
**Last Updated:** 2026-01-02
**Maintainer:** Infrastructure Team
