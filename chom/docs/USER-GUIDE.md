# CHOM User Guide

Complete guide for using CHOM to manage your websites, backups, teams, and billing. This guide is designed for non-technical users and site administrators.

## Table of Contents

1. [Dashboard Overview](#dashboard-overview)
2. [Managing Sites](#managing-sites)
3. [Working with Backups](#working-with-backups)
4. [Team Management](#team-management)
5. [Billing and Subscriptions](#billing-and-subscriptions)
6. [Monitoring and Metrics](#monitoring-and-metrics)
7. [Account Settings](#account-settings)
8. [Common Workflows](#common-workflows)
9. [FAQ](#faq)
10. [Getting Help](#getting-help)

---

## Dashboard Overview

When you log in to CHOM, you'll see your main dashboard.

### Dashboard Sections

```
┌────────────────────────────────────────────────────┐
│  CHOM                                      [👤 Menu]│
├────────────────────────────────────────────────────┤
│  📊 Quick Stats                                     │
│  ┌────────┐ ┌─────────┐ ┌────────┐ ┌─────────┐   │
│  │Sites: 12│ │Backups  │ │Storage │ │Uptime   │   │
│  │Active: 11│ │Last: 2h │ │45/100GB│ │99.9%    │   │
│  └────────┘ └─────────┘ └────────┘ └─────────┘   │
├────────────────────────────────────────────────────┤
│  📝 Recent Activity                                 │
│  • Site mysite.com created - 2 hours ago           │
│  • Backup completed for blog.example.com           │
│  • SSL certificate renewed for shop.example.com    │
├────────────────────────────────────────────────────┤
│  ⚠️ Alerts                                          │
│  • High disk usage on Production Server 1 (80%)    │
└────────────────────────────────────────────────────┘
```

### Navigation Menu

- **Sites** - Manage your websites
- **Backups** - View and restore backups
- **VPS Servers** - Manage your servers (admin only)
- **Team** - Invite and manage team members
- **Billing** - View invoices and manage subscription
- **Settings** - Account and organization settings

---

## Managing Sites

### Viewing Your Sites

1. Click **Sites** in the sidebar
2. You'll see all sites in your organization

**Site List Columns:**
- **Domain** - The website address
- **Type** - WordPress, Laravel, or HTML
- **Status** - Active, Creating, Suspended, or Failed
- **PHP Version** - Current PHP version
- **Created** - When the site was created

### Creating a New Site

#### Step 1: Start Site Creation

1. Click **Sites** → **+ Create Site**
2. Fill in the site details

#### Step 2: Basic Information

```
Domain Name: mysite.example.com
  ℹ️ Use a domain you own. You'll need to point DNS to our servers.

Site Type: [WordPress ▼]
  • WordPress - Full CMS with admin panel
  • Laravel - PHP framework for custom apps
  • HTML - Static website hosting

PHP Version: [8.2 ▼]
  • 8.2 (Stable, recommended)
  • 8.4 (Latest)
```

#### Step 3: WordPress Settings (if applicable)

```
Site Title: My Awesome Website
Admin Username: admin
Admin Email: admin@example.com

✓ Install WooCommerce
✓ Install Yoast SEO
```

#### Step 4: Server Selection (Optional)

Leave blank for automatic server selection, or choose a specific VPS server.

#### Step 5: Create Site

1. Click **Create Site**
2. Wait 2-3 minutes for deployment
3. You'll see progress updates in real-time

**Deployment Steps:**
```
⏳ Creating site structure...
⏳ Installing WordPress...
⏳ Configuring Nginx...
⏳ Setting up PHP-FPM...
✅ Site created successfully!
```

### Accessing Your Site

After creation:

1. **View Site Details** - Click on the site name
2. **Access Admin Panel** - Click "WP Admin" button
3. **View Frontend** - Click "Visit Site" button

**Your Credentials:**
- Login URL: `https://mysite.example.com/wp-admin`
- Username: (as configured)
- Password: (sent to your email)

### Editing Site Settings

1. Go to **Sites** → Click on site name
2. Click **Settings** tab

**Available Settings:**
```
General:
  • Site Name
  • Description
  • PHP Version

Security:
  • SSL Certificate (Auto-renew)
  • Force HTTPS
  • Basic Authentication

Performance:
  • Caching Enabled
  • CDN Integration
```

### Changing PHP Version

To update PHP version:

1. Go to site **Settings** tab
2. Find **PHP Version** dropdown
3. Select new version (8.2 or 8.4)
4. Click **Update**
5. Wait 30 seconds for reconfiguration

**Note:** Test your site after upgrading PHP to ensure compatibility.

### Deleting a Site

⚠️ **Warning:** This permanently deletes all site files and databases!

1. Go to site **Settings** tab
2. Scroll to **Danger Zone**
3. Click **Delete Site**
4. Type the domain name to confirm
5. Click **Delete Permanently**

**What gets deleted:**
- All website files
- Database
- Email accounts (if configured)
- SSL certificates

**What's kept:**
- Backups (for retention period)
- Activity logs

---

## Working with Backups

### Understanding Backups

CHOM creates backups automatically and allows manual backups before major changes.

**Backup Types:**
- **Automatic** - Scheduled daily/hourly backups
- **Manual** - Created on-demand
- **Pre-Update** - Created before updates

**What's Included:**
- ✅ All website files
- ✅ Complete database
- ✅ Configuration files
- ✅ Email accounts
- ❌ Log files (excluded to save space)

### Viewing Backups

1. Go to **Sites** → Select site → **Backups** tab
2. You'll see a list of all backups

**Backup Information:**
```
Date: 2025-12-30 02:00 AM
Type: Automatic Daily
Size: 125 MB
Status: ✅ Completed
Files: 12,453
Database: 2.3 MB
```

### Creating a Manual Backup

Before making changes (updates, theme changes, etc.):

1. Go to site → **Backups** tab
2. Click **Create Backup**
3. Add description: "Before installing new plugin"
4. Click **Create**
5. Wait 1-5 minutes (depending on site size)

**Progress Indicator:**
```
⏳ Creating backup...
  ▓▓▓▓▓▓▓▓░░ 80%

  Backing up files... 10,234 files
  Backing up database... 2.1 MB
  Compressing... 125 MB → 42 MB
```

### Restoring from Backup

⚠️ **Warning:** Restoring overwrites current site data!

1. Go to site → **Backups** tab
2. Find the backup you want
3. Click **Restore**
4. Review what will be restored:
   ```
   This will restore:
   ✓ All files (12,453 files)
   ✓ Database (2.3 MB)
   ✓ Configuration

   Current data will be backed up first.
   ```
5. Click **Restore Backup**
6. Wait 1-5 minutes for completion

**Success Message:**
```
✅ Backup restored successfully!
   Your site has been restored to 2025-12-29 02:00 AM
   A backup of the previous state was created automatically.
```

### Configuring Automatic Backups

1. Go to site → **Backups** tab
2. Click **Configure**

**Backup Settings:**
```
Automatic Backups: [✓ Enabled]

Schedule:
  Frequency: [Daily ▼]
    • Hourly (Pro/Enterprise only)
    • Daily
    • Weekly

  Time: [02:00 AM ▼]

Retention:
  Keep backups for: [7 days ▼]
    • 7 days (Starter)
    • 30 days (Pro)
    • 90 days (Enterprise)

Storage:
  Primary: CHOM Storage
  Off-site: [ ] Enable S3 Backup
```

### Downloading Backups

To download a backup to your computer:

1. Go to site → **Backups** tab
2. Find the backup
3. Click **Download**
4. Choose format:
   - **ZIP** - All files and database export
   - **Database Only** - SQL export

**Download Size:**
Backups are compressed. A 125 MB site typically downloads as ~42 MB.

### Deleting Old Backups

To free up storage:

1. Go to site → **Backups** tab
2. Select backups to delete (checkbox)
3. Click **Delete Selected**
4. Confirm deletion

**Note:** You cannot delete automatic backups within the retention period.

---

## Team Management

### Understanding Roles

CHOM has 4 permission levels:

| Role | Permissions |
|------|-------------|
| **Owner** | Full access, billing, delete organization |
| **Admin** | Manage sites, backups, team members (except owner) |
| **Member** | Create/manage sites, create backups |
| **Viewer** | Read-only access to sites and metrics |

### Viewing Team Members

1. Click **Team** in sidebar
2. You'll see all members

**Member List:**
```
Name              Email                    Role     Status
John Doe          john@example.com         Owner    Active
Jane Smith        jane@example.com         Admin    Active
Bob Johnson       bob@example.com          Member   Invited (pending)
```

### Inviting Team Members

1. Go to **Team** → **Invite Member**
2. Fill in details:
   ```
   Email: colleague@example.com
   Role: [Member ▼]
   Message (optional):
     "Hey! Join our CHOM organization to help manage our sites."
   ```
3. Click **Send Invitation**

**What Happens:**
- Email sent to colleague with invitation link
- Link expires in 7 days
- They create account and automatically join your organization

### Changing Member Roles

1. Go to **Team**
2. Find the member
3. Click **Change Role**
4. Select new role
5. Click **Update**

**Restrictions:**
- Only Owner can change Admin roles
- Cannot change your own role
- Must have at least one Owner

### Removing Team Members

1. Go to **Team**
2. Find the member
3. Click **Remove**
4. Confirm removal

**What Happens:**
- Member loses access immediately
- Their created sites remain
- Their activity is logged in audit trail

---

## Billing and Subscriptions

### Understanding Your Plan

CHOM offers three tiers:

#### Starter - $29/month
- 5 sites
- 10 GB storage
- Daily backups (7 day retention)
- Email support

#### Pro - $79/month
- 25 sites
- 100 GB storage
- Hourly backups (30 day retention)
- Priority support
- Staging environments

#### Enterprise - $249/month
- Unlimited sites
- Unlimited storage
- Real-time backups (90 day retention)
- Dedicated support
- White-label option
- SLA guarantee

### Viewing Current Plan

1. Go to **Settings** → **Billing**
2. You'll see:
   ```
   Current Plan: Pro
   Status: Active
   Billing Cycle: Monthly
   Next Billing Date: Jan 15, 2025
   Amount: $79.00

   Usage This Month:
   • Sites: 12 / 25 (48%)
   • Storage: 45 GB / 100 GB (45%)
   • Bandwidth: 234 GB / 500 GB (47%)
   ```

### Upgrading Your Plan

1. Go to **Settings** → **Billing**
2. Click **Change Plan**
3. Select new plan (Pro or Enterprise)
4. Review changes:
   ```
   Upgrade to Pro

   New Features:
   ✓ 25 sites (from 5)
   ✓ 100 GB storage (from 10 GB)
   ✓ Hourly backups (from daily)
   ✓ Staging environments
   ✓ Priority support

   Billing:
   Current Plan: $29/month
   New Plan: $79/month
   Prorated Amount: $35.42 (charged today)
   Next Bill: $79 on Jan 15, 2025
   ```
5. Click **Upgrade Now**

**Immediate Changes:**
- New limits apply instantly
- Prorated charge for current period
- Next bill reflects new plan

### Downgrading Your Plan

⚠️ **Warning:** Ensure you're within new limits before downgrading!

1. Go to **Settings** → **Billing**
2. Click **Change Plan**
3. Select lower plan
4. Review impact:
   ```
   Downgrade to Starter

   Impact:
   ⚠️ Site limit: 12 active → 5 allowed
   ⚠️ Storage: 45 GB → 10 GB allowed
   ⚠️ Backups: Hourly → Daily only

   Action Required:
   • Delete or archive 7 sites
   • Free up 35 GB storage
   ```
5. Click **Downgrade at End of Billing Period**

**What Happens:**
- Current plan active until end of period
- New plan starts next billing cycle
- No prorated refund

### Viewing Invoices

1. Go to **Settings** → **Billing** → **Invoices** tab
2. You'll see all past invoices

**Invoice List:**
```
Date           Description        Amount    Status      Actions
Dec 15, 2024   Pro Plan (Monthly) $79.00    Paid        [Download]
Nov 15, 2024   Pro Plan (Monthly) $79.00    Paid        [Download]
Nov 3, 2024    Extra Storage      $5.20     Paid        [Download]
```

### Updating Payment Method

1. Go to **Settings** → **Billing** → **Payment Method** tab
2. Click **Update Card**
3. Enter new card details
4. Click **Save**

**Supported Cards:**
- Visa
- Mastercard
- American Express
- Discover

### Canceling Subscription

1. Go to **Settings** → **Billing**
2. Scroll to **Cancel Subscription**
3. Click **Cancel**
4. Provide feedback (optional)
5. Confirm cancellation

**What Happens:**
- Access continues until end of billing period
- Sites remain accessible (read-only)
- Backups retained for 30 days
- Can reactivate anytime

---

## Monitoring and Metrics

### Viewing Site Metrics

1. Go to **Sites** → Select site → **Metrics** tab

**Available Metrics:**
```
📊 Performance (Last 24 hours)

⏱️ Response Time
   Average: 245 ms
   95th percentile: 580 ms
   [Line graph showing trends]

📈 Traffic
   Total Requests: 12,456
   Unique Visitors: 3,234
   [Bar chart by hour]

💾 Bandwidth
   Total: 2.3 GB
   [Pie chart: HTML, Images, CSS, JS]

⚠️ Errors
   Count: 12 (0.1%)
   Types: 404 (10), 500 (2)
   [Error log with timestamps]
```

### Understanding Status Indicators

Sites show colored status indicators:

- 🟢 **Green** - Everything is fine
- 🟡 **Yellow** - Minor issues detected
- 🔴 **Red** - Critical issue, site may be down
- ⚪ **Gray** - Status unknown or in maintenance

### Setting Up Alerts

Get notified when issues occur:

1. Go to site → **Alerts** tab
2. Click **+ Add Alert**
3. Configure alert:
   ```
   Alert Name: High Response Time

   Condition:
   When [Response Time ▼] is [Greater Than ▼] [1000 ms]
   for [5 minutes]

   Notify:
   [✓] Email: admin@example.com
   [ ] SMS: +1 (555) 123-4567
   [ ] Slack: #alerts channel

   Severity: [Warning ▼]
   ```
4. Click **Create Alert**

**Common Alert Types:**
- Response time > 1000ms
- Error rate > 1%
- Disk usage > 80%
- Site down/unreachable
- SSL certificate expiring (7 days)

### Viewing Logs

To debug issues:

1. Go to site → **Logs** tab
2. Select log type:
   - **Application** - WordPress/Laravel logs
   - **Access** - All HTTP requests
   - **Error** - Server errors

**Log Viewer:**
```
Filter: [Last 24 hours ▼] [Error ▼]

Search: [___________________________] [Search]

Time                Level    Message
Dec 30, 02:45:23   ERROR    PHP Fatal error: Undefined function
Dec 30, 02:12:45   WARNING  Slow query detected (2.3s)
Dec 30, 01:33:12   INFO     User logged in: admin
```

**Search Examples:**
- `error` - All errors
- `404` - Not found errors
- `user:john` - Actions by user John
- `slow query` - Database performance issues

### Grafana Dashboards

For advanced monitoring:

1. Go to site → **Metrics** tab
2. Click **View in Grafana**
3. Opens Grafana dashboard in new tab

**Grafana Features:**
- Real-time metrics
- Custom time ranges
- Zoom in on specific periods
- Compare multiple sites
- Export graphs

---

## Account Settings

### Profile Settings

1. Go to **Settings** → **Profile**

**Editable Fields:**
```
Name: [John Doe_________]
Email: john@example.com (verified)
  [Change Email]

Password: ••••••••
  [Change Password]

Timezone: [(UTC-05:00) Eastern Time ▼]
Language: [English ▼]

Notifications:
[✓] Email me about site issues
[✓] Email me about backups
[ ] Email me about billing
[✓] Weekly activity summary
```

### Two-Factor Authentication (2FA)

Secure your account with 2FA:

1. Go to **Settings** → **Security**
2. Click **Enable 2FA**
3. Scan QR code with authenticator app:
   - Google Authenticator
   - Authy
   - 1Password
   - Bitwarden
4. Enter verification code
5. Save recovery codes (important!)

**Recovery Codes:**
```
Save these codes in a safe place!

1. 8d7f-3k2j-9s4l
2. 2h4k-8j3s-4k2l
3. 9s4l-2k3j-8h4k
...

Each code can be used once if you lose your phone.
```

### Organization Settings

**Owners and Admins** can manage organization settings:

1. Go to **Settings** → **Organization**

**Settings:**
```
Organization Name: [Acme Hosting________]
Website: [https://acme.com___________]
Contact Email: [support@acme.com______]

Branding (Enterprise only):
Logo: [Upload]
Primary Color: [#3B82F6]
Custom Domain: [portal.acme.com]
```

### API Access

For developers integrating with CHOM:

1. Go to **Settings** → **API**
2. Click **Create Token**
3. Configure:
   ```
   Token Name: [CI/CD Pipeline________]
   Expires: [Never ▼]
     • Never
     • 30 days
     • 90 days
     • 1 year

   Permissions:
   [✓] Read sites
   [✓] Create sites
   [ ] Delete sites
   [✓] Read backups
   [✓] Create backups
   ```
4. Click **Create**
5. Copy token (shown only once!)

**Using the Token:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://chom.io/api/v1/sites
```

---

## Common Workflows

### Workflow 1: Launching a New WordPress Site

**Time:** 15 minutes

1. **Create Site** (5 min)
   - Sites → Create Site
   - Enter domain: `mynewsite.com`
   - Type: WordPress
   - Wait for deployment

2. **Configure DNS** (5 min)
   - Go to your domain registrar
   - Add A record: `mynewsite.com` → `[Your VPS IP]`
   - Wait for DNS propagation (5-60 min)

3. **Issue SSL** (2 min)
   - Sites → mynewsite.com → SSL tab
   - Click "Issue Certificate"
   - Wait 30 seconds

4. **Customize Site** (30 min+)
   - Click "WP Admin"
   - Install theme
   - Install plugins
   - Create content

5. **Setup Backups** (1 min)
   - Backups tab → Enable automatic backups
   - Create first manual backup

### Workflow 2: Restoring from Backup After Issue

**Scenario:** Plugin broke the site

1. **Identify Issue** (2 min)
   - Notice site is broken
   - Go to Sites → Select site

2. **Find Good Backup** (1 min)
   - Backups tab
   - Find backup before installing plugin
   - Example: "Dec 29, 2025 02:00 AM" (before "Dec 29, 2025 03:15 PM" when plugin was installed)

3. **Restore** (3-5 min)
   - Click "Restore" on good backup
   - Confirm restoration
   - Wait for completion

4. **Verify** (2 min)
   - Visit site
   - Confirm it's working
   - Check admin panel

**Total Time:** 8-10 minutes

### Workflow 3: Migrating Existing Site to CHOM

**Time:** 30-60 minutes

1. **Backup Existing Site** (10 min)
   - Export WordPress (Tools → Export)
   - Download wp-content folder
   - Export database

2. **Create New Site in CHOM** (5 min)
   - Create site with same domain
   - Wait for deployment

3. **Import Content** (15-30 min)
   - FTP/SFTP into new site
   - Upload wp-content files
   - Import database via phpMyAdmin
   - Update wp-config.php if needed

4. **Test Site** (10 min)
   - Test all pages
   - Test admin panel
   - Check plugins

5. **Switch DNS** (5 min)
   - Update DNS to point to CHOM
   - Wait for propagation
   - Monitor both old and new sites

6. **Verify and Cleanup** (5 min)
   - Confirm new site working
   - Create backup
   - Keep old site for 7 days (safety)

### Workflow 4: Team Onboarding

**Time:** 10 minutes per member

1. **Invite Member** (2 min)
   - Team → Invite Member
   - Enter email and role
   - Add welcome message

2. **Member Accepts** (5 min)
   - They receive email
   - Click invitation link
   - Create account
   - Automatically added to organization

3. **Orient New Member** (3 min)
   - Show them dashboard
   - Explain their role permissions
   - Show how to create backups
   - Share relevant documentation

4. **Setup 2FA** (2 min, optional but recommended)
   - Ask them to enable 2FA
   - Save recovery codes

---

## FAQ

### General Questions

**Q: What is CHOM?**
A: CHOM (Cloud Hosting & Observability Manager) is a platform for managing WordPress and Laravel sites across multiple servers, with built-in backups and monitoring.

**Q: How many sites can I create?**
A: Depends on your plan:
- Starter: 5 sites
- Pro: 25 sites
- Enterprise: Unlimited

**Q: Can I change my plan later?**
A: Yes! Upgrade anytime (instant), downgrade at end of billing period.

**Q: Do you offer refunds?**
A: We offer a 14-day money-back guarantee for first-time subscribers.

### Site Management

**Q: How long does it take to create a site?**
A: 2-3 minutes for WordPress, 1-2 minutes for HTML sites.

**Q: Can I use my own domain?**
A: Yes! Point your domain's A record to your VPS IP address.

**Q: What PHP versions are supported?**
A: PHP 8.2 (stable) and 8.4 (latest).

**Q: Can I install WordPress plugins?**
A: Yes, you have full access to wp-admin to install any plugin.

**Q: Can I access via FTP/SFTP?**
A: Yes, SFTP credentials are in site Settings → FTP Access.

### Backups

**Q: How often are backups created?**
A: Depends on plan:
- Starter: Daily
- Pro: Hourly
- Enterprise: Real-time

**Q: How long are backups kept?**
A: Depends on plan:
- Starter: 7 days
- Pro: 30 days
- Enterprise: 90 days

**Q: Can I download backups?**
A: Yes, as ZIP files containing all files and database.

**Q: Are backups stored off-site?**
A: By default, backups are on the same infrastructure. Enterprise plans can enable S3 backup for true off-site storage.

**Q: What happens if I restore a backup?**
A: Current site data is backed up first, then replaced with the selected backup's data.

### Billing

**Q: What payment methods do you accept?**
A: Credit cards (Visa, Mastercard, Amex, Discover) via Stripe.

**Q: Can I pay annually?**
A: Not yet, but annual billing is coming in Q1 2025 with a discount.

**Q: What happens if my payment fails?**
A: We'll retry for 7 days and email you. After that, sites become read-only until payment is updated.

**Q: Can I get an invoice for accounting?**
A: Yes, all invoices are in Settings → Billing → Invoices. Download as PDF.

### Technical Issues

**Q: My site is slow. What can I do?**
A:
1. Check Metrics tab for performance data
2. Clear WordPress cache (if using caching plugin)
3. Optimize images
4. Consider upgrading to a higher-tier VPS server

**Q: I'm getting a 500 error. How do I fix it?**
A:
1. Check Logs tab for error details
2. Try disabling recent plugins
3. Restore from a backup before the issue
4. Contact support if persistent

**Q: How do I change my site's PHP version?**
A: Sites → Select site → Settings → PHP Version dropdown → Update

**Q: Can I move a site to a different server?**
A: Yes, contact support. We'll migrate it for you (Pro/Enterprise).

**Q: My SSL certificate won't install. Why?**
A:
1. Ensure DNS points to our servers (check with `dig yourdomain.com`)
2. Wait 24-48 hours after DNS change
3. Retry issuing certificate
4. Contact support if still failing

---

## Getting Help

### Self-Service Resources

1. **Documentation**
   - [Getting Started Guide](GETTING-STARTED.md)
   - [Developer Guide](DEVELOPER-GUIDE.md)
   - [Operator Guide](OPERATOR-GUIDE.md)

2. **In-App Help**
   - Click "?" icon in any section
   - Hover over fields for tooltips
   - Check "Common Issues" in Settings

3. **Community**
   - [GitHub Discussions](https://github.com/calounx/mentat/discussions)
   - Search existing questions
   - Ask new questions

### Contacting Support

**Email Support** (All plans)
- Email: support@chom.io
- Response time: 24-48 hours
- Include: Site domain, error messages, screenshots

**Priority Support** (Pro/Enterprise)
- Same email, marked priority
- Response time: 4-8 hours
- Dedicated support agent

**Dedicated Support** (Enterprise only)
- Direct phone/Slack access
- Response time: 1 hour
- Named support engineer

### Emergency Support

For critical issues (site down, data loss):

1. Email: urgent@chom.io
2. Subject: "URGENT: [Brief description]"
3. Include:
   - Your organization name
   - Affected site(s)
   - What happened
   - What you've tried

We'll respond within 1 hour (Pro/Enterprise) or 4 hours (Starter).

### Providing Helpful Information

When contacting support, include:

1. **Site Details**
   - Domain name
   - Site type (WordPress, Laravel, HTML)
   - When issue started

2. **Error Information**
   - Exact error message
   - Screenshot of error
   - Log entries (from Logs tab)

3. **Steps to Reproduce**
   - What you were doing
   - What you expected
   - What actually happened

4. **What You've Tried**
   - Troubleshooting steps already attempted
   - Any temporary fixes applied

---

## Summary

You now know how to:

- ✅ Navigate the CHOM dashboard
- ✅ Create and manage sites
- ✅ Setup and restore backups
- ✅ Manage your team
- ✅ Handle billing and subscriptions
- ✅ Monitor site performance
- ✅ Configure account settings
- ✅ Follow common workflows
- ✅ Get help when needed

**Ready for more advanced topics?**
- 🚀 [Operator Guide](OPERATOR-GUIDE.md) - Production deployment
- 💻 [Developer Guide](DEVELOPER-GUIDE.md) - Development and API
- 📖 [Getting Started](GETTING-STARTED.md) - Initial setup

**Need help?** Email support@chom.io or visit our [community discussions](https://github.com/calounx/mentat/discussions).

Happy hosting! 🚀
