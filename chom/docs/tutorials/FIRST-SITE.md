# Tutorial: Create Your First WordPress Site

**Welcome!** This tutorial walks you through creating your first website with CHOM - step by step, no technical knowledge needed.

---

**⏱️ Time Required:** 10-15 minutes
**👥 Perfect For:** Complete beginners, business owners, anyone new to CHOM
**📋 Prerequisites:**
- CHOM dashboard access (login credentials)
- Optional: Domain name (can use test domain)

**🎯 What You'll Learn:**
- How to create a WordPress site
- How to access your new site
- How to log in to WordPress admin
- How to enable automatic backups
- How to set up SSL (HTTPS)

---

## Before You Start

### What You Need

**✅ Required:**
- Login to CHOM dashboard
- 10 minutes of time

**✅ Optional but recommended:**
- Domain name (like mysite.com)
- If you don't have one, you can use a test domain for now

**✅ Not required:**
- Technical knowledge
- Command line experience
- Coding skills

### What We'll Build

By the end of this tutorial, you'll have:
- A fully working WordPress website
- Automatic daily backups
- SSL certificate (secure HTTPS)
- Your own admin login
- Monitoring dashboard

**All in about 10 minutes!**

---

## Step 1: Log In to CHOM

### 1.1 Open CHOM Dashboard

1. Open your web browser (Chrome, Firefox, Safari, Edge)
2. Go to your CHOM URL (provided by your admin)
   - Example: `http://chom.yourcompany.com:8000`
   - Or: `http://localhost:8000` (if running locally)

**You should see:** CHOM login page

```
┌──────────────────────────────┐
│         CHOM                 │
│  Cloud Hosting Manager       │
│                              │
│  Email: [____________]       │
│  Password: [____________]    │
│                              │
│  [ Login ]                   │
│                              │
│  Don't have an account?      │
│  [Register]                  │
└──────────────────────────────┘
```

### 1.2 Enter Your Credentials

1. **Email:** Enter your email address
2. **Password:** Enter your password
3. **Click:** "Login" button

**You should see:** CHOM dashboard

```
┌────────────────────────────────────────┐
│  CHOM Dashboard               [User ▼] │
├────────────────────────────────────────┤
│  📊 Quick Stats                         │
│  Sites: 0  |  Backups: 0  |  Storage: 0│
├────────────────────────────────────────┤
│  [+ Create Your First Site]            │
└────────────────────────────────────────┘
```

**Troubleshooting:**
- Wrong password? Click "Forgot Password"
- Don't have account? Ask your CHOM administrator
- Can't access CHOM URL? Check with IT/admin

---

## Step 2: Start Creating Your Site

### 2.1 Navigate to Sites

**Option A: From Dashboard**
- Click the big blue button: **"+ Create Your First Site"**

**Option B: From Sidebar**
1. Look at the left sidebar
2. Click **"Sites"**
3. Click **"+ Create Site"** button (top right)

**You should see:** Site creation form

```
┌─────────────────────────────────────────┐
│  Create New Site                    [X] │
├─────────────────────────────────────────┤
│                                          │
│  Domain Name *                          │
│  [___________________________]          │
│                                          │
│  Site Type *                            │
│  [WordPress ▼]                          │
│                                          │
│  PHP Version                            │
│  [8.2 ▼]                                │
│                                          │
│  [ Cancel ]  [ Create Site ]           │
└─────────────────────────────────────────┘
```

---

## Step 3: Fill in Site Details

Now let's fill in the form. Take your time!

### 3.1 Enter Domain Name

**What is a domain name?**
- Your website's address on the internet
- Examples: myawesomesite.com, sarahsboutique.com, blog.example.com

**In the "Domain Name" field:**

**If you OWN a domain:**
```
Enter: mysite.com
(replace with your actual domain)
```

**If you DON'T have a domain yet:**
```
Enter: mysite.local
(this is just for testing - we'll explain later how to use a real domain)
```

**What NOT to include:**
- ❌ Don't add "http://" or "https://"
- ❌ Don't add "www" unless you specifically want it
- ✅ Just the domain: mysite.com

---

### 3.2 Select Site Type

**Click the "Site Type" dropdown**

You'll see three options:

**Option 1: WordPress** (Recommended for beginners)
- What it is: Popular website builder
- Best for: Blogs, business sites, portfolios, e-commerce
- Includes: Full WordPress with admin panel
- **Choose this if:** You want a regular website

**Option 2: Laravel**
- What it is: Framework for custom web applications
- Best for: Custom apps, APIs, SaaS platforms
- **Choose this if:** You're a developer building custom software

**Option 3: Static HTML**
- What it is: Plain HTML/CSS/JavaScript
- Best for: Simple landing pages, documentation
- **Choose this if:** You already have HTML files

**For this tutorial: Select "WordPress"**

---

### 3.3 Choose PHP Version

**Click the "PHP Version" dropdown**

You'll see:
- **PHP 8.2** (Stable - Recommended)
- **PHP 8.4** (Latest)

**What is PHP?**
- The programming language WordPress runs on
- Like choosing between Windows 10 vs Windows 11

**Which to choose?**
- **8.2:** More compatible with plugins, very stable
- **8.4:** Latest features, slightly faster

**For this tutorial: Keep "PHP 8.2" (default)**

**Good to know:**
- You can change PHP version later if needed
- Takes 30 seconds to switch
- Most WordPress plugins work with both

---

### 3.4 Optional WordPress Settings

**Click "Advanced Options" (if available)**

You might see additional fields:

**Site Title:**
```
Example: Sarah's Boutique
(What visitors see - you can change later)
```

**Admin Username:**
```
Default: admin
(Your WordPress login name)
```

**Admin Email:**
```
Example: sarah@example.com
(Where WordPress sends notifications)
```

**Admin Password:**
```
(Auto-generated strong password)
(You'll receive this by email)
```

**For this tutorial: Leave defaults or fill as you like**

---

### 3.5 Review Your Settings

**Before clicking Create, double-check:**

```
Domain Name: mysite.com ✓
Site Type: WordPress ✓
PHP Version: 8.2 ✓
```

**Looks good? Click the big blue button: "Create Site"**

---

## Step 4: Wait for Magic ✨

### 4.1 Watch the Progress

After clicking "Create Site," you'll see a progress screen:

```
┌─────────────────────────────────────────┐
│  Creating mysite.com...                 │
├─────────────────────────────────────────┤
│                                          │
│  ⏳ Creating directory structure...     │
│  ⏳ Downloading WordPress...            │
│  ⏳ Setting up database...              │
│  ⏳ Configuring web server (Nginx)...   │
│  ⏳ Installing WordPress...             │
│  ⏳ Setting up monitoring...            │
│                                          │
│  This takes 2-3 minutes. Grab coffee! ☕│
└─────────────────────────────────────────┘
```

### 4.2 What's Happening Behind the Scenes

While you wait, CHOM is automatically:

1. **Creating folders** on the server (10 seconds)
2. **Downloading WordPress** from WordPress.org (60 seconds)
3. **Creating a database** for your site (10 seconds)
4. **Configuring Nginx** web server (20 seconds)
5. **Installing WordPress** (30 seconds)
6. **Setting up PHP** (20 seconds)
7. **Configuring monitoring** (20 seconds)
8. **Running final checks** (10 seconds)

**Total: 2-3 minutes**

**What you do manually with traditional hosting: 30-60 minutes**

---

### 4.3 Success!

When deployment finishes, you'll see:

```
┌─────────────────────────────────────────┐
│  ✓ Site Created Successfully!           │
├─────────────────────────────────────────┤
│                                          │
│  Your site is ready:                    │
│  http://mysite.com                      │
│                                          │
│  WordPress Admin:                       │
│  Username: admin                        │
│  Password: Check your email             │
│                                          │
│  [View Site]  [Go to Dashboard]         │
└─────────────────────────────────────────┘
```

**Troubleshooting:**

**If creation failed:**
1. Read the error message carefully
2. Common issues:
   - Domain already exists → Choose different domain
   - VPS out of space → Contact admin
   - Network error → Try again
3. Click "Try Again" or contact support

---

## Step 5: Access Your New Website

### 5.1 Point Your Domain (If Using Real Domain)

**Skip this if you used a test domain like mysite.local**

If you used your own domain (mysite.com), you need to point it to CHOM:

**What to do:**
1. **Log in to your domain registrar** (GoDaddy, Namecheap, etc.)
2. **Find DNS settings** (might be called "DNS Management" or "Nameservers")
3. **Add an A record:**
   ```
   Type: A
   Name: @ (or blank)
   Value: YOUR_VPS_IP_ADDRESS
   TTL: 3600
   ```
4. **Save changes**
5. **Wait 5-60 minutes** for DNS to propagate

**Need help?** Your registrar has guides:
- [GoDaddy DNS Guide](https://www.godaddy.com/help/add-an-a-record-19238)
- [Namecheap DNS Guide](https://www.namecheap.com/support/knowledgebase/article.aspx/319/2237/how-can-i-set-up-an-a-address-record-for-my-domain)

**What's YOUR_VPS_IP_ADDRESS?**
- Find in CHOM: Go to VPS Servers → View your server → IP Address
- Or ask your CHOM administrator

---

### 5.2 Access via Browser (For Testing)

**If DNS isn't ready yet,** you can test using your computer's hosts file:

**On Mac/Linux:**
```bash
# Edit hosts file
sudo nano /etc/hosts

# Add this line (replace IP with your VPS IP):
192.168.1.100  mysite.com

# Save: Ctrl+X, then Y, then Enter
```

**On Windows:**
```bash
# Run Notepad as Administrator
# Open: C:\Windows\System32\drivers\etc\hosts

# Add this line:
192.168.1.100  mysite.com

# Save
```

**Now visit:** http://mysite.com in your browser

---

### 5.3 See Your WordPress Site

**Open your browser and go to:**
```
http://mysite.com
```

**You should see:**
- Default WordPress theme
- "Hello World" post
- WordPress logo

```
┌─────────────────────────────────────────┐
│  MyAwesomeSite              [Search]    │
├─────────────────────────────────────────┤
│                                          │
│  Hello World!                           │
│  Posted on December 30, 2025            │
│                                          │
│  Welcome to WordPress. This is your     │
│  first post. Edit or delete it, then    │
│  start writing!                         │
│                                          │
│  Posted in Uncategorized                │
│                                          │
└─────────────────────────────────────────┘
```

**Congratulations! Your WordPress site is live!** 🎉

---

## Step 6: Log In to WordPress Admin

Now let's log in to the WordPress dashboard where you can customize your site.

### 6.1 Find Your Login Credentials

**Option A: Check your email**
- CHOM sent an email with your WordPress password
- Subject: "Your WordPress site is ready!"
- Contains: Username and password

**Option B: In CHOM dashboard**
1. Go to Sites → Your Site
2. Click "Details" tab
3. Look for "WordPress Credentials"

**You should have:**
- **Username:** admin (or what you chose)
- **Password:** Random strong password

---

### 6.2 Access WordPress Admin

**Go to the WordPress admin login:**
```
http://mysite.com/wp-admin
```

**Or:**
```
http://mysite.com/wp-login.php
```

**You should see:**
```
┌─────────────────────────────────────────┐
│           WordPress Login               │
├─────────────────────────────────────────┤
│                                          │
│  Username: [admin____________]          │
│  Password: [●●●●●●●●●●●●●●●]          │
│                                          │
│  [ ] Remember Me                        │
│                                          │
│  [ Log In ]                             │
│                                          │
│  Lost your password?                    │
└─────────────────────────────────────────┘
```

### 6.3 Log In

1. **Enter username:** admin (or your custom username)
2. **Enter password:** (from email or CHOM dashboard)
3. **Click:** "Log In"

**You should see:** WordPress dashboard!

```
┌─────────────────────────────────────────┐
│  Dashboard           [Howdy, admin ▼]   │
├─────────────────────────────────────────┤
│  • Dashboard                             │
│  • Posts                                 │
│  • Media                                 │
│  • Pages                                 │
│  • Comments                              │
│  • Appearance                            │
│  • Plugins                               │
│  • Users                                 │
│  • Settings                              │
│                                          │
│  At a Glance:                           │
│  1 Post | 1 Page | 1 Comment           │
│                                          │
│  [Start customizing your site!]         │
└─────────────────────────────────────────┘
```

**You're in! Time to make this site your own.**

---

## Step 7: Customize Your Site (Optional)

Now the fun part - making it yours!

### 7.1 Change Site Title

1. **In WordPress dashboard:** Settings → General
2. **Site Title:** Change to your business name
   ```
   Example: Sarah's Boutique
   ```
3. **Tagline:** Short description
   ```
   Example: Handmade jewelry and accessories
   ```
4. **Click:** "Save Changes" at bottom

**Visit your site - title is updated!**

---

### 7.2 Choose a Theme (Your Site's Look)

1. **In WordPress dashboard:** Appearance → Themes
2. **Click:** "Add New"
3. **Browse themes** or search:
   ```
   Popular free themes:
   - Astra (multipurpose)
   - OceanWP (business)
   - GeneratePress (fast)
   - Hello Elementor (for page builder)
   ```
4. **Hover over theme** → Click "Install"
5. **After install:** Click "Activate"

**Your site now has a new look!**

**Tutorial:** [WordPress.org Theme Guide](https://wordpress.org/support/article/using-themes/)

---

### 7.3 Create Your First Page

1. **In WordPress dashboard:** Pages → Add New
2. **Enter title:**
   ```
   Example: About Us
   ```
3. **Add content** in editor:
   ```
   Welcome to Sarah's Boutique!

   We create handmade jewelry with love.
   Each piece is unique and crafted with care.

   Browse our collection and find your perfect accessory!
   ```
4. **Click:** "Publish" (top right)

**Your About page is live!**
**URL:** http://mysite.com/about-us

---

### 7.4 Install Your First Plugin

**Let's add a contact form:**

1. **In WordPress dashboard:** Plugins → Add New
2. **Search:** "Contact Form 7"
3. **Click:** "Install Now"
4. **After install:** "Activate"
5. **Go to:** Contact → Contact Forms
6. **Copy the shortcode:**
   ```
   [contact-form-7 id="123" title="Contact form 1"]
   ```
7. **Create new page:** Pages → Add New
8. **Title:** Contact
9. **Paste shortcode** in content
10. **Publish**

**You now have a contact form!**

---

## Step 8: Enable Automatic Backups

Protect your site with automatic backups!

### 8.1 Return to CHOM Dashboard

1. **Open new tab:** Your CHOM URL
2. **Already logged in?** Great!
3. **Logged out?** Log in again

### 8.2 Enable Backups

1. **Go to:** Sites → Your Site
2. **Click:** "Backups" tab
3. **Find:** "Automatic Backups" toggle
4. **Toggle to ON** (turns blue/green)
5. **Configure schedule:**
   ```
   Frequency: Daily
   Time: 02:00 AM (2 AM)
   Retention: 7 days (keeps last 7 backups)
   ```
6. **Click:** "Save Settings"

**You should see:**
```
✓ Automatic backups enabled
Next backup: Tomorrow at 02:00 AM
Retention: 7 days
```

**Your site is now automatically backed up every day!**

---

### 8.3 Create Manual Backup (Right Now)

Let's create a backup immediately:

1. **Still in Backups tab**
2. **Click:** "Create Backup" button
3. **Add description:**
   ```
   Example: Initial site setup
   ```
4. **Click:** "Create"
5. **Wait 1-2 minutes**

**You should see:**
```
✓ Backup created successfully!
  Size: 85 MB
  Files: 1,234
  Database: 2.1 MB
  Created: Just now
```

**Your site is now backed up!**

**What's backed up:**
- All WordPress files (themes, plugins, uploads)
- Database (posts, pages, settings)
- Configuration files

---

## Step 9: Enable SSL (HTTPS) - Make It Secure

Let's add the padlock 🔒 to your site!

### 9.1 Requirements

**SSL requires:**
- ✅ Real domain (not mysite.local)
- ✅ DNS pointing to your server
- ✅ Domain accessible via HTTP

**If using test domain:** Skip this step for now. Come back when you have a real domain.

---

### 9.2 Issue SSL Certificate

**In CHOM:**

1. **Go to:** Sites → Your Site
2. **Click:** "SSL" tab
3. **You should see:**
   ```
   SSL Status: Not Installed
   Domain: mysite.com

   [Issue SSL Certificate]
   ```
4. **Click:** "Issue SSL Certificate"
5. **Confirm:** "Yes, issue certificate"
6. **Wait 30-60 seconds**

**CHOM will:**
- Request certificate from Let's Encrypt (free!)
- Validate you own the domain
- Install certificate
- Configure automatic renewal (every 90 days)

---

### 9.3 Success!

**After installation:**
```
✓ SSL Certificate Installed
  Issued to: mysite.com
  Valid until: March 30, 2026
  Issued by: Let's Encrypt
  Auto-renewal: Enabled

HTTPS is now active!
```

**Visit your site:**
```
https://mysite.com
```

**You should see:**
- 🔒 Padlock icon in address bar
- "Secure" or "Connection is secure"

**Your site is now secure!**

---

## Step 10: View Your Site Metrics

Let's see how your site is performing!

### 10.1 Access Metrics Dashboard

**In CHOM:**

1. **Go to:** Sites → Your Site
2. **Click:** "Metrics" tab

**You should see:**
```
┌─────────────────────────────────────────┐
│  mysite.com - Metrics (Last 24 Hours)   │
├─────────────────────────────────────────┤
│                                          │
│  ⏱️  Response Time: 245 ms              │
│  📈 Requests: 12                        │
│  💾 Bandwidth: 1.2 MB                   │
│  ⚠️  Errors: 0                          │
│  ✓ Uptime: 100%                        │
│                                          │
│  [View Full Dashboard in Grafana →]    │
└─────────────────────────────────────────┘
```

**What these mean:**
- **Response Time:** How fast your site loads (lower = better)
- **Requests:** Number of page views
- **Bandwidth:** Data transferred
- **Errors:** Problems that occurred
- **Uptime:** Time site was accessible

---

### 10.2 View in Grafana (Advanced)

**Want pretty graphs?**

1. **Click:** "View Full Dashboard in Grafana"
2. **You'll see:** Detailed graphs showing:
   - Response times over time
   - Traffic patterns
   - Error rates
   - Server resource usage

**Example Grafana dashboard:**
```
Response Time (24h)
───────────────────────────────────
    │     ╱╲
300ms│    ╱  ╲
    │   ╱    ╲    ╱╲
200ms│  ╱      ╲  ╱  ╲
    │ ╱        ╲╱    ╲
100ms├─────────────────────────────
    0h    6h    12h   18h   24h

Avg: 245ms  Min: 120ms  Max: 890ms
```

**Cool, right?** This helps you:
- Know if site is slow
- See traffic patterns
- Catch problems early

---

## Step 11: What's Next?

**Congratulations!** You've successfully:
- ✅ Created a WordPress site
- ✅ Logged in to WordPress admin
- ✅ Enabled automatic backups
- ✅ Set up SSL (HTTPS)
- ✅ Viewed performance metrics

### Next Steps to Explore

**Customize Your Site:**
1. **Add more content:**
   - Write blog posts (Posts → Add New)
   - Create pages (About, Services, Contact)
   - Upload images (Media → Add New)

2. **Install useful plugins:**
   - **Yoast SEO** - Search engine optimization
   - **Wordfence** - Security
   - **WP Super Cache** - Speed up your site
   - **Akismet** - Spam protection

3. **Customize appearance:**
   - Try different themes
   - Customize colors (Appearance → Customize)
   - Add menus (Appearance → Menus)
   - Add widgets (Appearance → Widgets)

**Learn More About CHOM:**
1. **Invite team members:**
   - [Team Management Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md#team-management)

2. **Create staging site:**
   - Test changes safely before going live

3. **Set up monitoring alerts:**
   - Get notified if site goes down

4. **Explore the API:**
   - [API Quick Start](/home/calounx/repositories/mentat/chom/docs/API-QUICKSTART.md)

**WordPress Tutorials:**
1. [WordPress.org Beginner Guide](https://wordpress.org/support/article/first-steps-with-wordpress/)
2. [How to Use WordPress Editor](https://wordpress.org/support/article/wordpress-editor/)
3. [Finding WordPress Themes](https://wordpress.org/themes/)
4. [Finding WordPress Plugins](https://wordpress.org/plugins/)

---

## Troubleshooting Common Issues

### Issue: "Site not loading"

**Check these:**

1. **DNS propagation**
   ```bash
   # Check if DNS is updated:
   dig mysite.com

   # Should show your VPS IP
   ```
   - If wrong IP: Update DNS, wait 30-60 minutes
   - If correct: Continue to next check

2. **Site status in CHOM**
   - Go to Sites → Your Site
   - Status should be "Active" (not "Creating" or "Failed")

3. **Test from server**
   ```bash
   curl http://localhost
   # Should return HTML
   ```

4. **Check logs**
   - CHOM → Sites → Your Site → Logs
   - Look for errors

**Still not working?** [Get help](#getting-help)

---

### Issue: "Can't log in to WordPress admin"

**Try these fixes:**

1. **Check username/password**
   - Get credentials from CHOM: Sites → Your Site → Details
   - Or check email from CHOM

2. **Reset password**
   - On WordPress login: Click "Lost your password?"
   - Enter admin email
   - Check email for reset link

3. **Clear browser cache**
   - Ctrl+Shift+Delete (or Cmd+Shift+Delete on Mac)
   - Clear cookies and cache
   - Try logging in again

---

### Issue: "SSL certificate failed to install"

**Checklist:**

1. **DNS must be updated first**
   - Your domain must point to VPS IP
   - Check: https://dnschecker.org
   - Wait if recently changed (up to 48 hours)

2. **Port 80 must be open**
   - Let's Encrypt uses port 80 to verify
   - Check firewall settings

3. **Domain must be accessible**
   ```bash
   curl http://mysite.com
   # Should return HTML (not error)
   ```

4. **Try again**
   - CHOM → Sites → Your Site → SSL
   - Click "Issue Certificate" again

---

### Issue: "Backup creation failed"

**Common causes:**

1. **Not enough disk space**
   - Check: CHOM → VPS Servers → View usage
   - Free up space or upgrade VPS

2. **Site too large**
   - Backups include all files
   - Clean up old uploads, optimize images

3. **Permissions issue**
   - Usually resolves on retry
   - If persists: Contact support

---

## Getting Help

### Documentation

**Read more:**
- [User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md) - Complete CHOM features
- [FAQ](/home/calounx/repositories/mentat/chom/docs/getting-started/FAQ.md) - Common questions
- [Glossary](/home/calounx/repositories/mentat/chom/GLOSSARY.md) - Technical terms explained

### Community

**Ask questions:**
- [GitHub Discussions](https://github.com/calounx/mentat/discussions)
- Search existing topics
- Post new question with "Help Needed" tag

### Support

**Contact us:**
- Email: support@chom.io
- Include:
  - What you tried
  - What happened
  - Error messages (screenshot)
  - Site domain

---

## Summary

**You did it!** In about 10 minutes, you:

1. ✅ Logged in to CHOM
2. ✅ Created a WordPress site (3 minutes!)
3. ✅ Accessed your new site
4. ✅ Logged in to WordPress admin
5. ✅ Started customizing (theme, pages, plugins)
6. ✅ Enabled automatic backups
7. ✅ Set up SSL certificate
8. ✅ Viewed performance metrics

**This took you 10 minutes.**
**Traditional hosting: 30-60 minutes of manual work.**

**Welcome to the CHOM way of doing things!** 🚀

---

**Tutorial completed:** 2025-12-30
**Difficulty:** Beginner
**Maintained By:** CHOM Documentation Team

[Back to Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) | [User Guide](/home/calounx/repositories/mentat/chom/docs/USER-GUIDE.md) | [All Tutorials](/home/calounx/repositories/mentat/chom/docs/tutorials/)
