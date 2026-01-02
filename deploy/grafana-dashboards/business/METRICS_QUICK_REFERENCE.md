# Business Metrics Quick Reference Guide

A concise reference for interpreting key business metrics in the CHOM dashboards.

## Revenue Metrics

| Metric | Formula | Good | Warning | Critical |
|--------|---------|------|---------|----------|
| MRR Growth Rate (MoM) | `((Current MRR - Previous MRR) / Previous MRR) * 100` | >10% | 5-10% | <5% |
| ARPC | `Total MRR / Total Customers` | Increasing | Flat | Decreasing |
| LTV:CAC Ratio | `LTV / CAC` | >5:1 | 3:1-5:1 | <3:1 |

## Customer Economics

| Metric | Formula | Benchmark | Action Threshold |
|--------|---------|-----------|------------------|
| CAC (Low-touch) | `Marketing Spend / New Customers` | $100-400 | >$500 |
| CAC Payback Period | `CAC / ARPC` | <12 months | >18 months |
| LTV | `ARPC / Monthly Churn Rate` | >$2,000 | <$500 |

## Retention & Churn

| Metric | Formula | Excellent | Good | Concerning | Critical |
|--------|---------|-----------|------|------------|----------|
| Monthly Churn | `Churned Customers / Total Customers * 100` | <2% | 2-5% | 5-7% | >7% |
| Month 1 Retention | `Active Month 1 / Initial Cohort * 100` | >80% | 60-80% | 40-60% | <40% |
| Month 12 Retention | `Active Month 12 / Initial Cohort * 100` | >40% | 20-40% | 10-20% | <10% |

## Engagement Metrics

| Metric | Formula | High Engagement | Moderate | Low |
|--------|---------|----------------|----------|-----|
| DAU/MAU Ratio | `DAU / MAU * 100` | >20% | 10-20% | <10% |
| Avg Session Duration | Time in product | >10 min | 5-10 min | <5 min |
| Actions per Session | Count of key actions | >10 | 5-10 | <5 |

## Conversion Metrics

| Stage | Formula | Excellent | Good | Needs Work |
|-------|---------|-----------|------|------------|
| Sign-up → Activation | `Activated / Sign-ups * 100` | >70% | 50-70% | <50% |
| Activation → Trial | `Trials Started / Activated * 100` | >80% | 60-80% | <60% |
| Trial → Paid | `Paid / Trials * 100` | >40% | 25-40% | <25% |
| Overall Conversion | `Paid / Sign-ups * 100` | >20% | 10-20% | <10% |

## Customer Success Metrics

| Metric | Range | Excellent | Healthy | At Risk | Critical |
|--------|-------|-----------|---------|---------|----------|
| Health Score | 0-100 | 80-100 | 60-80 | 40-60 | 0-40 |
| NPS | -100 to 100 | >70 | 50-70 | 30-50 | <30 |
| CSAT | 1-5 | >4.5 | 4.0-4.5 | 3.5-4.0 | <3.5 |

## Support Metrics

| Metric | Critical | High | Medium | Low |
|--------|----------|------|--------|-----|
| First Response Time | <30 min | <1 hour | <2 hours | <4 hours |
| Resolution Time | <2 hours | <8 hours | <24 hours | <72 hours |
| Ticket Volume per Customer | - | - | - | <0.3/month |

## Growth & Marketing Metrics

| Metric | Formula | Strong | Average | Weak |
|--------|---------|--------|---------|------|
| Activation Rate | `Activated / Sign-ups * 100` | >70% | 50-70% | <50% |
| Email Open Rate | `Opens / Sent * 100` | >25% | 15-25% | <15% |
| Email Click Rate | `Clicks / Sent * 100` | >5% | 2-5% | <2% |
| Landing Page Conversion | `Conversions / Visits * 100` | >10% | 5-10% | <5% |
| Referral Conversion | `Referral Sign-ups / Invites * 100` | >40% | 20-40% | <20% |
| Virality (K-factor) | `Invites per User * Conversion %` | >1 | 0.5-1 | <0.5 |

## Channel Performance

| Channel | Typical CPA | Good ROI | Concerning ROI |
|---------|-------------|----------|----------------|
| Organic Search | $50-150 | >8:1 | <3:1 |
| Paid Search | $100-300 | >5:1 | <2:1 |
| Social Ads | $75-250 | >6:1 | <2:1 |
| Referral | $25-75 | >10:1 | <4:1 |
| Content Marketing | $30-100 | >8:1 | <3:1 |

## Cohort Retention Benchmarks

| Time Period | SaaS Benchmark | Your Target |
|-------------|----------------|-------------|
| Month 0 | 100% | 100% |
| Month 1 | 65-75% | ___% |
| Month 3 | 45-55% | ___% |
| Month 6 | 35-45% | ___% |
| Month 12 | 25-35% | ___% |

## Action Triggers

### Immediate Action Required (Within 24 Hours)
- Customer health score drops below 40
- Critical support tickets unresolved >2 hours
- Churn spike (>2x normal rate)
- Payment failures spike
- Major product issue affecting >10% users

### Action Required (Within 1 Week)
- NPS drops below 30
- MRR growth <5% for 2 consecutive months
- Trial conversion <20%
- Support ticket backlog increasing
- Key feature adoption declining

### Review & Plan (Within 1 Month)
- LTV:CAC ratio <3:1
- Email engagement declining
- Channel ROI <2:1
- DAU/MAU ratio declining
- Activation rate <50%

## Metric Definitions Cheat Sheet

**MRR** = Monthly Recurring Revenue (predictable monthly revenue)
**ARPC** = Average Revenue Per Customer
**CAC** = Customer Acquisition Cost
**LTV** = Lifetime Value (total revenue from a customer)
**DAU** = Daily Active Users
**WAU** = Weekly Active Users
**MAU** = Monthly Active Users
**NPS** = Net Promoter Score (loyalty metric, -100 to +100)
**CSAT** = Customer Satisfaction Score (1-5 scale)
**CPA** = Cost Per Acquisition
**ROI** = Return on Investment

## Dashboard Links

1. **Business KPI Dashboard** - Revenue, economics, core metrics
2. **Customer Success Dashboard** - Health, engagement, satisfaction
3. **Growth & Marketing Dashboard** - Acquisition, campaigns, channels

## Common Questions

**Q: What metric should I focus on first?**
A: Depends on your stage:
- Pre-revenue: Activation rate, engagement
- Early revenue: Trial conversion, retention
- Growth stage: LTV:CAC, MRR growth
- Mature: NPS, expansion revenue, efficiency

**Q: How often should I check these dashboards?**
A:
- Daily: Quick glance at key metrics (5 min)
- Weekly: Team review of trends (30 min)
- Monthly: Deep analysis and planning (2 hours)

**Q: What's the single most important metric?**
A: For SaaS: **LTV:CAC ratio**. It shows if your business model is sustainable.

**Q: When should I be worried about churn?**
A: When monthly churn consistently exceeds 5%, or when it's trending upward for 3+ months.

**Q: What's a good trial-to-paid conversion rate?**
A:
- Excellent: >40%
- Good: 25-40%
- Average: 15-25%
- Needs improvement: <15%

**Q: How do I calculate CAC correctly?**
A: `Total Sales & Marketing Spend (including salaries, tools, ads) / New Customers Acquired` in that period

**Q: What if my metrics don't match benchmarks?**
A: Benchmarks are guides, not rules. Focus on:
1. Your own trends (improving or declining?)
2. Unit economics (profitable or not?)
3. Customer feedback (satisfied or not?)

## Formulas Quick Reference

### Revenue Calculations
```
MRR = Sum of all monthly recurring subscription revenue
ARR = MRR × 12
ARPC = MRR / Number of Customers
MRR Growth Rate = ((Current MRR - Previous MRR) / Previous MRR) × 100
```

### Customer Economics
```
CAC = (Sales + Marketing Costs) / New Customers Acquired
LTV = ARPC / Monthly Churn Rate
LTV:CAC Ratio = LTV / CAC
CAC Payback Period (months) = CAC / ARPC
```

### Retention & Churn
```
Churn Rate = (Customers Lost / Customers at Start) × 100
Retention Rate = 100 - Churn Rate
Cohort Retention = (Active in Period / Original Cohort Size) × 100
```

### Engagement
```
DAU/MAU Ratio = (DAU / MAU) × 100
Stickiness = How many days per week/month users are active
Session Frequency = Total Sessions / Active Users
```

### Conversion
```
Conversion Rate = (Conversions / Total Visitors) × 100
Activation Rate = (Activated Users / Sign-ups) × 100
Trial Conversion = (Paid Customers / Trial Users) × 100
```

### Marketing
```
CPA = Marketing Spend / Acquisitions
ROI = (Revenue - Cost) / Cost
K-factor = Invites per User × Invite Conversion Rate
```

---

**Print this guide and keep it handy for quick metric interpretation!**

Last Updated: 2026-01-02
