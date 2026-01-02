# CHOM Business Intelligence Dashboards

This directory contains three comprehensive business intelligence dashboards designed to provide actionable insights for data-driven decision-making.

## Dashboard Overview

### 1. Business KPI Dashboard
**File:** `1-business-kpi-dashboard.json`
**Focus:** Revenue, customer economics, and core business health metrics

This dashboard helps executives and business leaders track the fundamental health and growth of the business.

### 2. Customer Success Dashboard
**File:** `2-customer-success-dashboard.json`
**Focus:** Customer health, engagement, satisfaction, and support metrics

This dashboard enables customer success teams to proactively manage customer relationships and prevent churn.

### 3. Growth & Marketing Dashboard
**File:** `3-growth-marketing-dashboard.json`
**Focus:** Acquisition channels, campaign performance, and growth metrics

This dashboard helps marketing teams optimize spend, identify best-performing channels, and track growth initiatives.

---

## Dashboard 1: Business KPI Dashboard

### Key Metrics Explained

#### Revenue Metrics

**Monthly Recurring Revenue (MRR)**
- **What it is:** Total predictable monthly revenue from all subscriptions
- **Why it matters:** Primary indicator of business health and growth trajectory
- **How to interpret:**
  - Steady upward trend = healthy growth
  - Flat or declining = need to increase new customers or reduce churn
- **Target:** 10-20% month-over-month growth for SaaS businesses

**MRR Growth Rate**
- **What it is:** Month-over-month percentage change in MRR
- **Formula:** `((Current MRR - Previous MRR) / Previous MRR) * 100`
- **Why it matters:** Measures acceleration or deceleration of revenue growth
- **Healthy range:** 5-15% for established businesses, 15-30% for early-stage

**Revenue per Customer (ARPC)**
- **What it is:** Average monthly revenue generated per customer
- **Formula:** `Total MRR / Total Customers`
- **Why it matters:** Indicates pricing effectiveness and upsell success
- **Action items:**
  - Low ARPC: Consider pricing increase or better tier segmentation
  - Increasing ARPC: Successful upselling or feature adoption

#### Customer Economics

**Customer Acquisition Cost (CAC)**
- **What it is:** Total cost to acquire one new customer
- **Formula:** `Total Marketing & Sales Spend / New Customers Acquired`
- **Why it matters:** Determines marketing efficiency and profitability
- **Benchmarks:**
  - Low-touch SaaS: $100-$400
  - Mid-market SaaS: $500-$2,000
  - Enterprise SaaS: $5,000-$50,000+
- **Red flags:** CAC increasing faster than ARPC

**Customer Lifetime Value (LTV)**
- **What it is:** Predicted total revenue from a customer over their lifetime
- **Formula:** `(ARPC / Monthly Churn Rate)`
- **Why it matters:** Determines how much you can spend on acquisition
- **Healthy ratio:** LTV should be 3x or higher than CAC

**LTV:CAC Ratio**
- **What it is:** Relationship between customer value and acquisition cost
- **Interpretation:**
  - < 1:1 = Unsustainable, losing money on each customer
  - 1:1 to 3:1 = Weak, need to improve
  - 3:1 to 5:1 = Good, sustainable growth
  - > 5:1 = Excellent, consider investing more in growth
- **Action items:**
  - Low ratio: Reduce CAC or increase retention/pricing
  - High ratio: Opportunity to invest more aggressively in acquisition

#### Retention & Churn

**Monthly Churn Rate**
- **What it is:** Percentage of customers lost each month
- **Formula:** `(Customers Lost / Total Customers at Start of Period) * 100`
- **Why it matters:** Directly impacts growth and profitability
- **Benchmarks:**
  - Excellent: < 2%
  - Good: 2-5%
  - Concerning: 5-7%
  - Critical: > 7%
- **Red flags:** Increasing churn rate, especially among high-value customers

**Retention Rate**
- **What it is:** Percentage of customers retained over a period
- **Formula:** `100 - Churn Rate`
- **Why it matters:** Shows product stickiness and customer satisfaction
- **Target:** > 95% monthly retention for healthy SaaS

#### Engagement Metrics

**Daily Active Users (DAU)**
- **What it is:** Unique users who perform key actions each day
- **Why it matters:** Indicates product engagement and value delivery
- **How to track:** Define "active" based on meaningful product interactions

**Weekly Active Users (WAU)**
- **What it is:** Unique users active in a 7-day period
- **Use case:** Better for products with weekly usage patterns

**Monthly Active Users (MAU)**
- **What it is:** Unique users active in a 30-day period
- **DAU/MAU Ratio:** Indicates engagement frequency
  - > 20% = very engaged user base
  - 10-20% = moderate engagement
  - < 10% = low engagement, investigate drop-off

#### Conversion Funnel

**Sign-up to Activation**
- **What it is:** % of sign-ups who complete onboarding and reach "aha moment"
- **Target:** > 60%
- **Action items if low:**
  - Simplify onboarding
  - Improve first-run experience
  - Add product tours or tooltips

**Activation to Trial**
- **What it is:** % of activated users who start a trial
- **Target:** > 70%
- **Optimization:** Clear value proposition, easy trial start

**Trial to Paid Conversion**
- **What it is:** % of trial users who become paying customers
- **Benchmarks:**
  - Excellent: > 40%
  - Good: 25-40%
  - Needs improvement: < 25%
- **Improvement strategies:**
  - Engage users during trial
  - Demonstrate ROI early
  - Reduce friction in upgrade process
  - Time-based follow-ups

### Using This Dashboard

**Daily Review:**
- Check MRR and growth rate
- Monitor active users (DAU)
- Review churn events

**Weekly Review:**
- Analyze funnel conversion rates
- Assess trial-to-paid conversion
- Review customer growth trends

**Monthly Review:**
- Deep dive into LTV:CAC ratio
- Analyze cohort retention
- Review forecasts and adjust targets
- Strategic planning based on trends

**When to Take Action:**
- MRR growth < 5%: Boost acquisition or reduce churn
- Churn > 5%: Investigate customer satisfaction and product issues
- LTV:CAC < 3: Optimize marketing spend or improve retention
- Trial conversion < 25%: Improve product onboarding and engagement

---

## Dashboard 2: Customer Success Dashboard

### Key Metrics Explained

#### Health & Satisfaction

**Customer Health Score**
- **What it is:** Composite score (0-100) indicating customer relationship health
- **Typical components:**
  - Product usage frequency (30%)
  - Feature adoption breadth (25%)
  - Support ticket volume (15%)
  - Payment history (15%)
  - Engagement score (15%)
- **Score ranges:**
  - 80-100: Excellent - upsell opportunity, request referral
  - 60-80: Healthy - maintain relationship
  - 40-60: At Risk - proactive outreach needed
  - 0-40: Critical - immediate intervention required
- **Action items:**
  - Critical customers: Schedule call within 24 hours
  - At-risk customers: Send engagement campaign
  - Excellent customers: Ask for case study or referral

**Net Promoter Score (NPS)**
- **What it is:** Measures customer loyalty and likelihood to recommend
- **How it's calculated:**
  - Survey: "How likely are you to recommend CHOM? (0-10)"
  - Promoters (9-10): Enthusiastic supporters
  - Passives (7-8): Satisfied but not enthusiastic
  - Detractors (0-6): Unhappy customers
  - NPS = % Promoters - % Detractors
- **Score interpretation:**
  - > 70: World-class
  - 50-70: Excellent
  - 30-50: Good
  - 0-30: Needs improvement
  - < 0: Critical issues
- **Best practices:**
  - Survey quarterly or biannually
  - Follow up with detractors immediately
  - Ask for specific feedback
  - Close the loop with all respondents

**Customer Satisfaction (CSAT)**
- **What it is:** Immediate satisfaction after specific interactions
- **Typical question:** "How satisfied were you with [experience]?" (1-5)
- **When to measure:**
  - After support ticket resolution
  - After onboarding completion
  - After major feature releases
  - After billing/renewal
- **Benchmarks:**
  - 4.5+: Excellent
  - 4.0-4.5: Good
  - 3.5-4.0: Acceptable
  - < 3.5: Concerning
- **Difference from NPS:** CSAT measures satisfaction with specific touchpoints, while NPS measures overall loyalty

#### Engagement & Usage

**Customer Engagement Score**
- **What it is:** Metric tracking how actively customers use the product
- **Typical factors:**
  - Login frequency
  - Time spent in product
  - Feature usage breadth
  - API calls made
  - Team member invitations
- **Why it matters:** High engagement correlates with retention
- **Action items:**
  - Low engagement: Trigger re-engagement campaign
  - Decreasing engagement: Early warning sign, reach out
  - High engagement: Opportunity for expansion

**Feature Adoption Rates**
- **What it is:** Percentage of customers using each feature
- **Why it matters:**
  - Validates product development priorities
  - Identifies training opportunities
  - Higher feature adoption = higher retention
- **Interpretation:**
  - Core features: Should be > 80%
  - Advanced features: 30-50% is typical
  - New features: Track growth rate
- **Action items:**
  - Low adoption: Improve discoverability, add in-app guidance
  - High adoption: Double down on similar features

**Time to First Value**
- **What it is:** Days from sign-up to achieving first success milestone
- **Why it matters:** Faster time-to-value = higher retention
- **Benchmarks:**
  - Excellent: < 1 day
  - Good: 1-3 days
  - Needs improvement: > 7 days
- **Optimization strategies:**
  - Pre-populate demo data
  - Guided quick-start flows
  - Automated setup assistants
  - Video tutorials for first actions

#### Support Metrics

**Support Ticket Volume**
- **What it is:** Number of support requests over time
- **Why it matters:**
  - Spike = product issue or confusing feature
  - Decreasing = improving product or documentation
  - Per-customer ratio indicates product complexity
- **Healthy ratio:** < 0.3 tickets per customer per month

**Resolution Time by Priority**
- **What it is:** Average time to resolve tickets at each priority level
- **Typical SLAs:**
  - Critical: < 2 hours
  - High: < 8 hours
  - Medium: < 24 hours
  - Low: < 72 hours
- **Why it matters:** Affects customer satisfaction and retention
- **Action items:** If missing SLAs, consider staffing or process improvements

**First Response Time**
- **What it is:** Time from ticket creation to first agent response
- **Target:** < 1 hour for all priorities
- **Why it matters:** Customers value quick acknowledgment even if resolution takes longer

### Using This Dashboard

**Daily Monitoring:**
- Review critical health score customers
- Check open ticket volume
- Monitor CSAT scores from recent interactions

**Weekly Analysis:**
- Identify at-risk customers for outreach
- Review feature adoption trends
- Analyze support ticket patterns

**Monthly Reviews:**
- Calculate and trend NPS
- Deep dive into customer segments
- Create customer success campaigns
- Report on health score improvements

**Quarterly Planning:**
- Comprehensive NPS survey
- Customer success strategy adjustment
- Resource allocation based on metrics
- Identify product improvement priorities

**Red Flags:**
- NPS < 30: Significant product or service issues
- Health score declining: Customer at risk of churn
- Support tickets increasing: Product usability issues
- Low feature adoption: Poor onboarding or unclear value

---

## Dashboard 3: Growth & Marketing Dashboard

### Key Metrics Explained

#### Acquisition Metrics

**Total Sign-ups**
- **What it is:** New user registrations over a time period
- **Why it matters:** Top-of-funnel health indicator
- **Tracking:** Monitor trends, not just absolute numbers
- **Healthy pattern:** Consistent upward trend

**Sign-up Growth Rate**
- **What it is:** Week-over-week or month-over-month sign-up increase
- **Formula:** `((Current Period - Previous Period) / Previous Period) * 100`
- **Benchmarks:**
  - Early stage: 20%+ weekly growth
  - Growth stage: 10-20% monthly growth
  - Mature: 5-10% monthly growth

**Activation Rate**
- **What it is:** % of sign-ups who complete activation (first meaningful action)
- **Why it matters:** Bridges acquisition to engagement
- **Benchmarks:**
  - Excellent: > 70%
  - Good: 50-70%
  - Needs work: < 50%
- **Optimization:**
  - Streamline onboarding
  - Add product tours
  - Personalize first experience
  - Remove friction points

#### Channel Analysis

**User Acquisition by Channel**
- **Channels to track:**
  - **Organic Search:** SEO traffic from Google, Bing
  - **Paid Ads:** Google Ads, Facebook Ads, LinkedIn Ads
  - **Referral:** Customer referrals and partnerships
  - **Direct:** URL typed directly, bookmarks
  - **Social Media:** Organic social traffic
  - **Email:** Marketing campaigns
  - **Content:** Blog, guides, resources
- **Why it matters:** Identifies most effective acquisition sources
- **Action items:**
  - Double down on best-performing channels
  - Test and optimize underperforming channels
  - Diversify to reduce dependency on single channel

**Cost Per Acquisition (CPA) by Channel**
- **What it is:** Average cost to acquire one user per channel
- **Formula:** `Channel Spend / New Users from Channel`
- **Why it matters:** Identifies most cost-effective channels
- **Optimization:**
  - Shift budget from high-CPA to low-CPA channels
  - Acceptable CPA depends on LTV
  - Track CPA trends over time

**Marketing ROI by Channel**
- **What it is:** Revenue generated vs. marketing spend per channel
- **Formula:** `Revenue from Channel / Marketing Spend on Channel`
- **Interpretation:**
  - ROI > 3:1 = Good
  - ROI > 5:1 = Excellent, invest more
  - ROI < 1:1 = Losing money, optimize or cut
- **Considerations:**
  - Include time-to-payback in analysis
  - Brand building has long-term ROI
  - Attribution can be complex

#### Campaign Performance

**Email Campaign Metrics**
- **Open Rate:**
  - Benchmarks: 15-25% for B2B SaaS
  - Improve with: Better subject lines, send time optimization, list segmentation
- **Click-Through Rate (CTR):**
  - Benchmarks: 2-5% for B2B SaaS
  - Improve with: Clear CTAs, relevant content, mobile optimization
- **Conversion Rate:**
  - Benchmarks: 1-5% depending on goal
  - Improve with: Landing page optimization, offer strength, urgency
- **Best practices:**
  - A/B test subject lines
  - Segment audiences
  - Personalize content
  - Mobile-first design

**Landing Page Conversion Rates**
- **What it is:** % of visitors who complete desired action
- **Benchmarks:**
  - Above average: > 10%
  - Average: 5-10%
  - Below average: < 5%
- **Optimization checklist:**
  - Clear, compelling headline
  - Strong value proposition
  - Social proof (testimonials, logos)
  - Minimal form fields
  - Clear CTA
  - Fast load time
  - Mobile responsive

#### Viral & Referral Growth

**Virality Coefficient (K-factor)**
- **What it is:** Number of new users each existing user brings
- **Formula:** `(# of invitations sent per user) × (% conversion rate of invites)`
- **Interpretation:**
  - K > 1: Viral growth! Each user brings more than one new user
  - K = 1: Self-sustaining but not growing virally
  - K < 1: Not viral, need other growth channels
- **How to improve:**
  - Make sharing easy and rewarding
  - Build network effects into product
  - Incentivize referrals
  - Reduce friction in referral process

**Referral Program Metrics**
- **Referrals Sent:** Total invitations sent by customers
- **Referrals Completed:** Invitations that resulted in sign-ups
- **Referral Conversion Rate:** % of invites that convert
  - Benchmarks: 20-40% is strong
- **Referrals per Active User:** How engaged are users with referral program
  - Target: > 0.5 referrals per MAU
- **Optimization:**
  - Make it easy to share
  - Provide templates or pre-written messages
  - Offer two-sided incentives (reward both referrer and referred)
  - Promote the program in-app

#### Cohort Analysis

**What it is:** Tracking groups of users who signed up in the same time period

**Why it matters:**
- Identifies if retention is improving over time
- Shows impact of product changes
- Reveals seasonal patterns
- Helps predict long-term value

**How to read cohort tables:**
- Each row = a cohort (e.g., "January 2024 sign-ups")
- Each column = retention period (Month 0, 1, 2, 3, etc.)
- Values = % of original cohort still active
- Look for:
  - Retention curve shape (steep drop or gradual)
  - Improvements in newer cohorts
  - "Smile curve" (retention stabilizes after initial drop)

**Healthy patterns:**
- Month 1 retention > 60%
- Month 3 retention > 40%
- Month 12 retention > 20%
- Newer cohorts retaining better than older ones

### Using This Dashboard

**Daily Monitoring:**
- Track sign-up volume and trends
- Monitor cost per acquisition
- Review campaign performance

**Weekly Analysis:**
- Compare channel performance
- Analyze week-over-week growth
- Review A/B test results
- Optimize ad spend allocation

**Monthly Deep Dive:**
- Cohort retention analysis
- Marketing ROI by channel
- Attribution modeling
- Budget reallocation decisions
- Campaign planning for next month

**Quarterly Strategy:**
- Channel mix optimization
- Long-term cohort trends
- Marketing budget planning
- New channel experiments
- Refine ICP (Ideal Customer Profile) based on best-converting segments

**Red Flags:**
- Sign-up growth stalling: Need new channels or campaigns
- Activation rate declining: Onboarding issues
- High CPA with low conversion: Poor targeting or messaging
- Decreasing cohort retention: Product-market fit issues

---

## Metric Instrumentation Guide

To populate these dashboards, you need to track the following metrics using Prometheus. Here are the required metrics:

### Business KPI Dashboard Metrics

```prometheus
# Revenue Metrics
chom_revenue_mrr{tier="starter|professional|enterprise"}
chom_customers_total
chom_customers_new_total
chom_customers_churned_total

# Engagement Metrics
chom_users_active_daily
chom_users_active_weekly
chom_users_active_monthly

# Churn & Retention
chom_churn_rate_monthly

# Conversion Funnel
chom_funnel_signups_total
chom_funnel_activated_total
chom_funnel_trial_started_total
chom_funnel_paid_total

# Marketing Spend
chom_marketing_spend_total{period="7d|30d"}
```

### Customer Success Dashboard Metrics

```prometheus
# Health & Satisfaction
chom_customer_health_score{organization="org_name"}
chom_nps_score
chom_nps_responses{category="promoter|passive|detractor"}
chom_csat_score

# Engagement
chom_customer_engagement_score
chom_feature_users{feature="feature_name"}
chom_feature_usage_total{feature="feature_name"}
chom_user_logins_total
chom_session_duration_minutes
chom_actions_per_session

# Support
chom_support_tickets_total{status="open|in_progress|resolved",priority="critical|high|medium|low"}
chom_support_resolution_time_hours{priority="critical|high|medium|low"}

# Time to Value
chom_time_to_first_value_days
```

### Growth & Marketing Dashboard Metrics

```prometheus
# Acquisition
chom_users_total
chom_users_signups_total{channel="organic|paid|referral|direct|social"}
chom_users_activated_total

# Marketing Spend
chom_marketing_spend_total{channel="organic|paid|social",period="7d|30d"}
chom_revenue_by_channel{channel="channel_name"}

# Referrals
chom_referrals_sent_total
chom_referrals_completed_total

# Campaigns
chom_email_campaign_sent{campaign="campaign_name"}
chom_email_campaign_opened{campaign="campaign_name"}
chom_email_campaign_clicked{campaign="campaign_name"}
chom_email_campaign_converted{campaign="campaign_name"}

# Landing Pages
chom_landing_page_visits{page="page_name"}
chom_landing_page_conversions{page="page_name"}

# Cohorts
chom_cohort_retention{cohort="YYYY-MM",month_0="100",month_1="...",month_3="...",month_6="...",month_12="..."}
```

### Implementation Example (Laravel/PHP)

```php
// In your metrics collection service

use Prometheus\CollectorRegistry;
use Prometheus\Storage\Redis;

class MetricsCollector
{
    private $registry;

    public function __construct()
    {
        $this->registry = new CollectorRegistry(new Redis());
    }

    // Track MRR
    public function trackMRR($tier, $amount)
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'revenue_mrr',
            'Monthly recurring revenue by tier',
            ['tier']
        );
        $gauge->set($amount, [$tier]);
    }

    // Track customer health score
    public function trackCustomerHealth($organization, $score)
    {
        $gauge = $this->registry->getOrRegisterGauge(
            'chom',
            'customer_health_score',
            'Customer health score',
            ['organization']
        );
        $gauge->set($score, [$organization]);
    }

    // Track sign-ups
    public function trackSignup($channel)
    {
        $counter = $this->registry->getOrRegisterCounter(
            'chom',
            'users_signups_total',
            'Total user sign-ups',
            ['channel']
        );
        $counter->inc([$channel]);
    }
}
```

---

## Dashboard Import Instructions

1. **Access Grafana:**
   - Navigate to your Grafana instance
   - Login with admin credentials

2. **Import Dashboard:**
   - Click "+" in left sidebar
   - Select "Import"
   - Click "Upload JSON file"
   - Select one of the dashboard JSON files
   - Choose your Prometheus data source
   - Click "Import"

3. **Configure Data Source:**
   - Ensure Prometheus data source is named "prometheus"
   - Or update the UID in the JSON files before importing

4. **Set Refresh Rate:**
   - Default: 1 minute
   - Adjust based on your needs and data freshness requirements

5. **Configure Alerts (Optional):**
   - Set up alerts for critical metrics
   - Examples:
     - MRR growth < 5%
     - Churn rate > 7%
     - Customer health score < 40
     - NPS < 30

---

## Best Practices for Using These Dashboards

### 1. Establish Baselines
- Track metrics for at least 30 days before making major decisions
- Understand normal variance in your metrics
- Document seasonal patterns

### 2. Set Realistic Targets
- Base targets on industry benchmarks and your stage
- Make targets SMART (Specific, Measurable, Achievable, Relevant, Time-bound)
- Review and adjust quarterly

### 3. Create Review Cadences
- **Daily:** Quick check of key metrics (5 minutes)
- **Weekly:** Team review of trends and anomalies (30 minutes)
- **Monthly:** Deep dive analysis and strategy session (2 hours)
- **Quarterly:** Comprehensive business review (half day)

### 4. Focus on Trends, Not Just Numbers
- Single data points can be misleading
- Look for patterns over weeks and months
- Compare to previous periods and forecasts

### 5. Combine Quantitative and Qualitative Data
- Metrics show what is happening
- Customer conversations show why
- Combine both for complete picture

### 6. Take Action on Insights
- Dashboards are only valuable if they drive decisions
- Create action items from dashboard reviews
- Track impact of changes on metrics

### 7. Iterate and Improve
- Add custom panels for your specific needs
- Remove panels that aren't actionable
- Adjust time ranges based on your business cycle

---

## Troubleshooting

### Dashboard Not Loading
- Check Prometheus data source connection
- Verify metric names match your instrumentation
- Check Grafana logs for errors

### No Data Showing
- Confirm metrics are being collected
- Check Prometheus query browser
- Verify time range includes data
- Check label filters

### Incorrect Values
- Verify metric calculation logic
- Check for timezone issues
- Confirm aggregation functions are correct
- Validate source data

### Performance Issues
- Reduce time range for heavy queries
- Increase refresh interval
- Use recording rules for complex queries
- Consider downsampling for historical data

---

## Additional Resources

### Recommended Reading
- "Lean Analytics" by Alistair Croll and Benjamin Yoskovitz
- "Traction" by Gabriel Weinberg and Justin Mares
- "Hacking Growth" by Sean Ellis and Morgan Brown

### Tools & Integrations
- **Analytics:** Mixpanel, Amplitude, Heap
- **Customer Success:** Gainsight, ChurnZero, Totango
- **Marketing:** HubSpot, Marketo, Segment
- **Data Warehouse:** Snowflake, BigQuery, Redshift

### Support
For questions or issues with these dashboards, please contact:
- Business Analytics Team: analytics@chom.example
- DevOps Team: devops@chom.example

---

## Changelog

### Version 1.0 (2026-01-02)
- Initial release
- Business KPI Dashboard
- Customer Success Dashboard
- Growth & Marketing Dashboard
- Comprehensive documentation

---

**Happy Analyzing!** Use these dashboards to make data-driven decisions and drive sustainable growth for CHOM.
