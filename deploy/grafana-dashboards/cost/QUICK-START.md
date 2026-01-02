# Cost Analysis & Capacity Planning - Quick Start Guide

Get up and running with CHOM cost analysis and capacity planning in 30 minutes.

## Prerequisites Checklist

- [ ] Prometheus installed and running
- [ ] Grafana installed and running
- [ ] CHOM application deployed
- [ ] Basic understanding of Grafana dashboards

## 5-Step Quick Start

### Step 1: Deploy Metrics Exporter (10 minutes)

**1.1 Copy the metrics exporter service:**
```bash
cd /home/calounx/repositories/mentat
cp deploy/grafana-dashboards/cost/MetricsExporter.php.example \
   chom/app/Services/MetricsExporter.php
```

**1.2 Copy the configuration:**
```bash
cp deploy/grafana-dashboards/cost/metrics-config.php \
   chom/config/metrics-config.php
```

**1.3 Add the metrics endpoint to routes:**
```bash
# Add to chom/routes/web.php
cat >> chom/routes/web.php << 'EOF'

// Prometheus metrics endpoint
Route::get('/metrics', function() {
    return response(app(\App\Services\MetricsExporter::class)->export())
        ->header('Content-Type', 'text/plain; version=0.0.4');
});
EOF
```

**1.4 Set your pricing in .env:**
```bash
cd chom
cat >> .env << 'EOF'

# Cost & Capacity Configuration
PRICING_VPS_BASE=10.00
PRICING_STORAGE_GB=0.15
PRICING_BANDWIDTH_GB=0.08
BUDGET_MONTHLY_TOTAL=5000
METRICS_ENABLED=true
EOF
```

**1.5 Test the metrics endpoint:**
```bash
curl http://localhost/metrics | head -20
```

You should see Prometheus-formatted metrics like:
```
# HELP chom_infrastructure_cost_monthly Monthly infrastructure cost in USD
# TYPE chom_infrastructure_cost_monthly gauge
chom_infrastructure_cost_monthly{service="chom",category="compute",resource_type="vps"} 120.00
```

### Step 2: Configure Prometheus (5 minutes)

**2.1 Edit Prometheus configuration:**
```bash
sudo nano /etc/prometheus/prometheus.yml
```

**2.2 Add CHOM scrape config:**
```yaml
scrape_configs:
  # Existing configs...

  # Add this new job
  - job_name: 'chom'
    scrape_interval: 30s
    static_configs:
      - targets: ['localhost:80']  # Adjust to your CHOM URL
    metrics_path: '/metrics'
```

**2.3 Restart Prometheus:**
```bash
sudo systemctl restart prometheus

# Verify it's running
sudo systemctl status prometheus
```

**2.4 Verify scraping:**
Visit `http://your-prometheus:9090/targets` and confirm CHOM target is UP.

### Step 3: Import Grafana Dashboards (5 minutes)

**Option A: Using Grafana UI (Recommended)**

1. Open Grafana in your browser
2. Login with your credentials
3. Click "+" icon → "Import"
4. Click "Upload JSON file"
5. Select `/home/calounx/repositories/mentat/deploy/grafana-dashboards/cost/cost-analysis.json`
6. Select "Prometheus" as data source
7. Click "Import"
8. Repeat steps 3-7 for `capacity-planning.json`

**Option B: Using Provisioning**

```bash
# Copy dashboards to Grafana provisioning directory
sudo cp /home/calounx/repositories/mentat/deploy/grafana-dashboards/cost/*.json \
   /etc/grafana/provisioning/dashboards/

# Create provisioning config if it doesn't exist
sudo tee /etc/grafana/provisioning/dashboards/chom.yml > /dev/null << 'EOF'
apiVersion: 1

providers:
  - name: 'CHOM Dashboards'
    orgId: 1
    folder: 'CHOM'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /etc/grafana/provisioning/dashboards
EOF

# Restart Grafana
sudo systemctl restart grafana-server
```

### Step 4: Verify Dashboards (5 minutes)

**4.1 Open Cost Analysis Dashboard:**
1. Navigate to Grafana → Dashboards
2. Find "CHOM - Cost Analysis"
3. Verify you see data in the panels
4. Check for any "No data" errors

**4.2 Open Capacity Planning Dashboard:**
1. Navigate to "CHOM - Capacity Planning"
2. Verify resource utilization gauges show data
3. Check forecast charts are rendering

**4.3 Troubleshoot if no data:**
```bash
# Check if metrics are being scraped
curl http://localhost:9090/api/v1/query?query=chom_infrastructure_cost_monthly

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="chom")'

# Check Grafana data source
# Go to Grafana → Configuration → Data Sources → Prometheus → Save & Test
```

### Step 5: Configure Alerts (5 minutes)

**5.1 Set up Slack notifications (optional):**

In Grafana:
1. Go to Alerting → Contact points
2. Click "New contact point"
3. Name: "CHOM Alerts"
4. Type: "Slack"
5. Webhook URL: (your Slack webhook)
6. Click "Test" then "Save"

**5.2 Create notification policy:**
1. Go to Alerting → Notification policies
2. Click "New policy"
3. Match: `service=chom`
4. Contact point: "CHOM Alerts"
5. Save

**5.3 Test an alert:**

Temporarily lower a threshold to trigger an alert:
1. Edit Cost Analysis dashboard
2. Find "Budget Utilization" panel
3. Edit → Alert
4. Set threshold to 0.1% (should trigger immediately)
5. Save and wait 1 minute
6. Check if alert fires
7. Reset threshold to 80%

## Verify Everything Works

### Checklist

- [ ] Metrics endpoint returns data: `curl http://localhost/metrics`
- [ ] Prometheus scraping CHOM: Check targets page
- [ ] Cost Analysis dashboard shows current costs
- [ ] Capacity Planning dashboard shows utilization
- [ ] Forecasts are visible (may need 24h of data)
- [ ] Alerts are configured and tested

## Common Issues & Solutions

### Issue 1: No metrics data

**Symptoms:** Dashboards show "No data"

**Solutions:**
```bash
# 1. Check if metrics endpoint works
curl http://localhost/metrics

# 2. Check Prometheus targets
curl http://localhost:9090/api/v1/targets

# 3. Check Prometheus can query metrics
curl http://localhost:9090/api/v1/query?query=up{job="chom"}

# 4. Check Grafana data source connection
# Grafana UI → Configuration → Data Sources → Prometheus → Test
```

### Issue 2: Incorrect cost calculations

**Symptoms:** Costs don't match expected values

**Solutions:**
1. Verify pricing in `.env` or `config/metrics-config.php`
2. Check MetricsExporter calculation logic
3. Verify resource counts are correct
4. Check database queries for storage/VPS counts

### Issue 3: Forecasts not showing

**Symptoms:** Forecast lines are missing

**Solutions:**
1. Need at least 7 days of data for accurate forecasts
2. Check PromQL `predict_linear()` queries
3. Verify historical data exists in Prometheus
4. Wait 24-48 hours after initial setup

### Issue 4: Alerts not firing

**Symptoms:** No alerts received when thresholds exceeded

**Solutions:**
1. Verify notification channel is configured
2. Test notification channel
3. Check alert rules are enabled
4. Verify alert conditions are being met
5. Check alert history in Grafana

## Next Steps

Now that basic setup is complete:

### Immediate (Today)
1. Review current costs in Cost Analysis dashboard
2. Check resource utilization in Capacity Planning dashboard
3. Set realistic budgets based on current costs
4. Configure alert thresholds

### This Week
1. Read [COST-OPTIMIZATION-RECOMMENDATIONS.md](./COST-OPTIMIZATION-RECOMMENDATIONS.md)
2. Implement quick wins (compression, cleanup, etc.)
3. Establish daily review routine
4. Train team on dashboard usage

### This Month
1. Implement high-priority optimizations
2. Set up automated reporting
3. Refine cost allocation by tenant
4. Plan first scaling actions based on forecasts

## Daily Operations

### Morning Routine (5 minutes)

```bash
# Open Cost Analysis Dashboard
# Check:
# 1. Total monthly cost is within budget
# 2. No cost anomalies detected
# 3. Top tenants are reasonable
# 4. Budget utilization trending normally

# Open Capacity Planning Dashboard
# Check:
# 1. All gauges are green/yellow (not red)
# 2. No scaling recommendations at "Critical" priority
# 3. Storage headroom > 30 days
# 4. Forecasts look reasonable
```

### Weekly Review (30 minutes)

1. Review cost trends and identify anomalies
2. Check capacity forecasts and plan scaling
3. Review top 10 tenants by cost
4. Implement 1-2 optimization opportunities
5. Update budgets if needed

### Monthly Review (2 hours)

1. Generate cost allocation report
2. Review optimization progress
3. Update budgets for next month
4. Plan capacity additions for next quarter
5. Stakeholder presentation with key metrics

## Key Metrics to Watch

### Cost Metrics
- Total monthly cost
- Budget utilization %
- Cost per tenant
- Month-over-month growth
- Infrastructure ROI

### Capacity Metrics
- CPU utilization
- Memory utilization
- Disk utilization
- Storage headroom (days)
- Number of scaling recommendations

### Health Indicators
- Cost anomalies detected: 0 (green)
- Capacity alerts: 0 (green)
- Budget variance: < 5% (green)
- Forecast accuracy: > 90% (green)

## Getting Help

### Documentation
- [README.md](./README.md) - Complete implementation guide
- [COST-OPTIMIZATION-RECOMMENDATIONS.md](./COST-OPTIMIZATION-RECOMMENDATIONS.md) - Optimization strategies
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture
- [SUMMARY.md](./SUMMARY.md) - Executive summary

### Troubleshooting
- Check Prometheus logs: `journalctl -u prometheus -f`
- Check Grafana logs: `journalctl -u grafana-server -f`
- Check CHOM logs: `tail -f chom/storage/logs/laravel.log`

### Community Resources
- Prometheus Documentation: https://prometheus.io/docs/
- Grafana Documentation: https://grafana.com/docs/
- PromQL Guide: https://prometheus.io/docs/prometheus/latest/querying/basics/

## Success Criteria

After 30 days, you should have:

- [ ] Real-time cost visibility
- [ ] Budget tracking and alerts
- [ ] Capacity planning with forecasts
- [ ] At least 3 optimizations implemented
- [ ] 10-20% cost reduction achieved
- [ ] Proactive scaling based on forecasts
- [ ] Weekly review process established
- [ ] Team trained on dashboards

## Customization

### Adjust Pricing

Edit `chom/config/metrics-config.php`:
```php
'pricing' => [
    'vps' => ['base_cost' => 15.00],  // Change from 10.00
    'storage' => ['ssd_per_gb' => 0.20],  // Change from 0.15
],
```

### Adjust Thresholds

```php
'capacity' => [
    'thresholds' => [
        'cpu' => [
            'warning' => 70,   // Change from 60
            'critical' => 90,  // Change from 85
        ],
    ],
],
```

### Add Custom Metrics

Add to `MetricsExporter.php`:
```php
private function exportCustomMetrics(): void
{
    $this->addHelp('chom_custom_metric', 'My custom metric');
    $this->addType('chom_custom_metric', 'gauge');
    $this->addMetric('chom_custom_metric', $this->calculateCustomValue());
}
```

## Quick Reference Commands

```bash
# Restart all services
sudo systemctl restart prometheus grafana-server

# Check service status
sudo systemctl status prometheus grafana-server

# View Prometheus targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="chom")'

# Query a metric
curl 'http://localhost:9090/api/v1/query?query=chom_infrastructure_cost_monthly'

# Test metrics endpoint
curl http://localhost/metrics | grep chom_

# View Grafana dashboards
ls /etc/grafana/provisioning/dashboards/

# Check Prometheus config
sudo promtool check config /etc/prometheus/prometheus.yml
```

## Conclusion

You now have a fully functional FinOps and capacity planning system for CHOM!

Start with daily dashboard reviews, implement quick-win optimizations, and build from there. Within 30-90 days, you should see significant cost savings and much better capacity planning.

**Remember:** This is a journey, not a destination. Continuous monitoring and optimization will yield the best results.

---

**Setup Time:** ~30 minutes
**Expected Results:** Cost visibility and capacity planning within 24 hours
**Next Step:** Read the [Cost Optimization Recommendations](./COST-OPTIMIZATION-RECOMMENDATIONS.md)
