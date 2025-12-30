# CHOM Glossary: Technical Terms Explained

**Purpose:** Simple, jargon-free explanations of technical terms used in CHOM documentation.

**How to use this glossary:**
- Terms are organized by category
- Each term has a plain English definition
- Examples show real-world context
- Related terms are cross-referenced

---

**⏱️ Quick Find:** Use your browser's search (Ctrl+F or Cmd+F) to find terms

---

## General Web & Hosting Terms

### API (Application Programming Interface)
**What it means:** A way for different software to talk to each other.

**Example:** The CHOM API lets you create websites using code instead of clicking buttons. Like ordering pizza through an app instead of calling the restaurant.

**Related:** [REST API](#rest-api), [Endpoint](#endpoint)

---

### Backup
**What it means:** A copy of your website files and database saved for safekeeping.

**Example:** Like saving your video game progress. If something goes wrong, you can restore to your last backup and nothing is lost.

**Related:** [Restore](#restore), [Retention Policy](#retention-policy)

---

### Bandwidth
**What it means:** The amount of data transferred when people visit your website.

**Example:** Like water flowing through a pipe. More visitors = more bandwidth used. CHOM tracks this so you know your usage.

**Related:** [Traffic](#traffic), [Data Transfer](#data-transfer)

---

### Cache
**What it means:** Temporarily stored copies of web pages to make sites load faster.

**Example:** Like remembering the route to a friend's house instead of looking at GPS every time. The website "remembers" pages so they load instantly.

**Related:** [Redis](#redis), [Performance](#performance)

---

### CDN (Content Delivery Network)
**What it means:** Servers around the world that deliver your website faster to visitors.

**Example:** Like having coffee shops in every neighborhood instead of one central location. Visitors get content from the nearest server.

**CHOM:** Coming in version 2.0

---

### CLI (Command Line Interface)
**What it means:** Text-based way to control computers by typing commands.

**Example:** Like texting commands to your computer instead of clicking buttons. Looks like this:
```bash
php artisan migrate
```

**Alternative:** GUI (Graphical User Interface - buttons and windows)

---

### Database
**What it means:** Organized storage for your website's content, like blog posts, user accounts, and settings.

**Example:** Like a filing cabinet where WordPress keeps all your posts, comments, and user information. CHOM uses SQLite, MySQL, or PostgreSQL.

**Related:** [MySQL](#mysql), [PostgreSQL](#postgresql), [SQLite](#sqlite)

---

### DNS (Domain Name System)
**What it means:** The system that converts website names (like google.com) into IP addresses (like 172.217.14.206) that computers understand.

**Example:** Like a phone book for the internet. You type "mysite.com" and DNS finds the right server.

**Common task:** Point your domain to CHOM by adding an A record with your VPS IP address.

**Related:** [Domain](#domain), [IP Address](#ip-address)

---

### Domain
**What it means:** Your website's address on the internet (like mysite.com).

**Example:** Like your home address, but for your website. You buy it from a registrar (GoDaddy, Namecheap, etc.).

**In CHOM:** You enter your domain when creating a site. CHOM configures everything to make it work.

**Related:** [DNS](#dns), [Subdomain](#subdomain)

---

### Downtime
**What it means:** Time when your website is not accessible to visitors.

**Example:** Like a store being closed. CHOM's goal is 99.9% uptime (less than 9 hours downtime per year).

**Related:** [Uptime](#uptime), [Availability](#availability)

---

### Firewall
**What it means:** Security system that blocks unwanted network traffic.

**Example:** Like a security guard at a building entrance. Only lets in authorized visitors, blocks suspicious activity.

**In CHOM:** Built into your VPS to protect sites from attacks.

---

### FTP (File Transfer Protocol)
**What it means:** Old method of uploading files to a server.

**Example:** Like emailing files to your server. CHOM uses SFTP (secure version) instead.

**Modern alternative:** SFTP, rsync, or direct SSH access

---

### IP Address
**What it means:** Numerical address that identifies a computer on the internet.

**Example:** Like a phone number for your server. Looks like `192.168.1.100` (IPv4) or `2001:0db8::1` (IPv6).

**In CHOM:** Each VPS has an IP address. You need this to configure CHOM.

**Related:** [VPS](#vps-virtual-private-server), [DNS](#dns)

---

### Port
**What it means:** A numbered channel for network connections.

**Example:** Like TV channels. Different services use different ports:
- Port 80: HTTP (web traffic)
- Port 443: HTTPS (secure web traffic)
- Port 22: SSH (remote server access)

**In CHOM:** Mostly automatic, but you need port 22 open for deployment.

---

### SSL Certificate (HTTPS)
**What it means:** Security certificate that encrypts data between visitor and website.

**Example:** Like sealing a letter in an envelope instead of sending a postcard. Shows the padlock icon 🔒 in browsers.

**In CHOM:** One-click free SSL from Let's Encrypt. Automatically renews.

**Related:** [Let's Encrypt](#lets-encrypt), [HTTPS](#https)

---

### SSH (Secure Shell)
**What it means:** Secure way to access and control a server remotely.

**Example:** Like remote desktop for servers, but text-based. You type commands and the server responds.

**In CHOM:** Used to deploy sites and manage VPS servers.

**Related:** [CLI](#cli-command-line-interface), [VPS](#vps-virtual-private-server)

---

### Subdomain
**What it means:** A subdivision of your main domain.

**Example:** If your domain is `example.com`, subdomains could be:
- `blog.example.com`
- `shop.example.com`
- `staging.example.com`

**In CHOM:** Create separate sites for each subdomain.

---

### Traffic
**What it means:** The number of visitors and page views your website receives.

**Example:** Like foot traffic in a store. CHOM tracks traffic in the metrics dashboard.

**Related:** [Bandwidth](#bandwidth), [Analytics](#analytics)

---

### Uptime
**What it means:** Percentage of time your website is accessible and working.

**Example:** 99.9% uptime = down less than 9 hours per year. CHOM monitors this automatically.

**Related:** [Downtime](#downtime), [Monitoring](#monitoring)

---

### VPS (Virtual Private Server)
**What it means:** A virtual computer in the cloud that runs your websites.

**Example:** Like renting a dedicated computer that's always on. More powerful than shared hosting, cheaper than a physical server.

**Providers:** DigitalOcean, Linode, Vultr, Hetzner

**In CHOM:** You need 1-2 VPS servers to run CHOM infrastructure.

**Related:** [IP Address](#ip-address), [SSH](#ssh-secure-shell)

---

## CHOM-Specific Terms

### CHOM
**What it means:** Cloud Hosting & Observability Manager

**What it does:** A control panel that makes managing WordPress and Laravel sites easy. Handles deployment, backups, monitoring, and billing.

**Think of it as:** Modern cPanel with built-in monitoring.

---

### Control Plane
**What it means:** The main CHOM application that manages everything.

**Example:** Like a command center. The control plane is where you log in, create sites, view metrics.

**Technical detail:** Runs on your VPS Manager server.

---

### Managed Site
**What it means:** A website that CHOM is managing for you.

**Example:** Any WordPress, Laravel, or HTML site you create through CHOM. CHOM handles deployment, updates, backups, and monitoring.

**Also called:** Site, tenant site, or just "site"

---

### Observability Stack
**What it means:** The monitoring system that tracks if your sites are healthy and fast.

**Components:**
- **Prometheus:** Collects metrics (response times, errors, traffic)
- **Loki:** Stores logs (errors, access logs, application logs)
- **Grafana:** Shows graphs and dashboards

**Example:** Like a fitness tracker for your websites. Shows heart rate (CPU), steps (traffic), sleep quality (uptime).

**In CHOM:** Automatically configured for every site you create.

**Related:** [Metrics](#metrics), [Logs](#logs)

---

### Organization
**What it means:** Your CHOM account (like a company or workspace).

**Example:** "Acme Hosting" is an organization. It contains sites, team members, and billing.

**Also called:** Tenant, account

**In CHOM:** You can be a member of multiple organizations.

---

### Site Provisioning
**What it means:** The automated process CHOM uses to create a new website.

**What happens:** CHOM automatically:
1. Creates folders on the VPS
2. Installs WordPress/Laravel
3. Configures Nginx web server
4. Sets up PHP
5. Creates database
6. Configures monitoring

**Example:** Like ordering a pizza. You specify what you want, CHOM does all the work.

**Time:** 2-3 minutes per site

---

### VPS Manager
**What it means:** One of your two VPS servers - the one running the CHOM control panel.

**What runs here:**
- CHOM dashboard (where you log in)
- Database for CHOM settings
- API endpoints

**Example:** The brain of your CHOM setup.

**Related:** [VPS](#vps-virtual-private-server), [Control Plane](#control-plane)

---

### VPS Fleet
**What it means:** All the VPS servers CHOM is managing.

**Example:** If you have 5 VPS servers hosting customer sites, that's your "fleet."

**In CHOM:** CHOM distributes sites across your fleet based on available resources.

---

## WordPress Terms

### Plugin
**What it means:** Add-on software that extends WordPress functionality.

**Example:** Like apps on your phone. Want a contact form? Install a plugin. Want SEO tools? Install a plugin.

**In CHOM:** Full plugin access - install any plugin from WordPress.org or upload custom ones.

---

### Theme
**What it means:** The design/appearance of your WordPress site.

**Example:** Like wallpaper and furniture in a house. Changes how your site looks, not what it does.

**In CHOM:** Full theme access - use free, premium, or custom themes.

---

### WP Admin
**What it means:** The WordPress administration panel.

**Access:** yoursite.com/wp-admin

**Example:** The "back office" where you write posts, manage users, install plugins, etc.

**In CHOM:** Click "WP Admin" button to access directly from CHOM dashboard.

---

## Development & Technical Terms

### Artisan
**What it means:** Laravel's command-line tool for common tasks.

**Example:** `php artisan migrate` runs database migrations, `php artisan serve` starts the development server.

**Use in CHOM:**
```bash
php artisan migrate  # Setup database
php artisan serve    # Run locally
```

**Related:** [CLI](#cli-command-line-interface), [Laravel](#laravel)

---

### Composer
**What it means:** Dependency manager for PHP projects.

**Example:** Like a shopping list that automatically downloads all the code libraries CHOM needs.

**Common commands:**
- `composer install` - Install dependencies
- `composer update` - Update dependencies

**Required:** To run CHOM

---

### Docker
**What it means:** Software that runs applications in isolated containers.

**Example:** Like shipping containers for software. Each container has everything it needs to run.

**In CHOM:** Optional. Can use docker-compose for local development.

---

### Endpoint
**What it means:** A specific URL in an API that performs one action.

**Example:** CHOM API endpoints:
- `POST /api/v1/sites` - Create a site
- `GET /api/v1/sites` - List sites
- `DELETE /api/v1/sites/123` - Delete site #123

**Related:** [API](#api-application-programming-interface)

---

### Environment Variable
**What it means:** Configuration setting stored outside your code.

**Example:** Database password, API keys, app settings. Stored in `.env` file in CHOM.

**Why:** Keeps secrets out of code, allows different settings for dev/production.

---

### Git
**What it means:** Version control system that tracks code changes.

**Example:** Like "track changes" in Microsoft Word, but for code. Lets multiple developers work together.

**In CHOM:** Source code is on GitHub.

---

### Laravel
**What it means:** The PHP framework CHOM is built with.

**What it provides:** Ready-made tools for authentication, database, routing, etc.

**Example:** Like building a house with pre-made rooms instead of from individual bricks.

**Version:** CHOM uses Laravel 12

---

### Livewire
**What it means:** Laravel tool that makes interactive web pages without writing JavaScript.

**Example:** Update pages in real-time (like dashboards) using only PHP.

**In CHOM:** Powers the dashboard UI.

---

### Migration
**What it means:** A file that describes database structure changes.

**Example:** "Create users table" or "Add email column to sites table."

**Run with:** `php artisan migrate`

**Why:** Keeps database changes in version control.

---

### npm
**What it means:** Package manager for JavaScript/Node.js.

**Example:** Like Composer but for JavaScript. Downloads Tailwind CSS, Vue, build tools.

**Common commands:**
- `npm install` - Install packages
- `npm run build` - Build CSS/JS
- `npm run dev` - Development mode

**Required:** To build CHOM frontend

---

### REST API
**What it means:** A standard way to build APIs using HTTP requests.

**Methods:**
- `GET` - Retrieve data
- `POST` - Create data
- `PUT` - Update data
- `DELETE` - Delete data

**Example:** CHOM REST API lets you create sites, manage backups, etc. programmatically.

**Related:** [API](#api-application-programming-interface), [Endpoint](#endpoint)

---

### Tailwind CSS
**What it means:** CSS framework used for CHOM's interface design.

**Example:** Pre-made styling classes like `bg-blue-500` (blue background) and `p-4` (padding).

**In CHOM:** Makes UI development faster.

---

### Token (API Token)
**What it means:** A secret code that proves you're authorized to use the API.

**Example:** Like a hotel room key. Include it with every API request to prove you have access.

**In CHOM:** Generate in Settings → API Tokens

**Security:** Keep tokens secret! They're like passwords.

---

## Database Terms

### MySQL
**What it means:** Popular open-source database system.

**Example:** Stores WordPress posts, user accounts, settings.

**In CHOM:** One option for production (SQLite and PostgreSQL also supported).

**Alternative:** MariaDB (MySQL-compatible fork)

---

### PostgreSQL
**What it means:** Advanced open-source database system.

**Example:** Like MySQL but with more features. Good for large-scale applications.

**In CHOM:** Recommended for production deployments.

**Nickname:** Postgres

---

### Redis
**What it means:** In-memory data store for caching and queues.

**Example:** Keeps frequently-used data in fast memory instead of slow disk.

**In CHOM:** Speeds up dashboard, handles background jobs.

**Optional:** But highly recommended for production

---

### SQLite
**What it means:** Simple database stored in a single file.

**Example:** Great for development, testing, small projects. No separate server needed.

**In CHOM:** Default for local development.

**File location:** `database/database.sqlite`

---

## Monitoring & Observability Terms

### Alert
**What it means:** Notification when something goes wrong.

**Example:** "Site is down" or "Response time > 1 second" triggers an alert.

**In CHOM:** Configure in Metrics → Alerts

**Delivery:** Email, Slack, webhook

---

### Dashboard
**What it means:** Visual display of important metrics and information.

**Example:** CHOM dashboard shows your sites, backups, alerts at a glance.

**In Grafana:** Custom dashboards show graphs of CPU, memory, traffic, errors.

---

### Grafana
**What it means:** Open-source tool for visualizing metrics with graphs and dashboards.

**Example:** Shows beautiful graphs of your site's performance over time.

**In CHOM:** Automatically configured. Access at http://your-observability-server:3000

**Related:** [Prometheus](#prometheus), [Observability Stack](#observability-stack)

---

### Logs
**What it means:** Recorded events and errors from your applications and servers.

**Types:**
- **Application logs:** WordPress/Laravel errors
- **Access logs:** Who visited your site, when
- **Error logs:** Nginx/PHP errors

**In CHOM:** View in Metrics → Logs tab

**Search:** Use Loki query language to find specific events

---

### Loki
**What it means:** Log aggregation system (like Elasticsearch, but simpler).

**Example:** Collects logs from all your sites in one place for easy searching.

**In CHOM:** Part of observability stack.

**Related:** [Logs](#logs), [Observability Stack](#observability-stack)

---

### Metrics
**What it means:** Numerical measurements of system behavior.

**Examples:**
- Response time: 245ms
- CPU usage: 32%
- Memory: 2.1GB / 4GB
- Requests per minute: 450

**In CHOM:** View in Metrics dashboard for each site.

**Related:** [Prometheus](#prometheus), [Grafana](#grafana)

---

### Prometheus
**What it means:** Open-source monitoring system that collects and stores metrics.

**Example:** Like a data collector. Every 15 seconds, it asks "How are you?" and records the answer.

**In CHOM:** Monitors all sites automatically.

**Data:** Stores 15 days of metrics by default

**Related:** [Metrics](#metrics), [Observability Stack](#observability-stack)

---

### Trace
**What it means:** Detailed record of what happened during a request.

**Example:** Shows exactly which code ran, how long each part took, where slowdowns occurred.

**In CHOM:** Advanced feature for debugging performance issues.

---

## Security Terms

### 2FA (Two-Factor Authentication)
**What it means:** Extra security layer requiring two forms of identification.

**Example:** Password (something you know) + phone code (something you have).

**In CHOM:** Optional but recommended. Enable in Settings → Security.

**Standard:** TOTP (Google Authenticator, Authy)

---

### Encryption
**What it means:** Scrambling data so only authorized people can read it.

**Example:** Like writing in secret code. Even if someone steals encrypted data, they can't read it.

**In CHOM:** SSH keys, SSL certificates, database passwords all encrypted.

---

### HTTPS
**What it means:** Secure version of HTTP using SSL/TLS encryption.

**Example:** The padlock icon 🔒 in your browser. Protects data in transit.

**In CHOM:** Free automatic HTTPS for all sites via Let's Encrypt.

**Related:** [SSL Certificate](#ssl-certificate-https)

---

### Let's Encrypt
**What it means:** Free, automated certificate authority providing SSL certificates.

**Example:** Like a trusted organization that vouches "This website is really mysite.com."

**In CHOM:** One-click SSL certificates. Auto-renewal every 90 days.

---

### Rate Limiting
**What it means:** Restricting how many requests someone can make in a time period.

**Example:** Prevents abuse by limiting to 60 API calls per minute.

**In CHOM:**
- Auth endpoints: 5 requests/minute
- API endpoints: 60 requests/minute

**Why:** Prevents brute-force attacks and overload.

---

### Sanctum
**What it means:** Laravel's API authentication system.

**Example:** Creates secure tokens for API access.

**In CHOM:** Powers API authentication.

**Alternative:** OAuth, JWT

---

## Billing & Business Terms

### Stripe
**What it means:** Payment processing service for online businesses.

**Example:** Handles credit cards, subscriptions, invoices automatically.

**In CHOM:** Powers billing system. Customers pay via Stripe.

**Integration:** Laravel Cashier

---

### Subscription
**What it means:** Recurring payment for ongoing service.

**Example:** Pay $29/month for CHOM Starter plan, auto-renews monthly.

**In CHOM:** Tiers: Starter ($29), Pro ($79), Enterprise ($249)

---

### Webhook
**What it means:** Automated message sent when an event happens.

**Example:** Stripe sends webhook when payment succeeds/fails. CHOM receives and takes action.

**In CHOM:** Handles subscription updates, payment failures automatically.

---

## Deployment Terms

### Ansible (Planned)
**What it means:** Automation tool for deploying and configuring servers.

**Example:** Write instructions once, run on 100 servers. Makes deployment consistent.

**In CHOM:** Deployment script uses similar concepts.

---

### Inventory
**What it means:** List of servers and their configuration.

**Example:** `inventory.yaml` tells CHOM which VPS servers to use and how to connect.

**In CHOM:** Edit before deployment to specify your VPS IPs.

---

### Staging Environment
**What it means:** Separate copy of your site for testing changes.

**Example:** Like a dress rehearsal. Test updates on staging before pushing to production.

**In CHOM:** Create staging sites to test safely.

---

### Production
**What it means:** The real, live environment that customers/visitors use.

**Example:** Your actual website that people see. Be careful changing production!

**Opposite:** Development, staging, testing

---

## Common Acronyms

### API - [Application Programming Interface](#api-application-programming-interface)
### CDN - [Content Delivery Network](#cdn-content-delivery-network)
### CLI - [Command Line Interface](#cli-command-line-interface)
### DNS - [Domain Name System](#dns-domain-name-system)
### FTP - [File Transfer Protocol](#ftp-file-transfer-protocol)
### HTTPS - [HTTP Secure](#https)
### RAM - Random Access Memory (server memory)
### REST - [Representational State Transfer](#rest-api)
### SSH - [Secure Shell](#ssh-secure-shell)
### SSL - [Secure Sockets Layer](#ssl-certificate-https)
### VPS - [Virtual Private Server](#vps-virtual-private-server)
### 2FA - [Two-Factor Authentication](#2fa-two-factor-authentication)

---

## Still Confused?

### Can't find a term?
Email us: docs@chom.io with the term you'd like explained.

### Want more detail?
Most glossary entries link to full documentation. Look for "Related" and "See also" sections.

### Need visual explanations?
Check out:
- [5-Minute Quick Start](/home/calounx/repositories/mentat/chom/docs/getting-started/QUICK-START.md) - Explains concepts visually
- [Architecture Diagrams](/home/calounx/repositories/mentat/chom/docs/diagrams/README.md) - Visual system overview

---

**Last Updated:** 2025-12-30
**Maintained By:** CHOM Documentation Team

[Back to Start Here](/home/calounx/repositories/mentat/chom/START-HERE.md) | [FAQ](/home/calounx/repositories/mentat/chom/docs/getting-started/FAQ.md) | [All Docs](/home/calounx/repositories/mentat/chom/docs/README.md)
