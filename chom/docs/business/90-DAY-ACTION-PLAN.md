# CHOM 90-Day Revenue Growth Action Plan

## Overview

This action plan prioritizes the highest-ROI features from the Revenue Growth Strategy for immediate implementation over the next 90 days.

**Goal:** Increase MRR by 25% and reduce churn by 15% within 90 days.

---

## Week 1-2: Foundation & Quick Wins

### Day 1-3: Analytics Setup
**Owner:** Engineering Lead
**Impact:** Visibility into all metrics

- [ ] Create database tables for business metrics tracking
  - `user_activity_log` table
  - `health_scores` table
  - `customer_milestones` table
- [ ] Implement activity tracking middleware
- [ ] Set up Grafana business metrics dashboard
- [ ] Create SQL views for key metrics (MRR, ARPU, churn)

**Deliverable:** Real-time business metrics dashboard accessible to leadership

---

### Day 4-7: Usage-Based Pricing Transparency
**Owner:** Product Manager + Full-stack Developer
**Impact:** +$6K MRR in 90 days, improved customer satisfaction

**Phase 1: Customer Visibility**
- [ ] Build usage overview dashboard (Livewire component)
  ```
  /home/calounx/repositories/mentat/chom/app/Livewire/Billing/UsageOverview.php
  ```
- [ ] Show current usage vs. included allowances
- [ ] Display estimated monthly bill with breakdown
- [ ] Add upgrade savings calculator

**Phase 2: Proactive Alerts**
- [ ] Email at 80% of quota usage
- [ ] Email at 100% with overage pricing
- [ ] In-app notification system
- [ ] Weekly usage summary emails

**Phase 3: Billing Logic**
- [ ] Update `UsageBasedBillingService.php`
- [ ] Implement Stripe usage metering for overages
- [ ] Add overage line items to invoices

**Code Changes:**
```bash
# Files to create/modify
touch app/Livewire/Billing/UsageOverview.php
touch app/Services/Billing/UsageBasedBillingService.php
touch app/Mail/UsageThresholdAlert.php
touch resources/views/livewire/billing/usage-overview.blade.php
```

**Success Metrics:**
- 80%+ of customers view usage dashboard in first month
- 35%+ of customers exceed base allowances
- Customer complaints about unexpected charges: 0

---

### Day 8-14: Customer Analytics Dashboard (Pro Tier Feature)
**Owner:** Full-stack Developer
**Impact:** +$4K MRR, 15% increase in Starter→Pro upgrades

**Features to Build:**
1. **Cost Trends**
   - Monthly spend breakdown
   - Cost per site analysis
   - 3-month forecast

2. **Performance Insights**
   - Average response time per site
   - Uptime percentage
   - Traffic trends (from observability stack)

3. **Optimization Recommendations**
   - Underutilized sites
   - Upgrade opportunities
   - Resource optimization tips

**Implementation:**
```bash
# New service
touch app/Services/Analytics/CustomerAnalyticsService.php

# Livewire components
touch app/Livewire/Analytics/CostTrends.php
touch app/Livewire/Analytics/PerformanceInsights.php
touch app/Livewire/Analytics/Recommendations.php

# Views
mkdir -p resources/views/livewire/analytics
touch resources/views/livewire/analytics/dashboard.blade.php
```

**Integration Points:**
- Pull data from Prometheus (site performance)
- Pull data from Loki (request logs)
- Calculate costs from `usage_records` table
- Generate recommendations based on usage patterns

**Success Metrics:**
- 60%+ of Pro customers use analytics weekly
- 20%+ of Starter customers upgrade for analytics
- 8+ NPS increase from Pro customers

---

## Week 3-4: Referral Program Launch

### Day 15-21: Referral Infrastructure
**Owner:** Backend Developer
**Impact:** -$3.5K CAC monthly, 10+ new customers/month

**Database Schema:**
```sql
-- Run migration
php artisan make:migration create_referral_tables
```

```php
// Migration content
Schema::create('referral_codes', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('user_id')->constrained();
    $table->string('code', 50)->unique();
    $table->enum('type', ['customer', 'affiliate', 'partner']);
    $table->decimal('commission_percent', 5, 2)->default(20.00);
    $table->integer('usage_count')->default(0);
    $table->integer('total_revenue_cents')->default(0);
    $table->integer('total_commissions_cents')->default(0);
    $table->enum('status', ['active', 'suspended', 'inactive'])->default('active');
    $table->timestamp('expires_at')->nullable();
    $table->timestamps();
});

Schema::create('referrals', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('referral_code_id')->constrained();
    $table->foreignUuid('referred_organization_id')->constrained('organizations');
    $table->enum('status', ['pending', 'qualified', 'converted', 'churned'])->default('pending');
    $table->timestamp('converted_at')->nullable();
    $table->timestamp('first_payment_at')->nullable();
    $table->integer('lifetime_value_cents')->default(0);
    $table->integer('commissions_paid_cents')->default(0);
    $table->timestamps();
});
```

**Services to Build:**
```bash
touch app/Services/Referral/ReferralService.php
touch app/Services/Referral/CommissionCalculator.php
touch app/Livewire/Referral/Dashboard.php
```

**Key Functions:**
- Auto-generate referral codes for all customers
- Track referral attribution during signup
- Apply 25% discount to referred customers
- Give $50 credit to referrers
- Calculate and track commissions for affiliates

---

### Day 22-28: Referral Marketing Launch
**Owner:** Marketing Manager
**Impact:** Brand awareness, viral growth

**Tasks:**
- [ ] Create referral landing page
- [ ] Email existing customers about referral program
- [ ] Design social sharing assets
  - Pre-written tweets
  - LinkedIn post templates
  - Email templates
- [ ] Build affiliate onboarding flow
- [ ] Create referral program FAQ

**Email Campaign:**
```
Subject: Give $50, Get $50 - Refer Friends to CHOM

Body:
Love CHOM? Share it with colleagues and get rewarded!

Your Referral Link: https://chom.io/ref/YOUR_CODE

When your referral subscribes:
- They get 25% off for 3 months
- You get $50 account credit

No limits. Unlimited referrals.

[Share Now]
```

**Success Metrics:**
- 15%+ of customers generate referral link
- 5%+ of new signups from referrals in first month
- 50+ affiliate applications

---

## Week 5-6: Customer Success Automation

### Day 29-35: Health Score System
**Owner:** Full-stack Developer
**Impact:** 15% churn reduction, 5%+ upgrade rate increase

**Implementation:**
```bash
touch app/Services/CustomerSuccess/HealthScoreService.php
touch app/Services/CustomerSuccess/InterventionService.php
touch app/Console/Commands/CalculateHealthScores.php
```

**Health Score Factors:**
1. **Engagement (40 points)**
   - Login frequency
   - Site activity
   - Feature usage

2. **Value Realization (30 points)**
   - Sites created
   - Backups configured
   - Team members invited

3. **Billing Health (20 points)**
   - Payment status
   - Usage trends
   - Upgrade/downgrade signals

4. **Support Signals (10 points)**
   - Ticket volume
   - Satisfaction scores

**Automated Interventions:**
```php
// app/Services/CustomerSuccess/InterventionService.php

class InterventionService
{
    public function processDaily(): void
    {
        // Calculate health scores for all tenants
        // Trigger interventions based on score

        // Healthy (80-100): Success email
        // At Risk (60-79): Engagement email + offer help
        // Critical (40-59): Personal outreach from CS team
        // Churning (0-39): Win-back offer + account review
    }
}
```

---

### Day 36-42: Milestone Tracking & Onboarding
**Owner:** Full-stack Developer
**Impact:** 25% improvement in activation rate

**Milestones to Track:**
- First site created (target: within 24 hours)
- SSL enabled (target: within 48 hours)
- First backup (target: within 72 hours)
- Team member invited (target: within 7 days)
- 5 sites created (Starter tier upgrade trigger)

**Onboarding Email Sequence:**

**Day 0 (Signup):**
```
Subject: Welcome to CHOM - Let's get your first site live

Checklist:
☐ Create your first WordPress site (5 minutes)
☐ Configure SSL certificate (automatic)
☐ Set up daily backups

[Get Started]
```

**Day 3 (No activity):**
```
Subject: Need help getting started?

We noticed you haven't created a site yet.
Need help? Reply to this email or:

[Watch 2-min Tutorial]
[Schedule Onboarding Call]
```

**Day 7 (Success):**
```
Subject: You're doing great!

Congratulations on deploying your first site! 🎉

Next steps to get more value:
☐ Invite your team
☐ Connect observability dashboard
☐ Set up staging environment

[Continue Setup]
```

---

## Week 7-8: Migration Service Launch

### Day 43-49: DIY Migration Tool
**Owner:** Backend Developer
**Impact:** 20% improvement in trial→paid conversion

**Build:**
1. **Migration Analysis Tool**
   - Scan source site (URL + credentials)
   - Detect platform (WordPress, Laravel, HTML)
   - Estimate migration time and compatibility

2. **Automated Migration Job**
   - WordPress import from URL
   - Database migration
   - File transfer via FTP/SSH
   - Post-migration validation

**Implementation:**
```bash
touch app/Services/Migration/MigrationService.php
touch app/Services/Migration/WordPressMigrator.php
touch app/Jobs/MigrationJob.php
touch app/Livewire/Migration/MigrationWizard.php

php artisan make:migration create_migrations_table
```

**Migration Table Schema:**
```php
Schema::create('migrations', function (Blueprint $table) {
    $table->uuid('id')->primary();
    $table->foreignUuid('site_id')->constrained();
    $table->string('source_url');
    $table->string('source_platform');
    $table->enum('service_level', ['diy', 'assisted', 'concierge']);
    $table->enum('status', ['pending', 'analyzing', 'in_progress', 'completed', 'failed']);
    $table->timestamp('scheduled_at')->nullable();
    $table->timestamp('started_at')->nullable();
    $table->timestamp('completed_at')->nullable();
    $table->text('source_credentials_encrypted')->nullable();
    $table->json('migration_log')->nullable();
    $table->string('stripe_payment_id')->nullable();
    $table->integer('amount_cents')->nullable();
    $table->timestamps();
});
```

---

### Day 50-56: Paid Migration Services
**Owner:** Product Manager + Customer Success
**Impact:** +$2.5K MRR, improved conversion rate

**Service Tiers:**
1. **DIY Migration** - Free
   - Self-service tool
   - Documentation
   - Community support

2. **Assisted Migration** - $49/site
   - Pre-migration consultation
   - Monitored migration
   - Post-migration verification
   - 1-week support

3. **Concierge Migration** - $199/site
   - White-glove service
   - DNS management
   - Email migration
   - 30-day support
   - Migration guarantee

**Marketing Materials:**
```
Landing Page: /migrate-from-[competitor]
- Cloudways
- Kinsta
- WP Engine
- SiteGround
- Bluehost
```

**Promotion:**
- Free migration credit for annual plans
- First 100 customers: 50% off assisted migration
- "Switch in 24 hours or your money back" guarantee

---

## Week 9-12: Marketplace Foundation

### Day 57-70: Marketplace Infrastructure
**Owner:** Senior Full-stack Developer
**Impact:** +$5K MRR by day 90, foundation for long-term ecosystem

**Phase 1: Database & Core Services**
```bash
php artisan make:migration create_marketplace_tables

touch app/Models/MarketplaceProduct.php
touch app/Models/SiteAddon.php
touch app/Models/MarketplaceSubscription.php
touch app/Services/Marketplace/MarketplaceService.php
```

**Database Schema:**
```sql
-- See full schema in REVENUE-GROWTH-STRATEGY.md
-- Key tables: marketplace_products, site_addons, marketplace_subscriptions
```

**Phase 2: First 5 Add-ons**

**Free Integrations (Starter+):**
1. **Cloudflare CDN** - One-click setup
2. **SendGrid Email** - SMTP configuration
3. **Google Analytics** - Tracking code injection

**Premium Add-ons (CHOM-branded):**
4. **Advanced Analytics** - $29/mo (already built)
5. **Priority Backups** - $19/mo
   - Hourly backups (vs daily)
   - 90-day retention (vs 7-day)
   - Instant restore

**Implementation Timeline:**
- Days 57-63: Database & core marketplace service
- Days 64-70: First 3 free integrations
- Days 71-77: First 2 premium add-ons
- Days 78-84: Testing & refinement
- Days 85-90: Soft launch to Pro/Enterprise customers

---

### Day 71-84: Marketplace UI/UX
**Owner:** Frontend Developer
**Impact:** User experience, conversion optimization

**Build:**
1. **Marketplace Browse Page**
   - Category filters
   - Search functionality
   - Featured add-ons
   - "Recommended for you" section

2. **Add-on Detail Pages**
   - Description & screenshots
   - Pricing & features
   - Reviews/ratings
   - Installation instructions
   - "Install Now" button

3. **Installed Add-ons Manager**
   - Active add-ons list
   - Configuration settings
   - Usage statistics
   - Uninstall option

**Files to Create:**
```bash
mkdir -p app/Livewire/Marketplace
touch app/Livewire/Marketplace/Browse.php
touch app/Livewire/Marketplace/ProductDetail.php
touch app/Livewire/Marketplace/InstalledAddons.php

mkdir -p resources/views/livewire/marketplace
touch resources/views/livewire/marketplace/browse.blade.php
touch resources/views/livewire/marketplace/product-detail.blade.php
touch resources/views/livewire/marketplace/installed-addons.blade.php
```

**Success Metrics:**
- 30%+ of Pro customers browse marketplace
- 20%+ install at least 1 free addon
- 10%+ subscribe to at least 1 paid addon

---

## Week 13: Launch Week

### Day 85-90: Coordinated Feature Launch
**Owner:** Product Manager + Marketing
**Impact:** Maximum visibility and adoption

**Launch Sequence:**

**Monday:**
- Email: "Introducing CHOM Marketplace"
- Blog post: "5 Essential Add-ons for Your Sites"
- Social media campaign

**Tuesday:**
- Email: "Understanding Your Usage - New Analytics"
- Blog post: "How to Optimize Your Hosting Costs"
- In-app announcements

**Wednesday:**
- Email: "Refer Friends, Get Rewarded"
- Blog post: "CHOM Referral Program Guide"
- Affiliate outreach

**Thursday:**
- Email: "Free Migration Service"
- Blog post: "How to Migrate from [Competitor]"
- Comparison landing pages

**Friday:**
- Wrap-up email: "Your Guide to New CHOM Features"
- Customer success webinar
- Press release

---

## Success Metrics & Tracking

### Week-by-Week Targets

**Weeks 1-2:**
- [ ] Metrics dashboard live
- [ ] Usage tracking implemented
- [ ] 500+ dashboard views

**Weeks 3-4:**
- [ ] Customer analytics launched
- [ ] 10+ Starter→Pro upgrades
- [ ] 100+ analytics sessions

**Weeks 5-6:**
- [ ] Referral program live
- [ ] 50+ referral codes generated
- [ ] 5+ referral signups

**Weeks 7-8:**
- [ ] Health scores calculated daily
- [ ] 20+ at-risk customers identified
- [ ] 10+ interventions sent

**Weeks 9-10:**
- [ ] Migration tool launched
- [ ] 10+ DIY migrations completed
- [ ] 5+ paid migrations

**Weeks 11-12:**
- [ ] Marketplace launched
- [ ] 5 add-ons available
- [ ] 20+ addon installations

**Week 13:**
- [ ] All features launched
- [ ] Press coverage secured
- [ ] Customer webinar completed

---

## Resource Allocation

### Team Requirements

**Engineering (60% of effort):**
- 1 Senior Full-stack Developer (100% allocated)
- 1 Backend Developer (80% allocated)
- 1 Frontend Developer (60% allocated)

**Product (20% of effort):**
- 1 Product Manager (50% allocated)
- 1 Product Designer (40% allocated)

**Marketing (10% of effort):**
- 1 Marketing Manager (30% allocated)
- 1 Content Writer (20% allocated)

**Customer Success (10% of effort):**
- 1 CS Manager (30% allocated)

**Total Team Cost:** ~$120K for 90 days

---

## Expected Results (Day 90)

### Revenue Impact
- **MRR Increase:** +$15K (25% growth)
- **New Revenue Streams:**
  - Usage overages: +$6K
  - Analytics add-on: +$4K
  - Marketplace: +$2K
  - Migration services: +$3K

### Customer Metrics
- **Churn Reduction:** From 8% to 6.8% (-15%)
- **Upgrade Rate:** From 5% to 7% (+40%)
- **Referral Signups:** 10+ per month
- **Trial Conversion:** From 30% to 36% (+20%)

### Product Metrics
- **Feature Adoption:**
  - Usage dashboard: 80%+
  - Customer analytics: 60%+
  - Referrals: 15%+
  - Marketplace: 30%+

---

## Risk Mitigation

### Technical Risks
**Risk:** Migration tool complexity delays launch
**Mitigation:** Start with WordPress-only, expand later

**Risk:** Marketplace integration issues
**Mitigation:** Begin with 3 simple integrations, test thoroughly

### Business Risks
**Risk:** Customer confusion with new pricing
**Mitigation:** Clear communication, grandfather existing customers

**Risk:** Low referral program adoption
**Mitigation:** Generous rewards, simplified sharing

### Operational Risks
**Risk:** Support volume increase
**Mitigation:** Comprehensive documentation, in-app guidance

---

## Communication Plan

### Internal Updates
- **Daily:** Standup with engineering team
- **Weekly:** All-hands progress update
- **Bi-weekly:** Leadership review

### Customer Communication
- **Week 1:** "What's Coming" teaser email
- **Week 6:** Mid-development update
- **Week 13:** Launch week campaign
- **Ongoing:** Feature adoption emails

---

## Next Steps (After Day 90)

### Q2 Priorities
1. **White-label Program** - Enterprise segment expansion
2. **API Platform** - Developer ecosystem
3. **Advanced Customer Success** - Predictive churn prevention
4. **Marketplace Expansion** - 20+ add-ons, partner program

### Long-term Vision
- 1,000+ customers by end of Year 1
- $1M ARR milestone
- 30% market share in WordPress hosting for agencies
- Recognized leader in hosting observability

---

## Appendix: Quick Reference

### File Locations
- Revenue strategy: `/home/calounx/repositories/mentat/chom/docs/business/REVENUE-GROWTH-STRATEGY.md`
- Metrics dashboard: `/home/calounx/repositories/mentat/chom/docs/business/METRICS-DASHBOARD.md`
- This action plan: `/home/calounx/repositories/mentat/chom/docs/business/90-DAY-ACTION-PLAN.md`

### Key Commands
```bash
# Run migrations
php artisan migrate

# Calculate health scores (daily)
php artisan health:calculate

# Send usage alerts (hourly)
php artisan usage:check-thresholds

# Process referrals (daily)
php artisan referrals:process

# Generate weekly business report
php artisan reports:weekly-business
```

### Important Metrics URLs (once deployed)
- Business dashboard: https://chom.io/admin/metrics
- Customer analytics: https://chom.io/analytics
- Marketplace: https://chom.io/marketplace
- Referral dashboard: https://chom.io/referrals
