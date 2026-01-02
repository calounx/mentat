# CHOM Business Intelligence Dashboard Suite

## Quick Start

Welcome to the CHOM Business Intelligence dashboard suite. This collection provides comprehensive analytics for data-driven decision-making across revenue, customer success, and growth metrics.

### Dashboard Files

1. **1-business-kpi-dashboard.json** - Core business metrics (MRR, CAC, LTV, churn)
2. **2-customer-success-dashboard.json** - Customer health, satisfaction, engagement
3. **3-growth-marketing-dashboard.json** - Acquisition, campaigns, channel performance

### Documentation Files

- **README.md** - Complete guide with metric explanations and usage instructions
- **METRICS_QUICK_REFERENCE.md** - Pocket reference for metric benchmarks and formulas
- **IMPLEMENTATION_GUIDE.md** - Technical implementation and code examples
- **INDEX.md** - This file (quick navigation)

---

## Getting Started in 5 Minutes

### Step 1: Import Dashboards (2 minutes)

1. Open Grafana (http://your-grafana-instance:3000)
2. Click "+" → "Import" in the left sidebar
3. Upload each JSON file:
   - `1-business-kpi-dashboard.json`
   - `2-customer-success-dashboard.json`
   - `3-growth-marketing-dashboard.json`
4. Select your Prometheus data source
5. Click "Import"

### Step 2: Verify Data Source (1 minute)

1. Ensure Prometheus is configured and running
2. Check that metric endpoint is accessible: `http://your-app/metrics`
3. Verify Prometheus is scraping your application

### Step 3: Review Key Metrics (2 minutes)

Open each dashboard and verify:
- Dashboard 1: MRR, Customer count, Churn rate
- Dashboard 2: Health scores, NPS, Support metrics
- Dashboard 3: Sign-ups, Activation rate, Channel distribution

---

## Dashboard Navigation

### For Executives
**Start with:** Dashboard 1 (Business KPI Dashboard)
**Focus on:**
- MRR and growth rate
- LTV:CAC ratio
- Customer growth trends
- Revenue forecasts

**Review frequency:** Daily 5-minute check, weekly 30-minute review

### For Customer Success Managers
**Start with:** Dashboard 2 (Customer Success Dashboard)
**Focus on:**
- Customer health scores (identify at-risk customers)
- Support ticket trends
- NPS and CSAT scores
- Feature adoption rates

**Review frequency:** Daily monitoring, weekly deep dive

### For Marketing Teams
**Start with:** Dashboard 3 (Growth & Marketing Dashboard)
**Focus on:**
- Sign-up trends and activation rates
- Channel performance and ROI
- Campaign metrics
- Cohort retention

**Review frequency:** Daily campaign checks, weekly optimization

---

## Metric Priorities by Role

### CEO / Founder
**Top 5 Metrics:**
1. MRR Growth Rate
2. LTV:CAC Ratio
3. Churn Rate
4. Customer Count
5. NPS

**Dashboard:** Business KPI Dashboard
**Cadence:** Weekly review with CFO

### VP of Customer Success
**Top 5 Metrics:**
1. Customer Health Score Distribution
2. NPS
3. Support Resolution Time
4. Feature Adoption Rates
5. Time to First Value

**Dashboard:** Customer Success Dashboard
**Cadence:** Daily monitoring, weekly team review

### CMO / Head of Marketing
**Top 5 Metrics:**
1. Cost Per Acquisition by Channel
2. Marketing ROI
3. Activation Rate
4. Sign-up Trends
5. Referral Conversion Rate

**Dashboard:** Growth & Marketing Dashboard
**Cadence:** Daily for campaigns, weekly for strategy

### CFO / Finance Lead
**Top 5 Metrics:**
1. MRR and ARR
2. CAC and Payback Period
3. Revenue per Customer
4. Churn Impact on Revenue
5. Customer Lifetime Value

**Dashboard:** Business KPI Dashboard
**Cadence:** Monthly detailed review, quarterly board prep

---

## Common Use Cases

### Use Case 1: Quarterly Business Review
**Dashboards needed:** All three
**Metrics to analyze:**
- Revenue growth trajectory (Dashboard 1)
- Customer health trends (Dashboard 2)
- Acquisition efficiency (Dashboard 3)
- Cohort retention patterns (Dashboard 3)

**Recommended flow:**
1. Start with overall MRR and growth (Dashboard 1, 10 min)
2. Review customer health and satisfaction (Dashboard 2, 15 min)
3. Analyze marketing efficiency (Dashboard 3, 15 min)
4. Identify top 3 priorities for next quarter

### Use Case 2: Weekly Team Standup
**Dashboard:** Rotate weekly
**Week 1:** Business KPI Dashboard
**Week 2:** Customer Success Dashboard
**Week 3:** Growth & Marketing Dashboard
**Week 4:** Deep dive into top concern from previous weeks

**Format:**
- 5 minutes: Review key metrics
- 10 minutes: Discuss trends and anomalies
- 10 minutes: Define action items

### Use Case 3: Daily Monitoring
**Time required:** 5 minutes
**Dashboards:** Quick check across all three

**Checklist:**
- [ ] MRR stable or growing? (Dashboard 1)
- [ ] Any critical health score customers? (Dashboard 2)
- [ ] Sign-up trend normal? (Dashboard 3)
- [ ] Any metric anomalies requiring attention?

### Use Case 4: Customer Churn Investigation
**Primary dashboard:** Customer Success Dashboard
**Secondary dashboard:** Business KPI Dashboard

**Investigation flow:**
1. Identify churned customer segment (Dashboard 1)
2. Review health scores before churn (Dashboard 2)
3. Check support ticket history (Dashboard 2)
4. Analyze feature adoption patterns (Dashboard 2)
5. Compare to successful customer cohorts
6. Document findings and create action plan

### Use Case 5: Marketing Channel Optimization
**Primary dashboard:** Growth & Marketing Dashboard
**Review frequency:** Weekly

**Analysis steps:**
1. Review CPA by channel
2. Calculate ROI for each channel
3. Identify best-performing campaigns
4. Compare activation rates by source
5. Adjust budget allocation
6. Set up experiments for underperforming channels

---

## Metric Alert Thresholds

### Critical (Immediate Action Required)

| Metric | Threshold | Dashboard | Action |
|--------|-----------|-----------|--------|
| Monthly Churn Rate | >7% | Dashboard 1 | Emergency customer retention meeting |
| Customer Health Score | <40 (any customer) | Dashboard 2 | Immediate customer outreach |
| NPS | <30 | Dashboard 2 | Product/service review |
| MRR Growth | Negative for 2 months | Dashboard 1 | Strategy review |
| Support Resolution Time | >2x SLA | Dashboard 2 | Support team escalation |

### Warning (Action Within 1 Week)

| Metric | Threshold | Dashboard | Action |
|--------|-----------|-----------|--------|
| LTV:CAC Ratio | <3:1 | Dashboard 1 | Marketing efficiency review |
| Trial Conversion | <20% | Dashboard 1 | Onboarding optimization |
| Activation Rate | <50% | Dashboard 3 | UX improvement sprint |
| Feature Adoption | <30% for core features | Dashboard 2 | User education campaign |
| Email Open Rate | <15% | Dashboard 3 | Email strategy review |

### Monitor (Monthly Review)

| Metric | Threshold | Dashboard | Action |
|--------|-----------|-----------|--------|
| DAU/MAU Ratio | <10% | Dashboard 1 | Engagement initiative |
| Time to First Value | >7 days | Dashboard 2 | Onboarding streamlining |
| Referral Conversion | <20% | Dashboard 3 | Referral program optimization |
| Landing Page Conversion | <5% | Dashboard 3 | A/B testing plan |

---

## Customization Guide

### Adding Custom Panels

1. Click "Add panel" in any dashboard
2. Write your Prometheus query
3. Choose visualization type
4. Configure display options
5. Save dashboard

### Modifying Existing Panels

1. Click panel title → "Edit"
2. Adjust query, visualization, or thresholds
3. Update panel title and description
4. Save changes

### Creating Dashboard Variables

Variables allow filtering by organization, tier, or time period:

1. Dashboard settings (gear icon) → "Variables"
2. Click "Add variable"
3. Configure variable source (e.g., Prometheus label values)
4. Use variable in panel queries: `{organization="$organization"}`

### Example Custom Panels

**Panel: Revenue by Tier**
```promql
sum(chom_revenue_mrr) by (tier)
```

**Panel: Top 10 Customers by MRR**
```promql
topk(10, sum(chom_revenue_mrr) by (organization))
```

**Panel: Weekly Sign-up Growth Rate**
```promql
(increase(chom_users_signups_total[7d]) - increase(chom_users_signups_total[7d] offset 7d)) /
increase(chom_users_signups_total[7d] offset 7d) * 100
```

---

## Troubleshooting

### "No data" showing in panels

**Solutions:**
1. Check Prometheus data source connection
2. Verify metrics are being collected: `http://your-app/metrics`
3. Confirm time range includes data
4. Check Prometheus scrape status: `http://prometheus:9090/targets`

### Metrics showing unexpected values

**Solutions:**
1. Verify calculation logic in source code
2. Check for timezone mismatches
3. Review data in Prometheus query browser
4. Validate source data in database

### Dashboard performance is slow

**Solutions:**
1. Reduce time range for large queries
2. Use Prometheus recording rules for complex calculations
3. Increase dashboard refresh interval
4. Consider downsampling historical data

### Panels show different data than expected

**Solutions:**
1. Check panel query and verify metric names
2. Review aggregation functions (sum, avg, etc.)
3. Validate label filters
4. Compare with raw Prometheus data

---

## Best Practices

### 1. Establish Baselines
- Track metrics for 30+ days before making decisions
- Document normal ranges for your business
- Understand seasonal patterns

### 2. Create Review Cadences
- **Daily:** 5-minute health check
- **Weekly:** 30-minute team review
- **Monthly:** 2-hour deep dive
- **Quarterly:** Half-day strategic review

### 3. Take Action on Insights
- Dashboards are only valuable if they drive decisions
- Create action items from each review
- Track impact of changes on metrics
- Iterate based on results

### 4. Combine Quantitative and Qualitative
- Metrics show WHAT is happening
- Customer conversations show WHY
- Use both for complete understanding

### 5. Focus on Trends
- Single data points can mislead
- Look for patterns over weeks/months
- Compare to previous periods
- Track against forecasts

---

## Quick Reference Card

### Most Important Metrics (The "Rule of 5")

**For Sustainability:**
1. **LTV:CAC Ratio** - Must be >3:1
2. **Monthly Churn** - Must be <5%
3. **MRR Growth Rate** - Target >10%
4. **Trial Conversion** - Target >25%
5. **Customer Health Score** - Keep >60

**If these 5 are healthy, your business is on solid ground.**

---

## Support & Resources

### Getting Help
- **Technical Issues:** DevOps team (devops@chom.example)
- **Metric Interpretation:** Business Analytics team (analytics@chom.example)
- **Dashboard Customization:** See IMPLEMENTATION_GUIDE.md

### Further Reading
- README.md - Comprehensive metric guide
- METRICS_QUICK_REFERENCE.md - Benchmarks and formulas
- IMPLEMENTATION_GUIDE.md - Technical implementation

### External Resources
- Prometheus documentation: https://prometheus.io/docs/
- Grafana documentation: https://grafana.com/docs/
- SaaS metrics guides: https://www.saastr.com/

---

## Version History

**v1.0** (2026-01-02)
- Initial release
- 3 dashboards with 50+ panels
- Comprehensive documentation
- Implementation guides

---

## Quick Wins

### Week 1: Get Dashboards Running
- [ ] Import all 3 dashboards
- [ ] Configure Prometheus data source
- [ ] Verify basic metrics are populating
- [ ] Share dashboards with team

### Week 2: Implement Core Metrics
- [ ] Set up MRR tracking
- [ ] Configure customer counting
- [ ] Track active users
- [ ] Implement basic funnel metrics

### Week 3: Add Advanced Tracking
- [ ] Customer health score calculation
- [ ] Support metrics integration
- [ ] Marketing channel attribution
- [ ] Email campaign tracking

### Week 4: Optimize & Alert
- [ ] Set up critical alerts
- [ ] Create review cadence
- [ ] Train team on dashboards
- [ ] Document custom business logic

---

**You're ready to start making data-driven decisions!**

Begin with Dashboard 1 (Business KPI Dashboard), verify your key metrics are tracking correctly, and build from there.

Questions? Check the README.md for detailed metric explanations or the IMPLEMENTATION_GUIDE.md for technical details.
