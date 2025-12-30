# CHOM in 5 Minutes: Quick Start Guide

**Welcome!** This guide explains what CHOM is and what you can do with it - no technical jargon, just plain English.

---

**⏱️ Time Required:** 5 minutes to read
**👥 Perfect For:** Everyone - business owners, developers, operators
**🎯 What You'll Learn:** CHOM basics, what it does, and where to go next

---

## What is CHOM?

**Simple answer:** CHOM is a control panel that makes managing websites easy.

Think of it like:
- **cPanel** - but modern and automated
- **Shopify** - but you own the infrastructure
- **Heroku** - but for WordPress and Laravel

### What Can CHOM Do?

#### For Website Owners
- ✅ Create WordPress sites in 3 minutes (not hours)
- ✅ Automatic daily backups (one-click restore)
- ✅ Free SSL certificates (the padlock 🔒 in browsers)
- ✅ See how your sites perform (speed, uptime, traffic)
- ✅ Invite team members with different permission levels

#### For Developers
- ✅ Deploy Laravel applications automatically
- ✅ Full API for automation
- ✅ Built-in monitoring (Prometheus + Grafana)
- ✅ Git integration
- ✅ Multiple PHP versions (8.2, 8.4)

#### For Agencies & Hosting Providers
- ✅ Manage hundreds of client sites from one dashboard
- ✅ Automated billing with Stripe
- ✅ White-label capabilities
- ✅ Multi-tenant architecture
- ✅ Role-based access for team and clients

---

## How Does It Work?

### The Big Picture

```
┌─────────────────────────────────────────────┐
│          You (CHOM Dashboard)               │
│                                              │
│  [Create Site] [View Metrics] [Backups]     │
│   Point and click - no coding needed        │
└──────────────┬──────────────────────────────┘
               │
               │ CHOM does all the work:
               │ • Installs WordPress
               │ • Configures web server
               │ • Sets up database
               │ • Enables SSL
               │ • Creates backups
               │ • Monitors everything
               │
               ▼
┌──────────────────────────────────────────────┐
│        Your VPS Servers                      │
│                                              │
│  ┌────────────┐  ┌────────────┐            │
│  │ Site 1     │  │ Site 2     │  ...        │
│  │ mysite.com │  │ blog.com   │            │
│  └────────────┘  └────────────┘            │
│                                              │
│  All monitored, backed up, and secured      │
└──────────────────────────────────────────────┘
```

### What You Need

**To use CHOM (if someone else set it up):**
- Just a login! That's it.
- Access the dashboard in your browser
- Start creating sites immediately

**To deploy CHOM yourself:**
- 2 VPS servers (virtual computers in the cloud)
- About 30 minutes
- Basic Linux knowledge helpful (but guides walk you through everything)

**VPS providers we work with:**
- DigitalOcean ($5-20/month per server)
- Linode
- Vultr
- Hetzner
- Any provider with Debian 13

---

## What Makes CHOM Special?

### vs Traditional Hosting (cPanel, Plesk)

| Feature | Traditional Hosting | CHOM |
|---------|---------------------|------|
| **Create WordPress site** | 30-60 minutes (manual setup) | 3 minutes (automated) |
| **SSL certificates** | Manual configuration | Automatic & free |
| **Backups** | Setup cron jobs yourself | Click "Enable" - done |
| **Monitoring** | Install/configure Prometheus | Built-in, automatic |
| **Team access** | Share passwords 😱 | Role-based permissions |
| **Cost** | $30+/month per site | $29/month for 5 sites |

### vs Managed WordPress (WP Engine, Kinsta)

| Feature | Managed WordPress | CHOM |
|---------|-------------------|------|
| **Control** | Limited - their way only | Full - you own everything |
| **Lock-in** | Hard to leave | Export anytime (open source) |
| **Pricing** | $30-100/site/month | $29/month for 5 sites |
| **Monitoring** | Basic | Prometheus + Grafana |
| **Customization** | Restricted | Full server access |

### vs DIY (Manual server setup)

| Feature | DIY Setup | CHOM |
|---------|-----------|------|
| **Setup time** | Hours/days | 30 minutes |
| **Expertise needed** | Advanced Linux knowledge | Follow simple guide |
| **Mistakes** | Easy to misconfigure | Validated deployment |
| **Monitoring** | You set it up | Included automatically |
| **Updates** | Manual tracking | Automated alerts |

---

## Real-World Use Cases

### Scenario 1: Small Business Owner

**Sarah runs a boutique and wants a website**

**Traditional way:**
1. Buy hosting ($15/month)
2. Install WordPress (30 min, following tutorials)
3. Configure SSL (15 min, confusing)
4. Setup backups (30 min, if she remembers)
5. Hope it stays up (no monitoring)

**Total:** 1+ hour, ongoing maintenance stress

**With CHOM:**
1. Log in to CHOM
2. Click "Create Site"
3. Enter domain: sarahsboutique.com
4. Click "Create"
5. Wait 3 minutes - done!

**Result:** Site is live, backed up, monitored, and secure.

---

### Scenario 2: Web Agency

**DevShop manages 50 client websites**

**Without CHOM:**
- Different hosting for each client
- Multiple control panels to learn
- Manual backup management
- Client calls: "Is my site down?"
- Billing nightmare (50 different invoices)

**With CHOM:**
- All 50 sites in one dashboard
- Consistent deployment process
- Automatic backups for all sites
- Proactive alerts before clients notice
- One Stripe subscription handles all billing
- Invite clients with "Viewer" role

**Time saved:** 10-15 hours/week

---

### Scenario 3: SaaS Startup

**AppCo provides WordPress sites to customers**

**Without CHOM:**
- Custom provisioning scripts (weeks to build)
- Manual server management
- DIY monitoring setup
- Build billing system
- Handle customer support for infrastructure

**With CHOM:**
- API-driven site creation (already built)
- Auto-scaling across VPS fleet
- Built-in monitoring and logs
- Stripe integration included
- Focus on your app, not infrastructure

**Time to market:** Months → Weeks

---

## Common Questions

### Is CHOM free?

**The software:** Yes! Open source (MIT license)

**What you pay for:**
- VPS servers ($5-20/month each from providers like DigitalOcean)
- Optional: Stripe fees if you run it as a business

### Do I need technical knowledge?

**To use CHOM:** No - point and click interface
**To deploy CHOM:** Some Linux basics help, but our guides are beginner-friendly

### Can I try it without VPS servers?

Yes! Run locally on your computer:
```bash
git clone https://github.com/calounx/mentat.git
cd mentat/chom
composer install && npm install
php artisan serve
```

Takes 10 minutes. See [Getting Started Guide](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md)

### What if I already have websites?

You can:
1. Migrate them to CHOM-managed servers
2. Use CHOM's API to automate your existing setup
3. Gradually move sites over time

### Is it secure?

Yes! Built-in security:
- ✅ Automatic SSL certificates
- ✅ Two-factor authentication (2FA)
- ✅ Role-based access control
- ✅ Rate limiting on API
- ✅ Encrypted data storage
- ✅ Regular security updates

See [Security Guide](/home/calounx/repositories/mentat/chom/docs/security/application-security.md)

### What about support?

**Community support:** Free
- [GitHub Discussions](https://github.com/calounx/mentat/discussions)
- [Documentation](/home/calounx/repositories/mentat/chom/docs/README.md)
- Email: support@chom.io

**Professional support:** Contact for pricing

---

## CHOM at a Glance: Quick Reference

### Pricing Plans

When you run CHOM as a business, built-in tiers:

| Plan | Price/Month | Sites | Storage | Backups | Support |
|------|-------------|-------|---------|---------|---------|
| **Starter** | $29 | 5 | 10GB | Daily | Email |
| **Pro** | $79 | 25 | 100GB | Hourly | Priority |
| **Enterprise** | $249 | Unlimited | Unlimited | Real-time | Dedicated |

**Note:** Fully customizable in config

### Tech Stack (for developers)

- **Backend:** Laravel 12 (PHP 8.2+)
- **Frontend:** Livewire 3, Alpine.js, Tailwind CSS
- **Database:** SQLite/MySQL/PostgreSQL
- **Cache:** Redis
- **Monitoring:** Prometheus, Loki, Grafana
- **Payments:** Stripe (Laravel Cashier)

### System Requirements

**For deployment:**
- 2 VPS servers with Debian 13
- Minimum 2GB RAM each (4GB recommended)
- 20GB disk space minimum

**For local development:**
- PHP 8.2+
- Composer 2.x
- Node.js 18+
- 4GB RAM minimum

---

## What's Next? Choose Your Journey

### I Want to Use CHOM (Manage Sites)

**If CHOM is already running:**
1. Get login credentials from your admin
2. Read: [User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md)
3. Follow: [Tutorial: Your First Site](/home/calounx/repositories/mentat/chom/docs/tutorials/FIRST-SITE.md)

**Time:** 30 minutes to create your first site

---

### I Want to Deploy CHOM (Set Up Infrastructure)

**Have VPS servers ready?**
1. Follow: [30-Minute Deployment](/home/calounx/repositories/mentat/chom/deploy/QUICKSTART.md)
2. Or detailed: [Complete Deployment Guide](/home/calounx/repositories/mentat/chom/deploy/DEPLOYMENT-GUIDE.md)

**Don't have VPS yet?**
1. Read: [Operator Guide](/home/calounx/repositories/mentat/chom/docs/OPERATOR-GUIDE.md) (explains what you need)
2. Provision VPS from DigitalOcean, Linode, or Vultr
3. Then: [30-Minute Deployment](/home/calounx/repositories/mentat/chom/deploy/QUICKSTART.md)

**Time:** 30 min deployment + VPS provisioning time

---

### I Want to Develop CHOM (Contribute Code)

**Set up local development:**
1. Follow: [Getting Started Guide](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md)
2. Read: [Developer Guide](/home/calounx/repositories/mentat/chom/docs/DEVELOPER-GUIDE.md)
3. Check: [Contributing Guidelines](/home/calounx/repositories/mentat/chom/CONTRIBUTING.md)

**Time:** 1 hour to first contribution

---

### I Want to Integrate with CHOM (Use the API)

**Build custom integrations:**
1. Quick start: [API Quick Start](/home/calounx/repositories/mentat/chom/docs/API-QUICKSTART.md)
2. Full reference: [API Documentation](/home/calounx/repositories/mentat/chom/docs/API-README.md)
3. Try: [Postman Collection](/home/calounx/repositories/mentat/chom/postman_collection.json)

**Time:** 15 minutes to first API call

---

## Key Concepts Explained Simply

### Concept 1: VPS (Virtual Private Server)

**What it is:** A virtual computer in the cloud that's always on.

**Real-world analogy:**
- Shared hosting = Apartment building (you share resources)
- VPS = Townhouse (your own space, shared land)
- Dedicated server = Detached house (all yours, expensive)

**CHOM needs:** 2 VPS servers
- Server 1: Runs CHOM dashboard
- Server 2: Runs monitoring (Prometheus, Grafana)
- (You can add more servers to host more sites)

---

### Concept 2: SSH (Secure Shell)

**What it is:** A way to securely access and control a server remotely.

**Real-world analogy:** Like remote desktop, but text-based.

**In CHOM:**
- Used to deploy sites to VPS
- You don't need to use SSH manually - CHOM does it for you
- But deployment requires SSH access to your VPS

---

### Concept 3: Observability Stack

**What it is:** Monitoring system (Prometheus + Loki + Grafana)

**What it does:**
- **Prometheus:** Collects numbers (response time, CPU, memory)
- **Loki:** Stores logs (error messages, access records)
- **Grafana:** Shows pretty graphs of everything

**Real-world analogy:** Like a fitness tracker for your websites. Shows "heart rate" (CPU), "steps" (traffic), "sleep quality" (uptime).

**In CHOM:** Automatically set up for every site. No configuration needed.

---

### Concept 4: API (Application Programming Interface)

**What it is:** A way for software to talk to other software.

**Real-world analogy:**
- Dashboard = Ordering food at a restaurant
- API = Ordering food via a mobile app
- Same result, different interface

**CHOM API examples:**
```bash
# Create a site
curl -X POST /api/v1/sites -d '{"domain":"mysite.com"}'

# Create a backup
curl -X POST /api/v1/sites/123/backups
```

**Why use it:** Automation, integration with other tools

---

## Troubleshooting FAQs

### "I don't understand technical terms"

→ Check [Glossary](/home/calounx/repositories/mentat/chom/GLOSSARY.md) - every term explained simply

### "I'm not sure where to start"

→ Use [Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) guide - picks the right path for you

### "The documentation is too technical"

→ Try:
- [Tutorial: Your First Site](/home/calounx/repositories/mentat/chom/docs/tutorials/FIRST-SITE.md) - Step-by-step with screenshots
- [FAQ](/home/calounx/repositories/mentat/chom/docs/getting-started/FAQ.md) - Common questions in plain English

### "I want to see CHOM in action first"

→ Options:
1. Run locally (10 min): [Getting Started](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md)
2. Try the demo (coming soon)
3. Watch video tutorial (coming soon)

### "I'm stuck and need help"

→ Contact us:
- [GitHub Discussions](https://github.com/calounx/mentat/discussions) - Community help
- Email: support@chom.io - Direct support
- [FAQ](/home/calounx/repositories/mentat/chom/docs/getting-started/FAQ.md) - Already answered questions

---

## Visual Feature Overview

### Dashboard Preview

```
┌─────────────────────────────────────────────────────────┐
│  CHOM - Cloud Hosting & Observability Manager    [Menu] │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  📊 Overview                                             │
│  ┌─────────────┐ ┌─────────────┐ ┌──────────────┐      │
│  │ Sites: 12   │ │ Backups: 34 │ │ Storage:     │      │
│  │ Active: 11  │ │ Last: 2h ago│ │ 45GB/100GB   │      │
│  │ Creating: 1 │ │             │ │ (45% used)   │      │
│  └─────────────┘ └─────────────┘ └──────────────┘      │
│                                                          │
│  🌐 Your Sites                                          │
│  ┌────────────────────────────────────────────────┐    │
│  │ mysite.com        [WordPress] [PHP 8.2]  [✓]  │    │
│  │ blog.example.com  [WordPress] [PHP 8.2]  [✓]  │    │
│  │ app.example.com   [Laravel]   [PHP 8.4]  [✓]  │    │
│  │                                                 │    │
│  │ [+ Create New Site]                            │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  📈 Quick Actions                                       │
│  • Create backup for mysite.com                         │
│  • View metrics dashboard                               │
│  • Invite team member                                   │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Creating a Site (Simple Flow)

```
Step 1: Click "Create Site"
   ↓
Step 2: Enter domain name
   ↓
Step 3: Choose site type (WordPress/Laravel/HTML)
   ↓
Step 4: Select PHP version
   ↓
Step 5: Click "Create"
   ↓
Wait 2-3 minutes...
   ↓
✓ Site is live!
```

### Metrics Dashboard Preview

```
┌─────────────────────────────────────────────────────────┐
│  mysite.com - Metrics (Last 24 Hours)                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ⏱️  Response Time                                       │
│  ┌────────────────────────────────────────────────┐    │
│  │     ╱╲                                          │    │
│  │    ╱  ╲    ╱╲                                   │    │
│  │   ╱    ╲  ╱  ╲                                  │    │
│  │  ╱      ╲╱    ╲────                             │    │
│  │ ─────────────────────────────────────────────   │    │
│  │ Avg: 245ms  Min: 120ms  Max: 890ms             │    │
│  └────────────────────────────────────────────────┘    │
│                                                          │
│  📈 Traffic                                             │
│  Requests: 1,234  |  Bandwidth: 2.3 GB                  │
│                                                          │
│  ⚠️  Errors: 3 (0.2%)                                   │
│                                                          │
│  [View Full Dashboard in Grafana →]                     │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

---

## Success Stories (Example Use Cases)

### Freelance Developer

**Before CHOM:**
- 3-4 hours setting up each client site
- Manually configured backups (sometimes forgot)
- Client calls: "Is my site down?" (no monitoring)
- Managing 10 different hosting accounts

**After CHOM:**
- 3 minutes to deploy each site
- Automatic backups for all clients
- Proactive alerts before clients notice issues
- All sites in one dashboard

**Result:** 20 hours/month saved, happier clients

---

### Growing Agency

**Challenge:** Managing 100+ client sites across different platforms

**CHOM Solution:**
- Migrated all sites to CHOM-managed infrastructure
- Team members have role-based access
- Clients can view their own metrics (viewer role)
- Automated billing through Stripe

**Result:**
- $3,000/month saved on hosting costs
- Support tickets reduced 60%
- Can scale to 500+ sites without hiring

---

### SaaS Startup

**Product:** Provides branded WordPress sites to customers

**Built with CHOM API:**
- Customer signs up → API creates site
- Automatic provisioning in 3 minutes
- Built-in monitoring for SLA guarantees
- Stripe handles all billing

**Result:**
- Launched in 6 weeks (vs 6 months building custom)
- $50k saved on development
- Focus on product, not infrastructure

---

## Summary: Is CHOM Right for You?

### ✅ CHOM is perfect if you...

- Manage multiple WordPress or Laravel sites
- Want to automate deployment and backups
- Need monitoring without complexity
- Value open source and owning your infrastructure
- Want professional features without enterprise cost
- Run an agency or hosting business
- Are tired of manual server management

### ❌ CHOM might not fit if you...

- Only have 1-2 static websites (simpler solutions exist)
- Don't want to manage any infrastructure (try fully-managed services)
- Need Windows hosting (CHOM requires Linux)
- Want zero learning curve (there's a small setup phase)

---

## Next Steps

**Ready to start?**

1. **Choose your path:** [Start Here Guide](/home/calounx/repositories/mentat/chom/START-HERE.md)
2. **Learn the terms:** [Glossary](/home/calounx/repositories/mentat/chom/GLOSSARY.md)
3. **Get hands-on:** [Tutorial: First Site](/home/calounx/repositories/mentat/chom/docs/tutorials/FIRST-SITE.md)

**Still have questions?**

- [FAQ](/home/calounx/repositories/mentat/chom/docs/getting-started/FAQ.md) - Common questions answered
- [Community](https://github.com/calounx/mentat/discussions) - Ask the community
- [Email](mailto:support@chom.io) - Contact support

---

**Welcome to CHOM! We're excited to have you here.** 🚀

---

**Last Updated:** 2025-12-30
**Reading Time:** 5 minutes
**Maintained By:** CHOM Documentation Team

[Back to Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) | [User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md) | [All Docs](/home/calounx/repositories/mentat/chom/docs/README.md)
