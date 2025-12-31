# CHOM Business Metrics Dashboard

## Executive Summary Metrics

This document provides SQL queries and tracking methodologies for key business metrics that drive CHOM's growth strategy.

---

## 1. Revenue Metrics

### Monthly Recurring Revenue (MRR)

```sql
-- Current MRR by tier
SELECT
    s.tier,
    COUNT(DISTINCT s.organization_id) as customer_count,
    SUM(tl.price_monthly_cents) / 100 as base_mrr,
    SUM(COALESCE(overage.monthly_overages, 0)) as overage_mrr,
    (SUM(tl.price_monthly_cents) / 100 + SUM(COALESCE(overage.monthly_overages, 0))) as total_mrr,
    ((SUM(tl.price_monthly_cents) / 100 + SUM(COALESCE(overage.monthly_overages, 0))) / COUNT(DISTINCT s.organization_id)) as arpu
FROM subscriptions s
JOIN tier_limits tl ON s.tier = tl.tier
LEFT JOIN (
    SELECT
        tenant_id,
        SUM(quantity * unit_price) as monthly_overages
    FROM usage_records
    WHERE DATE_FORMAT(period_start, '%Y-%m') = DATE_FORMAT(NOW(), '%Y-%m')
    GROUP BY tenant_id
) overage ON s.organization_id = (SELECT organization_id FROM tenants WHERE id = overage.tenant_id LIMIT 1)
WHERE s.status IN ('active', 'trialing')
GROUP BY s.tier
ORDER BY FIELD(s.tier, 'starter', 'pro', 'enterprise');
```

### MRR Growth Rate

```sql
-- Month-over-month MRR growth
WITH monthly_mrr AS (
    SELECT
        DATE_FORMAT(current_period_start, '%Y-%m') as month,
        SUM(tl.price_monthly_cents) / 100 as mrr
    FROM subscriptions s
    JOIN tier_limits tl ON s.tier = tl.tier
    WHERE s.status IN ('active', 'trialing')
    GROUP BY month
)
SELECT
    current.month,
    current.mrr as current_mrr,
    previous.mrr as previous_mrr,
    (current.mrr - previous.mrr) as absolute_growth,
    ROUND(((current.mrr - previous.mrr) / previous.mrr * 100), 2) as growth_percentage
FROM monthly_mrr current
LEFT JOIN monthly_mrr previous
    ON previous.month = DATE_FORMAT(DATE_SUB(STR_TO_DATE(CONCAT(current.month, '-01'), '%Y-%m-%d'), INTERVAL 1 MONTH), '%Y-%m')
ORDER BY current.month DESC
LIMIT 12;
```

### Average Revenue Per User (ARPU)

```sql
-- ARPU by tier with breakdown
SELECT
    s.tier,
    COUNT(DISTINCT s.organization_id) as customers,
    -- Base subscription revenue
    AVG(tl.price_monthly_cents / 100) as avg_base_revenue,
    -- Average overage revenue
    AVG(COALESCE(overage.monthly_overages, 0)) as avg_overage_revenue,
    -- Average addon revenue (when marketplace is implemented)
    -- AVG(COALESCE(addons.monthly_addons, 0)) as avg_addon_revenue,
    -- Total ARPU
    (AVG(tl.price_monthly_cents / 100) + AVG(COALESCE(overage.monthly_overages, 0))) as total_arpu
FROM subscriptions s
JOIN tier_limits tl ON s.tier = tl.tier
LEFT JOIN (
    SELECT
        tenant_id,
        SUM(quantity * unit_price) as monthly_overages
    FROM usage_records
    WHERE DATE_FORMAT(period_start, '%Y-%m') = DATE_FORMAT(NOW(), '%Y-%m')
    GROUP BY tenant_id
) overage ON s.organization_id = (SELECT organization_id FROM tenants WHERE id = overage.tenant_id LIMIT 1)
WHERE s.status IN ('active', 'trialing')
GROUP BY s.tier;
```

---

## 2. Customer Acquisition Metrics

### Customer Acquisition Cost (CAC)

```sql
-- CAC by channel (requires marketing spend tracking table)
-- Assuming we add a marketing_campaigns table

CREATE TABLE marketing_campaigns (
    id UUID PRIMARY KEY,
    name VARCHAR(255),
    channel VARCHAR(100), -- 'paid_search', 'social', 'content', 'referral', 'direct'
    spend_cents INT,
    period_start DATE,
    period_end DATE,
    created_at TIMESTAMP
);

CREATE TABLE customer_attribution (
    id UUID PRIMARY KEY,
    organization_id UUID REFERENCES organizations(id),
    campaign_id UUID REFERENCES marketing_campaigns(id),
    source VARCHAR(100),
    medium VARCHAR(100),
    attributed_at TIMESTAMP
);

-- CAC calculation
SELECT
    mc.channel,
    SUM(mc.spend_cents) / 100 as total_spend,
    COUNT(DISTINCT ca.organization_id) as customers_acquired,
    (SUM(mc.spend_cents) / 100) / COUNT(DISTINCT ca.organization_id) as cac
FROM marketing_campaigns mc
LEFT JOIN customer_attribution ca
    ON mc.id = ca.campaign_id
WHERE mc.period_start >= DATE_SUB(NOW(), INTERVAL 3 MONTH)
GROUP BY mc.channel
ORDER BY cac ASC;
```

### Conversion Funnel Analysis

```sql
-- Trial to paid conversion rate
SELECT
    COUNT(*) as total_trials,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as converted,
    ROUND((SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) / COUNT(*) * 100), 2) as conversion_rate,
    AVG(DATEDIFF(
        CASE WHEN status = 'active' THEN current_period_start ELSE NULL END,
        created_at
    )) as avg_days_to_convert
FROM subscriptions
WHERE trial_ends_at IS NOT NULL
    AND created_at >= DATE_SUB(NOW(), INTERVAL 6 MONTH);
```

---

## 3. Customer Retention Metrics

### Monthly Churn Rate

```sql
-- Customer churn rate by cohort
WITH monthly_cohorts AS (
    SELECT
        DATE_FORMAT(created_at, '%Y-%m') as cohort_month,
        COUNT(*) as cohort_size
    FROM subscriptions
    GROUP BY cohort_month
),
churned_customers AS (
    SELECT
        DATE_FORMAT(s.created_at, '%Y-%m') as cohort_month,
        DATE_FORMAT(s.cancelled_at, '%Y-%m') as churn_month,
        COUNT(*) as churned_count
    FROM subscriptions s
    WHERE s.cancelled_at IS NOT NULL
    GROUP BY cohort_month, churn_month
)
SELECT
    mc.cohort_month,
    mc.cohort_size,
    COALESCE(SUM(cc.churned_count), 0) as total_churned,
    ROUND((COALESCE(SUM(cc.churned_count), 0) / mc.cohort_size * 100), 2) as churn_rate
FROM monthly_cohorts mc
LEFT JOIN churned_customers cc ON mc.cohort_month = cc.cohort_month
GROUP BY mc.cohort_month, mc.cohort_size
ORDER BY mc.cohort_month DESC
LIMIT 12;
```

### Customer Lifetime Value (LTV)

```sql
-- LTV calculation by tier
SELECT
    s.tier,
    COUNT(DISTINCT s.organization_id) as customers,
    AVG(tl.price_monthly_cents / 100) as avg_monthly_revenue,
    AVG(DATEDIFF(
        COALESCE(s.cancelled_at, NOW()),
        s.created_at
    ) / 30) as avg_lifetime_months,
    (AVG(tl.price_monthly_cents / 100) * AVG(DATEDIFF(
        COALESCE(s.cancelled_at, NOW()),
        s.created_at
    ) / 30)) as estimated_ltv
FROM subscriptions s
JOIN tier_limits tl ON s.tier = tl.tier
GROUP BY s.tier;
```

### Net Revenue Retention (NRR)

```sql
-- Net Revenue Retention (expansion - churn)
WITH cohort_revenue AS (
    SELECT
        DATE_FORMAT(s.created_at, '%Y-%m') as cohort,
        s.organization_id,
        tl.price_monthly_cents / 100 as initial_mrr,
        (
            SELECT price_monthly_cents / 100
            FROM tier_limits
            WHERE tier = (
                SELECT tier FROM subscriptions s2
                WHERE s2.organization_id = s.organization_id
                ORDER BY created_at DESC
                LIMIT 1
            )
        ) as current_mrr
    FROM subscriptions s
    JOIN tier_limits tl ON s.tier = tl.tier
    WHERE s.created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
)
SELECT
    cohort,
    COUNT(*) as cohort_size,
    SUM(initial_mrr) as initial_cohort_mrr,
    SUM(current_mrr) as current_cohort_mrr,
    ROUND((SUM(current_mrr) / SUM(initial_mrr) * 100), 2) as nrr_percentage
FROM cohort_revenue
GROUP BY cohort
ORDER BY cohort DESC;
```

---

## 4. Product Engagement Metrics

### Feature Adoption Rate

```sql
-- Feature adoption by tier
SELECT
    t.tier,
    COUNT(DISTINCT t.id) as total_tenants,
    -- Sites created
    COUNT(DISTINCT CASE WHEN sites_count > 0 THEN t.id END) as tenants_with_sites,
    ROUND(COUNT(DISTINCT CASE WHEN sites_count > 0 THEN t.id END) / COUNT(DISTINCT t.id) * 100, 2) as site_adoption_rate,
    -- SSL enabled
    COUNT(DISTINCT CASE WHEN ssl_sites > 0 THEN t.id END) as tenants_with_ssl,
    ROUND(COUNT(DISTINCT CASE WHEN ssl_sites > 0 THEN t.id END) / COUNT(DISTINCT t.id) * 100, 2) as ssl_adoption_rate,
    -- Backups configured
    COUNT(DISTINCT CASE WHEN backup_count > 0 THEN t.id END) as tenants_with_backups,
    ROUND(COUNT(DISTINCT CASE WHEN backup_count > 0 THEN t.id END) / COUNT(DISTINCT t.id) * 100, 2) as backup_adoption_rate,
    -- Team collaboration
    COUNT(DISTINCT CASE WHEN team_size > 1 THEN t.id END) as tenants_with_teams,
    ROUND(COUNT(DISTINCT CASE WHEN team_size > 1 THEN t.id END) / COUNT(DISTINCT t.id) * 100, 2) as team_adoption_rate
FROM tenants t
LEFT JOIN (
    SELECT tenant_id, COUNT(*) as sites_count
    FROM sites
    GROUP BY tenant_id
) s ON t.id = s.tenant_id
LEFT JOIN (
    SELECT tenant_id, COUNT(*) as ssl_sites
    FROM sites
    WHERE ssl_enabled = 1
    GROUP BY tenant_id
) ssl ON t.id = ssl.tenant_id
LEFT JOIN (
    SELECT site_id, COUNT(*) as backup_count
    FROM site_backups
    GROUP BY site_id
) b ON b.site_id IN (SELECT id FROM sites WHERE tenant_id = t.id)
LEFT JOIN (
    SELECT organization_id, COUNT(*) as team_size
    FROM users
    GROUP BY organization_id
) u ON u.organization_id = t.organization_id
WHERE t.status = 'active'
GROUP BY t.tier;
```

### Daily/Weekly/Monthly Active Users

```sql
-- Create user activity tracking table
CREATE TABLE user_activity_log (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    activity_type VARCHAR(100), -- 'login', 'site_create', 'backup_create', etc.
    activity_at TIMESTAMP,
    INDEX idx_user_activity(user_id, activity_at)
);

-- DAU/WAU/MAU calculation
SELECT
    'Daily' as period,
    COUNT(DISTINCT user_id) as active_users
FROM user_activity_log
WHERE activity_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)

UNION ALL

SELECT
    'Weekly' as period,
    COUNT(DISTINCT user_id) as active_users
FROM user_activity_log
WHERE activity_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)

UNION ALL

SELECT
    'Monthly' as period,
    COUNT(DISTINCT user_id) as active_users
FROM user_activity_log
WHERE activity_at >= DATE_SUB(NOW(), INTERVAL 30 DAY);
```

---

## 5. Usage & Quota Metrics

### Quota Utilization Analysis

```sql
-- Identify customers approaching limits (upsell opportunities)
SELECT
    t.id as tenant_id,
    t.name as tenant_name,
    t.tier,
    o.billing_email,
    -- Site usage
    t.cached_sites_count as current_sites,
    tl.max_sites as site_limit,
    ROUND((t.cached_sites_count / NULLIF(tl.max_sites, 0) * 100), 2) as site_usage_percent,
    -- Storage usage
    t.cached_storage_mb / 1024 as current_storage_gb,
    tl.max_storage_gb as storage_limit_gb,
    ROUND(((t.cached_storage_mb / 1024) / NULLIF(tl.max_storage_gb, 0) * 100), 2) as storage_usage_percent,
    -- Recommended action
    CASE
        WHEN t.cached_sites_count / NULLIF(tl.max_sites, 0) > 0.8 THEN 'Recommend upgrade - site limit'
        WHEN (t.cached_storage_mb / 1024) / NULLIF(tl.max_storage_gb, 0) > 0.8 THEN 'Recommend upgrade - storage limit'
        ELSE 'Healthy usage'
    END as recommendation
FROM tenants t
JOIN organizations o ON t.organization_id = o.id
JOIN tier_limits tl ON t.tier = tl.tier
WHERE t.status = 'active'
    AND (
        t.cached_sites_count / NULLIF(tl.max_sites, 0) > 0.7
        OR (t.cached_storage_mb / 1024) / NULLIF(tl.max_storage_gb, 0) > 0.7
    )
ORDER BY site_usage_percent DESC, storage_usage_percent DESC;
```

### Overage Revenue Tracking

```sql
-- Monthly overage revenue by metric type
SELECT
    DATE_FORMAT(period_start, '%Y-%m') as month,
    metric_type,
    COUNT(DISTINCT tenant_id) as customers_with_overages,
    SUM(quantity) as total_overage_quantity,
    SUM(quantity * unit_price) as overage_revenue,
    AVG(quantity * unit_price) as avg_overage_per_customer
FROM usage_records
WHERE period_start >= DATE_SUB(NOW(), INTERVAL 6 MONTH)
GROUP BY month, metric_type
ORDER BY month DESC, overage_revenue DESC;
```

---

## 6. Customer Health Score

### Health Score Calculation

```sql
-- Create health scores table (see REVENUE-GROWTH-STRATEGY.md for full schema)
CREATE TABLE health_scores (
    id UUID PRIMARY KEY,
    tenant_id UUID REFERENCES tenants(id),
    score INT, -- 0-100
    status VARCHAR(50), -- 'healthy', 'at_risk', 'critical', 'churning'
    factors JSON,
    calculated_at TIMESTAMP,
    INDEX idx_tenant_health(tenant_id, calculated_at)
);

-- Health score distribution
SELECT
    status,
    COUNT(*) as customer_count,
    ROUND((COUNT(*) / (SELECT COUNT(*) FROM health_scores WHERE calculated_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)) * 100), 2) as percentage,
    AVG(score) as avg_score,
    MIN(score) as min_score,
    MAX(score) as max_score
FROM health_scores
WHERE calculated_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY status
ORDER BY FIELD(status, 'healthy', 'at_risk', 'critical', 'churning');
```

### At-Risk Customer Identification

```sql
-- Customers needing immediate attention
SELECT
    t.id as tenant_id,
    t.name,
    o.billing_email,
    hs.score as health_score,
    hs.status,
    hs.factors,
    -- Last login
    MAX(ual.activity_at) as last_activity,
    DATEDIFF(NOW(), MAX(ual.activity_at)) as days_since_activity,
    -- Support tickets
    COUNT(DISTINCT st.id) as recent_tickets,
    -- Subscription status
    s.status as subscription_status,
    DATEDIFF(s.current_period_end, NOW()) as days_until_renewal
FROM tenants t
JOIN organizations o ON t.organization_id = o.id
JOIN health_scores hs ON t.id = hs.tenant_id
LEFT JOIN users u ON o.id = u.organization_id
LEFT JOIN user_activity_log ual ON u.id = ual.user_id
LEFT JOIN subscriptions s ON o.id = s.organization_id
-- LEFT JOIN support_tickets st ON t.id = st.tenant_id AND st.created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
WHERE hs.status IN ('critical', 'churning')
    AND hs.calculated_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
GROUP BY t.id, t.name, o.billing_email, hs.score, hs.status, hs.factors, s.status, s.current_period_end
ORDER BY hs.score ASC, days_until_renewal ASC;
```

---

## 7. Referral & Growth Metrics

### Referral Program Performance

```sql
-- Referral performance (when implemented)
CREATE TABLE referral_codes (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    code VARCHAR(50) UNIQUE,
    type ENUM('customer', 'affiliate', 'partner'),
    commission_percent DECIMAL(5,2),
    usage_count INT DEFAULT 0,
    total_revenue_cents INT DEFAULT 0,
    total_commissions_cents INT DEFAULT 0,
    status ENUM('active', 'suspended', 'inactive'),
    created_at TIMESTAMP
);

CREATE TABLE referrals (
    id UUID PRIMARY KEY,
    referral_code_id UUID REFERENCES referral_codes(id),
    referred_organization_id UUID REFERENCES organizations(id),
    status ENUM('pending', 'qualified', 'converted', 'churned'),
    converted_at TIMESTAMP,
    created_at TIMESTAMP
);

-- Referral metrics
SELECT
    rc.type,
    COUNT(DISTINCT rc.id) as active_referrers,
    SUM(rc.usage_count) as total_referrals,
    SUM(CASE WHEN r.status = 'converted' THEN 1 ELSE 0 END) as converted_referrals,
    ROUND((SUM(CASE WHEN r.status = 'converted' THEN 1 ELSE 0 END) / SUM(rc.usage_count) * 100), 2) as conversion_rate,
    SUM(rc.total_revenue_cents) / 100 as total_revenue_generated,
    SUM(rc.total_commissions_cents) / 100 as total_commissions_paid,
    (SUM(rc.total_revenue_cents) / 100) - (SUM(rc.total_commissions_cents) / 100) as net_revenue
FROM referral_codes rc
LEFT JOIN referrals r ON rc.id = r.referral_code_id
WHERE rc.status = 'active'
GROUP BY rc.type;
```

### Viral Coefficient

```sql
-- Viral coefficient calculation
WITH new_customers AS (
    SELECT
        DATE_FORMAT(created_at, '%Y-%m') as month,
        COUNT(*) as organic_signups
    FROM organizations
    WHERE created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
        AND id NOT IN (SELECT referred_organization_id FROM referrals)
    GROUP BY month
),
referred_customers AS (
    SELECT
        DATE_FORMAT(r.created_at, '%Y-%m') as month,
        COUNT(*) as referred_signups
    FROM referrals r
    WHERE r.created_at >= DATE_SUB(NOW(), INTERVAL 12 MONTH)
    GROUP BY month
)
SELECT
    nc.month,
    nc.organic_signups,
    COALESCE(rc.referred_signups, 0) as referred_signups,
    ROUND((COALESCE(rc.referred_signups, 0) / nc.organic_signups), 2) as viral_coefficient
FROM new_customers nc
LEFT JOIN referred_customers rc ON nc.month = rc.month
ORDER BY nc.month DESC;
```

---

## 8. Marketplace Metrics (Future)

### Marketplace Revenue & Adoption

```sql
-- Marketplace performance (when implemented)
CREATE TABLE marketplace_products (
    id UUID PRIMARY KEY,
    name VARCHAR(255),
    category VARCHAR(100),
    price_monthly_cents INT,
    commission_percent DECIMAL(5,2),
    install_count INT DEFAULT 0,
    created_at TIMESTAMP
);

CREATE TABLE site_addons (
    id UUID PRIMARY KEY,
    site_id UUID REFERENCES sites(id),
    product_id UUID REFERENCES marketplace_products(id),
    status ENUM('active', 'inactive'),
    installed_at TIMESTAMP
);

-- Marketplace metrics
SELECT
    mp.category,
    COUNT(DISTINCT mp.id) as products,
    SUM(mp.install_count) as total_installs,
    COUNT(DISTINCT sa.site_id) as active_subscriptions,
    SUM(mp.price_monthly_cents * sa.active_count) / 100 as monthly_revenue,
    SUM(mp.price_monthly_cents * sa.active_count * mp.commission_percent / 100) / 100 as commission_revenue
FROM marketplace_products mp
LEFT JOIN (
    SELECT product_id, COUNT(*) as active_count
    FROM site_addons
    WHERE status = 'active'
    GROUP BY product_id
) sa ON mp.id = sa.product_id
GROUP BY mp.category
ORDER BY monthly_revenue DESC;
```

---

## Dashboard Implementation

### Recommended Tools

1. **Grafana** - Already integrated, can add business metric dashboards
2. **Metabase** - Open-source BI tool for SQL-based dashboards
3. **Tableau/Looker** - Enterprise BI (for larger scale)
4. **Custom Laravel Dashboard** - Build with Livewire

### Sample Grafana Dashboard Panels

```yaml
# grafana-business-dashboard.yaml
dashboard:
  title: "CHOM Business Metrics"
  panels:
    - title: "MRR Trend"
      type: graph
      datasource: mysql

    - title: "ARPU by Tier"
      type: stat
      datasource: mysql

    - title: "Churn Rate"
      type: gauge
      datasource: mysql
      thresholds:
        - value: 0
          color: green
        - value: 5
          color: yellow
        - value: 8
          color: red

    - title: "Customer Health Distribution"
      type: piechart
      datasource: mysql
```

---

## Automated Reporting

### Daily Executive Email

```php
// File: app/Console/Commands/SendDailyMetricsReport.php
class SendDailyMetricsReport extends Command
{
    public function handle()
    {
        $metrics = [
            'mrr' => $this->getMRR(),
            'new_customers_today' => $this->getNewCustomers(),
            'churned_customers_today' => $this->getChurnedCustomers(),
            'health_score_avg' => $this->getAvgHealthScore(),
            'at_risk_customers' => $this->getAtRiskCount(),
        ];

        Mail::to('executives@chom.io')->send(
            new DailyMetricsReport($metrics)
        );
    }
}
```

### Weekly Business Review

```php
// File: app/Console/Commands/SendWeeklyBusinessReview.php
class SendWeeklyBusinessReview extends Command
{
    public function handle()
    {
        $report = [
            'mrr_growth' => $this->calculateMRRGrowth(),
            'customer_growth' => $this->calculateCustomerGrowth(),
            'churn_analysis' => $this->analyzeChurn(),
            'feature_adoption' => $this->getFeatureAdoption(),
            'upsell_opportunities' => $this->identifyUpsellOpportunities(),
            'at_risk_customers' => $this->getAtRiskCustomers(),
        ];

        // Generate PDF report
        $pdf = PDF::loadView('reports.weekly-business-review', $report);

        Mail::to('leadership@chom.io')->send(
            new WeeklyBusinessReview($pdf)
        );
    }
}
```

---

## API Endpoints for Real-Time Metrics

```php
// File: routes/api.php
Route::prefix('metrics')->group(function () {
    Route::get('/mrr', [MetricsController::class, 'getMRR']);
    Route::get('/arpu', [MetricsController::class, 'getARPU']);
    Route::get('/churn', [MetricsController::class, 'getChurnRate']);
    Route::get('/health-scores', [MetricsController::class, 'getHealthScores']);
    Route::get('/at-risk', [MetricsController::class, 'getAtRiskCustomers']);
    Route::get('/upsell-opportunities', [MetricsController::class, 'getUpsellOpportunities']);
});
```

---

## Conclusion

These metrics and queries provide a comprehensive view of CHOM's business health. Key implementation steps:

1. **Create missing tables** (health_scores, user_activity_log, marketing_campaigns)
2. **Set up scheduled jobs** for metric calculation
3. **Build Grafana dashboards** for real-time visibility
4. **Automate reporting** for executive team
5. **Create alerts** for critical metrics (churn spike, MRR drop, etc.)

Focus on the metrics that drive the 8 revenue features outlined in REVENUE-GROWTH-STRATEGY.md.
