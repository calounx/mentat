# CHOM Frequently Asked Questions

**Last Updated:** 2025-12-30

This FAQ answers the most common questions about CHOM. Can't find your answer? See [Getting Help](#still-need-help) at the bottom.

---

**⏱️ Quick Navigation:** Use your browser's search (Ctrl+F or Cmd+F) to find specific questions

---

## Quick Links - Jump to Section

- [Getting Started](#getting-started) - New to CHOM?
- [Sites & WordPress](#sites--wordpress) - Creating and managing sites
- [Backups & Recovery](#backups--recovery) - Protecting your data
- [Billing & Plans](#billing--plans) - Pricing and payments
- [Technical Issues](#technical-issues) - Troubleshooting
- [API & Integration](#api--integration) - For developers
- [Security](#security) - Safety and privacy
- [Deployment](#deployment) - Setting up CHOM

---

## Getting Started

### Q: What is CHOM?

**A:** CHOM (Cloud Hosting & Observability Manager) is a control panel that makes managing WordPress and Laravel websites easy.

**Think of it like:**
- Modern cPanel (automated, developer-friendly)
- Shopify (but you own the infrastructure)
- WP Engine (but cheaper and more flexible)

**What you can do:**
- Create WordPress sites in 3 minutes
- Automatic backups and monitoring
- Manage multiple sites from one dashboard
- Free SSL certificates
- Team collaboration with roles

→ [Learn more: Quick Start Guide](/home/calounx/repositories/mentat/chom/docs/getting-started/QUICK-START.md)

---

### Q: Do I need technical knowledge to use CHOM?

**A:** It depends what you want to do:

**To USE CHOM (manage websites):**
- **No technical knowledge needed**
- Point-and-click interface
- If you can use WordPress, you can use CHOM

**To DEPLOY CHOM (set up the infrastructure):**
- **Some Linux basics help**
- Our guides walk you through everything
- Copy-paste commands provided
- Takes 30 minutes following the guide

→ [For users: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md)
→ [For deployers: Deployment Guide](/home/calounx/repositories/mentat/chom/deploy/QUICKSTART.md)

---

### Q: How is CHOM different from other hosting solutions?

**A:** Here's a quick comparison:

| Feature | CHOM | Managed Hosts (WP Engine) | cPanel | DIY Setup |
|---------|------|---------------------------|--------|-----------|
| **Setup time** | 3 min/site | 5-10 min/site | 30-60 min/site | Hours |
| **Cost** | $29/mo for 5 sites | $30+/site/month | $15-30/site | VPS cost only |
| **Control** | Full access | Limited | Full | Full |
| **Monitoring** | Built-in | Basic | Add-on | You build it |
| **Lock-in** | None (open source) | Hard to leave | Medium | None |
| **Backups** | Automatic | Automatic | Manual setup | You set up |
| **SSL** | Automatic & free | Automatic | Manual or paid | You configure |

**Best for:**
- Agencies managing many sites
- Hosting providers
- Developers who want automation
- Anyone tired of manual setup

---

### Q: Is CHOM free?

**A:** Yes and no:

**The CHOM software:**
- ✅ 100% free and open source
- ✅ MIT license (use however you want)
- ✅ No per-site fees
- ✅ No hidden costs

**What you DO pay for:**
- VPS servers ($5-20/month per server)
  - Rent from DigitalOcean, Linode, Vultr, etc.
  - Need minimum 2 servers to run CHOM
- Optional: Stripe fees if you charge customers

**Example monthly cost:**
- 2 VPS @ $10/each = $20/month
- Manage unlimited sites
- Much cheaper than $30/site at managed hosts

---

### Q: What do I need to get started?

**To use CHOM (someone else deployed it):**
- Just a login from your admin
- Web browser
- That's it!

**To deploy CHOM yourself:**
- 2 VPS servers running Debian 13
- Basic Linux knowledge (helpful but not required)
- 30 minutes following our guide
- SSH access to your servers

**To try CHOM locally (no VPS needed):**
- Computer with Linux/macOS/Windows
- PHP 8.2+, Composer, Node.js
- 15 minutes following setup guide

→ [Local setup: Getting Started](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md)
→ [Production setup: Deployment Guide](/home/calounx/repositories/mentat/chom/deploy/QUICKSTART.md)

---

### Q: Can I try CHOM before deploying to VPS?

**A:** Yes! Run it locally on your computer:

```bash
# Takes about 10 minutes
git clone https://github.com/calounx/mentat.git
cd mentat/chom
composer install && npm install
cp .env.example .env
php artisan key:generate
touch database/database.sqlite
php artisan migrate
php artisan serve
```

Then visit http://localhost:8000

→ [Full guide: Getting Started](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md)

---

### Q: Where do I start if I'm completely new?

**A:** Follow this learning path:

1. **Read this FAQ** (you're here!) - 10 minutes
2. **Read:** [5-Minute Quick Start](/home/calounx/repositories/mentat/chom/docs/getting-started/QUICK-START.md) - Understand what CHOM is
3. **Check:** [Glossary](/home/calounx/repositories/mentat/chom/GLOSSARY.md) - Learn technical terms
4. **Choose your path:** [Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) - Pick user/developer/operator guide
5. **Get hands-on:** [Tutorial: First Site](/home/calounx/repositories/mentat/chom/docs/tutorials/FIRST-SITE.md) - Create your first website

**Total time:** About 1 hour to feel confident

---

## Sites & WordPress

### Q: How long does it take to create a website?

**A:** **2-3 minutes** from clicking "Create Site" to fully working website.

**What CHOM does automatically:**
1. Creates directory structure (10 seconds)
2. Downloads and installs WordPress (60 seconds)
3. Configures Nginx web server (20 seconds)
4. Sets up PHP-FPM (20 seconds)
5. Creates database (10 seconds)
6. Configures monitoring (20 seconds)

**Traditional manual setup:** 30-60 minutes

---

### Q: What types of sites can I create?

**A:** CHOM supports three site types:

**1. WordPress**
- Full WordPress installation
- Access to WP Admin
- Install any theme/plugin
- Ideal for: Blogs, business sites, e-commerce

**2. Laravel**
- Laravel framework applications
- For custom web apps
- Ideal for: SaaS, APIs, custom applications

**3. Static HTML**
- Plain HTML/CSS/JS websites
- Fastest performance
- Ideal for: Landing pages, documentation sites

→ [Creating sites: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#creating-a-new-site)

---

### Q: Can I use my own domain name?

**A:** Yes! Two scenarios:

**1. You own the domain:**
- Point your domain's DNS to your VPS IP
- Create site in CHOM with your domain
- Wait 5-60 minutes for DNS to propagate
- Done!

**Example DNS setup:**
```
Type: A Record
Name: @
Value: YOUR_VPS_IP
TTL: 3600
```

**2. You don't have a domain yet:**
- Create site with any domain (for testing)
- Use hosts file to access locally
- Buy domain later and update DNS

→ [DNS setup guide: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#managing-sites)

---

### Q: What PHP versions are supported?

**A:** CHOM supports:

- **PHP 8.2** (Stable - Recommended)
- **PHP 8.4** (Latest)

**Can I change PHP version later?**
- Yes! Takes 30 seconds
- Go to Site → Settings → PHP Version
- Select new version → Click Update

**Which should I use?**
- PHP 8.2: Most compatible, stable
- PHP 8.4: Latest features, slightly faster

→ [Changing PHP: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#changing-php-version)

---

### Q: Can I install WordPress plugins and themes?

**A:** Yes, absolutely! Full access to WordPress admin.

**Install plugins:**
- Log in to WP Admin (yoursite.com/wp-admin)
- Go to Plugins → Add New
- Install any plugin from WordPress.org
- Or upload custom plugins

**Install themes:**
- Go to Appearance → Themes
- Install any free or premium theme
- Upload custom themes

**No restrictions** - you have complete control.

---

### Q: Can I migrate existing WordPress sites to CHOM?

**A:** Yes! Two methods:

**Method 1: Manual migration**
1. Export from old site (WordPress export, database dump)
2. Create new site in CHOM
3. Import content to new site
4. Update DNS

**Method 2: Using plugins**
1. Install migration plugin (All-in-One WP Migration, Duplicator)
2. Export site as package
3. Import to CHOM-managed site

**Method 3: CLI (advanced)**
- Use rsync for files
- mysqldump for database
- Update wp-config.php

→ Coming soon: Automated migration tool

---

### Q: My site isn't loading. What should I check?

**A:** Follow this checklist:

**1. Check site status in CHOM**
- Is status "Active"? (not "Creating" or "Failed")

**2. Check DNS**
```bash
# Does domain point to correct IP?
dig yourdomain.com

# Or use online tool: https://dnschecker.org
```

**3. Check from CHOM server**
```bash
# Can server reach itself?
curl http://localhost
```

**4. Check logs**
- CHOM → Your Site → Logs tab
- Look for errors in:
  - Nginx error log
  - PHP error log
  - Application log

**5. Common fixes**
- DNS not updated yet (wait 30-60 min)
- Typo in domain name
- Port 80/443 blocked by firewall
- Web server not running

→ [Full troubleshooting: Getting Started](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md#troubleshooting)

---

## Backups & Recovery

### Q: How do backups work?

**A:** CHOM provides two types:

**1. Automatic Backups**
- CHOM creates these on a schedule
- Daily, weekly, or monthly (depends on your plan)
- Runs in background (doesn't slow site)
- You don't do anything - it just happens

**2. Manual Backups**
- You create these before making changes
- Click "Create Backup" button
- Takes 1-3 minutes
- Add a note: "Before updating WordPress"

**What's backed up:**
- ✅ All website files (themes, plugins, uploads)
- ✅ Database (posts, pages, users, settings)
- ✅ Configuration files

**NOT backed up:**
- ❌ Log files (to save space)
- ❌ Cache files (can be regenerated)

→ [Backup tutorial: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#working-with-backups)

---

### Q: How often are backups created?

**A:** Depends on your plan:

| Plan | Frequency | Retention |
|------|-----------|-----------|
| **Starter** | Daily (2 AM) | 7 days |
| **Pro** | Hourly | 30 days |
| **Enterprise** | Real-time | 90 days |

**Can I customize this?**
- Yes! Go to Site → Backups → Settings
- Change frequency and retention
- Example: Daily backups, keep for 14 days

---

### Q: How do I restore a backup?

**A:** Very simple:

**Step-by-step:**
1. Go to your site in CHOM dashboard
2. Click "Backups" tab
3. Find the backup you want (check date/description)
4. Click "Restore" button
5. Confirm: "Yes, restore this backup"
6. Wait 2-3 minutes

**What happens:**
- CHOM automatically creates a backup BEFORE restoring
- Then overwrites current site with backup data
- Your site is restored to that point in time

**Can I undo a restore?**
- Yes! CHOM keeps the "before restore" backup
- Restore that backup to undo

→ [Restore guide: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#restore-from-backup)

---

### Q: Can I download backups to my computer?

**A:** Yes!

1. Go to Site → Backups
2. Find the backup
3. Click "Download" button
4. Save the .tar.gz file to your computer

**Why download?**
- Extra safety (off-site backup)
- Migrate to different hosting
- Archive old sites

**File size:** Depends on site (typically 50-500 MB)

---

### Q: Where are backups stored?

**A:** Two locations:

**Default (all plans):**
- Same VPS server as your site
- Path: `/var/chom/backups/`
- Faster restores
- **Risk:** If server dies, backups gone

**Enterprise (optional):**
- AWS S3 or compatible cloud storage
- Off-site storage for safety
- Automatic synchronization
- **Benefit:** Survives server failure

**Recommendation:** Use S3 for production sites

---

### Q: What if I restore the wrong backup?

**A:** Don't worry! CHOM has your back:

**Automatic safety backup:**
- Before ANY restore, CHOM creates a backup
- Named: "Before restore - [timestamp]"
- Kept for 7 days minimum

**To undo:**
1. Go to Backups tab
2. Find "Before restore" backup
3. Restore that backup

**Your site returns to state before the wrong restore.**

---

## Billing & Plans

### Q: How much does CHOM cost?

**A:** CHOM itself is free (open source). Costs come from:

**1. Infrastructure:**
- VPS servers: $5-20/month per server
- Minimum 2 servers needed
- More servers = host more sites

**2. Optional business use:**
If you charge customers for hosting, built-in billing tiers:

| Plan | Price/Month | Sites | Storage | Backups |
|------|-------------|-------|---------|---------|
| **Starter** | $29 | 5 | 10GB | Daily |
| **Pro** | $79 | 25 | 100GB | Hourly |
| **Enterprise** | $249 | Unlimited | Unlimited | Real-time |

**Customize:** Edit `config/chom.php` to change pricing

---

### Q: Can I change my plan?

**A:** Yes, anytime!

**To upgrade:**
1. Go to Settings → Billing
2. Click "Change Plan"
3. Select higher tier (Starter → Pro → Enterprise)
4. Confirm
5. **Immediate effect** (prorated charge to credit card)

**To downgrade:**
1. Same steps
2. Takes effect next billing cycle
3. No refund for current month
4. Sites/storage must fit in new plan

---

### Q: What payment methods do you accept?

**A:** CHOM uses Stripe for payments:

**Accepted cards:**
- Visa
- Mastercard
- American Express
- Discover
- Most debit cards

**Not accepted:**
- PayPal
- Cryptocurrency
- Bank transfer
- Cash/check

**Why Stripe:** Secure, automatic billing, invoices, receipts

---

### Q: Is there a free trial?

**A:** Yes! Two options:

**1. Run CHOM yourself (truly free):**
- Open source - download and use
- Pay only for VPS servers
- No time limit
- Full features

**2. Business use (if we host for you):**
- 14-day free trial
- No credit card required
- All features included
- Cancel anytime

---

### Q: What happens if my payment fails?

**A:** Stripe will retry automatically:

**Timeline:**
1. **Day 1:** Payment fails, you get email
2. **Day 3:** First retry
3. **Day 5:** Second retry
4. **Day 7:** Final retry, urgent email
5. **Day 8:** Sites become read-only
6. **Day 14:** Sites suspended (not deleted)

**To fix:**
1. Update payment method in Settings → Billing
2. We'll retry immediately
3. Sites reactivated within minutes

**Your data is safe** - we keep it for 30 days after suspension.

---

### Q: Can I get a refund?

**A:** Yes!

**14-day money-back guarantee:**
- First-time subscribers only
- Request within 14 days of first payment
- Full refund, no questions asked
- Email: billing@chom.io

**After 14 days:**
- No refunds for unused time
- Can cancel to stop future charges
- Downgrade instead of canceling to save money

---

## Technical Issues

### Q: My site is slow. What can I do?

**A:** Follow this troubleshooting guide:

**Step 1: Check CHOM metrics**
1. Go to Site → Metrics
2. Look for bottlenecks:
   - High CPU? → Disable heavy plugins
   - High memory? → Check for memory leaks
   - Slow database? → Optimize database
   - Many errors? → Check logs

**Step 2: Quick wins**
- Clear WordPress cache (if using cache plugin)
- Optimize images (use ShortPixel or Smush)
- Disable unused plugins
- Switch to lighter theme

**Step 3: Advanced optimization**
- Enable Redis caching
- Use CDN (Cloudflare)
- Optimize database (WP-Optimize plugin)
- Upgrade VPS to more RAM

→ [Performance guide: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#monitoring-and-metrics)

---

### Q: I'm getting "500 Internal Server Error"

**A:** This means something broke on the server.

**Common causes & fixes:**

**1. PHP memory limit exceeded**
```bash
# In CHOM: Site → Settings → PHP Settings
# Increase memory_limit to 256M or 512M
```

**2. Plugin conflict**
- Disable all plugins
- Re-enable one by one to find culprit
- Remove problematic plugin

**3. Corrupted .htaccess file**
- SSH into server
- Rename .htaccess to .htaccess.bak
- WordPress will regenerate it

**4. Permissions issue**
```bash
# Fix WordPress permissions
chown -R www-data:www-data /var/www/yoursite
chmod -R 755 /var/www/yoursite
```

**How to debug:**
1. Go to Site → Logs in CHOM
2. Look in PHP Error Log
3. Error message tells you what broke

→ [Troubleshooting guide: Getting Started](/home/calounx/repositories/mentat/chom/docs/GETTING-STARTED.md#troubleshooting)

---

### Q: SSL certificate won't install

**A:** Let's Encrypt SSL needs specific conditions:

**Checklist:**
- [ ] DNS points to correct VPS IP (`dig yourdomain.com`)
- [ ] Port 80 is open (Let's Encrypt uses this)
- [ ] Port 443 is open (for HTTPS)
- [ ] Domain accessible via HTTP first
- [ ] Waited 24-48 hours after DNS change

**To fix:**

**1. Check DNS propagation**
```bash
dig yourdomain.com
# Should show your VPS IP
```
Or use: https://dnschecker.org

**2. Check ports**
```bash
# On VPS:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**3. Test HTTP access**
```bash
curl http://yourdomain.com
# Should return HTML (not error)
```

**4. Try manual SSL**
```bash
# In CHOM: Site → SSL → Issue Certificate
# Check logs for specific error
```

→ [SSL guide: User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#managing-sites)

---

### Q: How do I view logs?

**A:** CHOM provides easy log access:

**Via Dashboard:**
1. Go to Site → Logs tab
2. Select log type:
   - **Application** - WordPress/Laravel errors
   - **Access** - Visitor requests
   - **Error** - Nginx/PHP errors
3. Filter by date, severity, search

**Via SSH (advanced):**
```bash
# SSH into VPS
ssh deploy@your-vps-ip

# View logs
tail -f /var/log/nginx/yoursite.com-error.log
tail -f /var/www/yoursite.com/wp-content/debug.log
```

**What to look for:**
- PHP Fatal Errors
- Memory exhausted
- Database connection errors
- 404 errors (broken links)

---

### Q: Can I SSH into my VPS?

**A:** Yes, if you set it up!

**For CHOM-managed VPS:**
- SSH key generated during setup
- User: Usually `deploy` or `root`
- Port: 22 (default)

**To connect:**
```bash
ssh deploy@your-vps-ip
```

**What you can do:**
- View logs manually
- Run commands
- Install software
- Debug issues

**What NOT to do:**
- Don't delete CHOM files
- Don't change critical configs without knowing
- Don't stop critical services (nginx, php-fpm)

→ [SSH guide: Operator Guide](/home/calounx/repositories/mentat/chom/docs/OPERATOR-GUIDE.md)

---

## API & Integration

### Q: Does CHOM have an API?

**A:** Yes! Full REST API with OpenAPI documentation.

**What you can do:**
- Create/delete sites programmatically
- Manage backups
- View metrics
- Manage users and teams
- Automate everything in the dashboard

**API Documentation:**
- Interactive docs: http://your-chom-url/api/documentation
- OpenAPI spec: `/openapi.yaml`
- Postman collection: `/postman_collection.json`

→ [API Quick Start](/home/calounx/repositories/mentat/chom/docs/API-QUICKSTART.md)

---

### Q: How do I authenticate with the API?

**A:** Use API tokens (Bearer authentication).

**Get a token:**
1. Log in to CHOM dashboard
2. Go to Settings → API Tokens
3. Click "Create Token"
4. Copy the token (shown once!)
5. Store safely

**Use the token:**
```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://your-chom-url/api/v1/sites
```

**Token security:**
- Never commit to Git
- Rotate regularly
- Use different tokens for different apps
- Revoke compromised tokens immediately

→ [API Authentication: API Docs](/home/calounx/repositories/mentat/chom/docs/API-README.md)

---

### Q: Are there SDKs or libraries?

**A:** Not yet, but coming soon!

**Current workarounds:**
- Use API directly with curl
- Any HTTP library (axios, fetch, requests)
- Postman collection for testing

**Planned SDKs (Q2 2025):**
- PHP SDK
- JavaScript/Node.js SDK
- Python SDK

**For now:**
```javascript
// Example with fetch (JavaScript)
const response = await fetch('http://chom.io/api/v1/sites', {
  headers: {
    'Authorization': 'Bearer YOUR_TOKEN',
    'Content-Type': 'application/json'
  }
});
const sites = await response.json();
```

---

### Q: What's the API rate limit?

**A:** Varies by endpoint:

| Endpoint Type | Limit | Window |
|---------------|-------|--------|
| **Authentication** | 5 requests | Per minute |
| **General API** | 60 requests | Per minute |
| **Enterprise** | 300 requests | Per minute |

**What happens if exceeded:**
- HTTP 429 (Too Many Requests)
- Wait 60 seconds
- Retry

**How to avoid:**
- Cache responses
- Use webhooks instead of polling
- Upgrade to Enterprise for higher limits

---

### Q: Can I get webhooks for events?

**A:** Yes! Webhooks notify your app when things happen.

**Available webhooks:**
- Site created/deleted
- Backup completed
- SSL certificate renewed
- Payment succeeded/failed
- User invited

**Setup:**
1. Go to Settings → Webhooks
2. Click "Add Webhook"
3. Enter your URL
4. Select events
5. Save

**Your endpoint receives:**
```json
{
  "event": "site.created",
  "data": {
    "site_id": 123,
    "domain": "mysite.com",
    "created_at": "2025-12-30T10:00:00Z"
  }
}
```

→ [Webhooks guide: API Docs](/home/calounx/repositories/mentat/chom/docs/API-README.md)

---

## Security

### Q: Is CHOM secure?

**A:** Yes! Built-in security features:

**Authentication & Authorization:**
- ✅ Password hashing (bcrypt)
- ✅ Two-factor authentication (2FA)
- ✅ API token authentication
- ✅ Role-based access control
- ✅ Session management

**Network Security:**
- ✅ HTTPS/SSL for all traffic
- ✅ Rate limiting (prevents brute force)
- ✅ CSRF protection
- ✅ Firewall rules

**Data Security:**
- ✅ Encrypted database credentials
- ✅ SSH key encryption
- ✅ No plaintext passwords
- ✅ Audit logging

**Infrastructure:**
- ✅ Isolated environments per site
- ✅ Regular security updates
- ✅ Dependency scanning

→ [Security guide: Security Docs](/home/calounx/repositories/mentat/chom/docs/security/application-security.md)

---

### Q: Should I enable 2FA?

**A:** Yes, highly recommended!

**What is 2FA:**
- Two-Factor Authentication
- Password + code from phone app
- Much harder for hackers

**How to enable:**
1. Go to Settings → Security
2. Click "Enable 2FA"
3. Scan QR code with app (Google Authenticator, Authy)
4. Enter code to confirm
5. Save backup codes!

**When required:**
- Admins: Strongly recommended
- Regular users: Optional
- API access: Not needed (uses tokens)

---

### Q: What if I lose my 2FA device?

**A:** Use backup codes!

**When you enable 2FA:**
- CHOM shows 10 backup codes
- **SAVE THESE!** Print or store securely
- Each code works once

**If you lost codes:**
- Email: security@chom.io
- We'll verify your identity
- Reset 2FA for your account

**Prevention:**
- Save backup codes when setting up
- Register multiple devices
- Consider backup device (second phone)

---

### Q: How do I report a security issue?

**A:** Please be responsible:

**DO:**
- Email: security@chom.io
- Include detailed description
- Steps to reproduce
- Potential impact
- Give us time to fix (30 days)

**DON'T:**
- Post publicly on GitHub
- Tweet about it
- Tell others before it's fixed

**We promise:**
- Response within 24 hours
- Credit in changelog
- Potential bug bounty
- Responsible disclosure

---

## Deployment

### Q: What do I need to deploy CHOM?

**A:** Minimum requirements:

**Hardware:**
- 2 VPS servers
- 2GB RAM each (4GB recommended)
- 20GB disk space each
- Public IP addresses

**Software:**
- Debian 13 (preferred) or Ubuntu 22.04+
- SSH access
- Root or sudo user

**Skills:**
- Basic Linux command line
- Understanding of SSH
- Ability to edit text files

**Time:**
- 30 minutes following quick deploy
- 1-2 hours following detailed guide

→ [Quick deploy: Deployment Guide](/home/calounx/repositories/mentat/chom/deploy/QUICKSTART.md)

---

### Q: Why do I need 2 VPS servers?

**A:** Separation of concerns:

**Server 1: VPS Manager**
- Runs CHOM control panel (dashboard)
- Database for CHOM settings
- API endpoints
- Billing system

**Server 2: Observability Stack**
- Prometheus (metrics collection)
- Loki (log aggregation)
- Grafana (visualization)
- Monitors all sites

**Benefits:**
- Monitoring survives if VPS Manager crashes
- Better performance (separate resources)
- Easier scaling (add more site servers later)

**Can I use 1 server?**
- Not recommended for production
- Okay for testing/development
- Everything competes for resources

---

### Q: Which VPS provider should I use?

**A:** CHOM works with any Debian 13 VPS. Popular choices:

| Provider | Starting Price | Pros | Cons |
|----------|----------------|------|------|
| **DigitalOcean** | $6/month | Easy UI, good docs | More expensive |
| **Linode** | $5/month | Reliable, fast support | - |
| **Vultr** | $5/month | Many locations | UI less polished |
| **Hetzner** | €4/month | Cheapest, powerful | EU-focused |

**Recommendations:**
- **Beginners:** DigitalOcean (best docs)
- **Budget:** Hetzner
- **Reliability:** Linode
- **Global:** Vultr (most locations)

**What to look for:**
- Debian 13 available
- SSH access included
- IPv4 address
- Good network (1Gbps+)

---

### Q: How long does deployment take?

**A:** Depends on method:

**Quick Deploy (automated):**
- Configure: 5 minutes
- Validate: 2 minutes
- Deploy: 20 minutes
- **Total: ~30 minutes**

**Manual step-by-step:**
- Reading guide: 15 minutes
- Configuration: 10 minutes
- Deployment: 30-45 minutes
- **Total: ~1 hour**

**First time:**
- Add 30 minutes for learning
- Reading documentation
- Understanding concepts

**Experienced user:**
- Can deploy in 15 minutes

---

### Q: Can I deploy on Windows server?

**A:** No, CHOM requires Linux.

**Why:**
- CHOM uses Linux-specific tools (nginx, systemd)
- WordPress/PHP perform better on Linux
- Most web hosting is Linux-based

**Options:**
- Use Linux VPS (recommended)
- Use WSL2 on Windows (development only)
- Run in Docker on Windows (not recommended)

---

### Q: What if deployment fails?

**A:** Don't panic! Common issues:

**1. SSH connection fails**
- Check IP address is correct
- Verify SSH port (usually 22)
- Ensure firewall allows SSH
- Try manual connection: `ssh user@ip`

**2. Validation errors**
- Read error message carefully
- Usually tells you exactly what's wrong
- Fix and run `--validate` again

**3. Partial deployment**
- Safe to re-run deployment
- Script is idempotent (running twice is safe)
- Or: Start fresh with new VPS

**Get help:**
- Check logs in deploy directory
- [Troubleshooting guide](/home/calounx/repositories/mentat/chom/deploy/DEPLOYMENT-GUIDE.md#troubleshooting)
- [GitHub Discussions](https://github.com/calounx/mentat/discussions)

---

## Still Need Help?

### Search Documentation

**Can't find your answer?**

Try searching all docs:
1. Visit [Documentation Index](/home/calounx/repositories/mentat/chom/docs/README.md)
2. Use browser search (Ctrl+F / Cmd+F)
3. Check [Glossary](/home/calounx/repositories/mentat/chom/GLOSSARY.md) for terms

### Ask the Community

**GitHub Discussions**
- [Ask Questions](https://github.com/calounx/mentat/discussions)
- Search existing threads
- Community answers usually within hours

### Contact Support

**Email: support@chom.io**

**Include in your message:**
- What you're trying to do
- What you expected to happen
- What actually happened
- Error messages (copy-paste or screenshot)
- What you've already tried
- Your setup (CHOM version, OS, etc.)

**Response time:**
- Community: Hours to days
- Email: 1-2 business days
- Enterprise: 2-4 hours (SLA)

### Report Bugs

**GitHub Issues**
- [Report Bugs](https://github.com/calounx/mentat/issues)
- Check if already reported
- Include reproduction steps
- Add screenshots/logs

---

## Documentation Feedback

**Is this FAQ helpful?**

We want to improve! If you:
- Couldn't find your question
- Found outdated information
- Have suggestions

Please let us know:
- Email: docs@chom.io
- [GitHub Issues](https://github.com/calounx/mentat/issues)

**Popular requests get added to FAQ!**

---

**Last Updated:** 2025-12-30
**Questions Answered:** 60+
**Maintained By:** CHOM Documentation Team

[Back to Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) | [Quick Start](/home/calounx/repositories/mentat/chom/docs/getting-started/QUICK-START.md) | [All Docs](/home/calounx/repositories/mentat/chom/docs/README.md)
