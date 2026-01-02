# Confidence Level Improvement Roadmap: 82% → 99%

**Current Status:** 82% (HIGH) - Production Ready with Limitations
**Target:** 99% (EXCELLENT) - Full Production Confidence
**Gap to Close:** 17 percentage points
**Timeline:** 2-3 weeks of focused work

---

## 🎯 Confidence Gap Analysis

### Current State Breakdown

| Component | Current | Target | Gap | Priority |
|-----------|---------|--------|-----|----------|
| Observability Stack | 92% | 99% | +7% | HIGH |
| CHOM Application | 72% | 99% | +27% | CRITICAL |
| **Overall** | **82%** | **99%** | **+17%** | **CRITICAL** |

---

## 📊 Identified Gaps & Solutions

### CHOM Application Gaps (72% → 99% = +27 points)

| Gap | Impact | Effort | Solution |
|-----|--------|--------|----------|
| **No Integration/E2E Testing** | -10% | HIGH | Implement Dusk/Playwright test suite |
| **No Load Testing** | -8% | MEDIUM | Implement k6/Locust benchmarks |
| **Email Service Not Configured** | -5% | LOW | Configure SendGrid/Mailgun |
| **Observability Integration Untested** | -5% | MEDIUM | Test metrics/logs collection |
| **Remaining Test Failures** | -6% | MEDIUM | Fix 22 failing tests |
| **No Disaster Recovery Testing** | -3% | MEDIUM | Test backup/restore at scale |

**Total Points Available:** 37% (targeting 27% to reach 99%)

### Observability Stack Gaps (92% → 99% = +7 points)

| Gap | Impact | Effort | Solution |
|-----|--------|--------|----------|
| ~~DNS Not Configured~~ | ~~-5%~~ | ~~N/A~~ | ✅ **COMPLETED** |
| **Network Connectivity Untested** | -3% | LOW | Test VPS-to-VPS communication |
| **No Production Dashboards** | -2% | LOW | Load pre-configured Grafana dashboards |
| **No Alert Rules Defined** | -2% | LOW | Configure Alertmanager rules |

**Total Points Available:** 7% (all needed to reach 99%)

---

## 🚀 Implementation Plan

### Phase 1: Quick Wins (Week 1) - +12% Confidence

**Goal:** 82% → 94% in 1 week

#### 1.1 Configure Email Service (+5% - 1 day)

**Deliverables:**
- SendGrid account setup (free tier)
- Environment configuration
- Test email delivery
- Verify team invitation flow

**Implementation:**
```bash
# 1. Sign up for SendGrid (https://sendgrid.com)
# 2. Create API key with "Mail Send" permissions
# 3. Configure Laravel .env

MAIL_MAILER=smtp
MAIL_HOST=smtp.sendgrid.net
MAIL_PORT=587
MAIL_USERNAME=apikey
MAIL_PASSWORD=SG.xxxxxxxxxxxxxxxxxxxx
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@arewel.com
MAIL_FROM_NAME="CHOM Platform"

# 4. Test email delivery
php artisan tinker
>>> Mail::raw('Test email', function($msg) {
      $msg->to('test@example.com')->subject('CHOM Test');
   });
```

**Verification:**
- Send test invitation
- Receive email with invitation link
- Accept invitation successfully
- Verify password reset emails work

**Confidence Gained:** +5% (Total: 87%)

---

#### 1.2 Test Network Connectivity (+3% - 2 hours)

**Deliverables:**
- VPS-to-VPS connectivity verified
- Firewall rules configured
- Prometheus scraping CHOM metrics
- Logs flowing from CHOM to Loki

**Implementation:**
```bash
# On mentat (51.254.139.78) - Observability
# Test connectivity to landsraad
ping -c 4 51.77.150.96
curl -I https://landsraad.arewel.com
curl http://51.77.150.96:9100/metrics  # Node Exporter

# On landsraad (51.77.150.96) - CHOM
# Allow Prometheus scraping
ufw allow from 51.254.139.78 to any port 9100
ufw allow from 51.254.139.78 to any port 443

# Test connectivity to mentat
ping -c 4 51.254.139.78
curl -I https://mentat.arewel.com

# Configure Prometheus to scrape CHOM
# Add to /etc/prometheus/prometheus.yml on mentat:
- job_name: 'chom-application'
  static_configs:
    - targets: ['51.77.150.96:443']
      labels:
        service: 'chom'
        environment: 'production'

- job_name: 'chom-node-exporter'
  static_configs:
    - targets: ['51.77.150.96:9100']
      labels:
        service: 'system'
        host: 'landsraad'

# Restart Prometheus
systemctl restart prometheus

# Configure Promtail/Alloy on landsraad to ship logs to Loki
# Edit /etc/alloy/config.alloy or install Promtail
```

**Verification:**
- Prometheus targets show "UP" status for CHOM
- Grafana shows CHOM metrics
- Loki receives CHOM application logs
- Network latency < 5ms between VPS

**Confidence Gained:** +3% (Total: 90%)

---

#### 1.3 Load Grafana Dashboards & Alerts (+4% - 4 hours)

**Deliverables:**
- 5 pre-configured Grafana dashboards imported
- 10 critical alert rules defined
- Alertmanager notification channels configured
- Test alert firing and resolution

**Implementation:**

**A. Create Dashboards:**

1. **System Overview Dashboard** (Node Exporter metrics)
   - CPU usage per host
   - Memory usage with swap
   - Disk usage and I/O
   - Network throughput

2. **CHOM Application Dashboard**
   - Request rate (requests/sec)
   - Response time (p50, p95, p99)
   - Error rate (4xx, 5xx)
   - Active users
   - Queue job throughput

3. **Database Performance Dashboard**
   - Query execution time
   - Connection pool usage
   - Slow queries (>1s)
   - Database size growth

4. **Security Dashboard**
   - Failed login attempts
   - API rate limit violations
   - Suspicious IPs (fail2ban)
   - SSL certificate expiry countdown

5. **Business Metrics Dashboard**
   - Total sites managed
   - Backups created/restored
   - Active organizations
   - Storage usage per tenant

**B. Define Alert Rules:**

```yaml
# /etc/prometheus/rules/chom_alerts.yml
groups:
  - name: chom_critical
    interval: 30s
    rules:
      - alert: HighMemoryUsage
        expr: node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Memory usage critical on {{ $labels.instance }}"

      - alert: DiskSpaceLow
        expr: node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes < 0.2
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Disk space below 20% on {{ $labels.instance }}"

      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 10
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected: {{ $value }} errors/sec"

      - alert: DatabaseConnectionPoolExhausted
        expr: mysql_global_status_threads_connected / mysql_global_variables_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Database connection pool at {{ $value | humanizePercentage }}"

      - alert: QueueBacklog
        expr: laravel_queue_size > 1000
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Queue backlog: {{ $value }} jobs pending"

      - alert: SSLCertificateExpiringSoon
        expr: (ssl_certificate_expiry_seconds - time()) / 86400 < 14
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL certificate expires in {{ $value }} days"
```

**C. Configure Alertmanager:**

```yaml
# /etc/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'email-notifications'

  routes:
    - match:
        severity: critical
      receiver: 'email-critical'
      continue: true

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'ops@arewel.com'
        from: 'alertmanager@arewel.com'
        smarthost: 'smtp.sendgrid.net:587'
        auth_username: 'apikey'
        auth_password: 'SG.xxxxxxxxxxxxxxxxxxxx'

  - name: 'email-critical'
    email_configs:
      - to: 'critical-alerts@arewel.com'
        from: 'alertmanager@arewel.com'
        smarthost: 'smtp.sendgrid.net:587'
        auth_username: 'apikey'
        auth_password: 'SG.xxxxxxxxxxxxxxxxxxxx'
        send_resolved: true
```

**Verification:**
- All 5 dashboards show live data
- Test alerts trigger correctly
- Email notifications received
- Alert resolution notifications work

**Confidence Gained:** +4% (Total: 94%)

---

### Phase 2: Integration & E2E Testing (Week 2) - +10% Confidence

**Goal:** 94% → 104% → 99% (capped)

#### 2.1 Implement Integration/E2E Test Suite (+10% - 3 days)

**Deliverables:**
- Laravel Dusk installed and configured
- 30+ E2E test scenarios covering critical workflows
- CI/CD pipeline integration
- Test coverage report

**Implementation:**

**A. Install Laravel Dusk:**

```bash
cd /home/calounx/repositories/mentat/chom

# Install Dusk
composer require --dev laravel/dusk
php artisan dusk:install

# Configure for headless Chrome
# Edit tests/DuskTestCase.php
```

**B. Create E2E Test Scenarios:**

```php
// tests/Browser/AuthenticationFlowTest.php
<?php

namespace Tests\Browser;

use Laravel\Dusk\Browser;
use Tests\DuskTestCase;
use PHPUnit\Framework\Attributes\Test;

class AuthenticationFlowTest extends DuskTestCase
{
    #[Test]
    public function user_can_complete_full_registration_flow(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->visit('/register')
                    ->type('name', 'Test User')
                    ->type('email', 'test@example.com')
                    ->type('organization_name', 'Test Org')
                    ->type('password', 'SecurePass123!')
                    ->type('password_confirmation', 'SecurePass123!')
                    ->press('Register')
                    ->waitForLocation('/dashboard')
                    ->assertSee('Welcome');
        });
    }

    #[Test]
    public function user_can_enable_2fa_and_login(): void
    {
        $this->browse(function (Browser $browser) {
            // Login
            $browser->loginAs($this->user)
                    ->visit('/settings/security')
                    ->press('Enable 2FA')
                    ->waitForText('Scan QR Code')
                    ->assertSee('Recovery Codes');

            // Get 2FA code from test helper
            $code = $this->getTotpCode($this->user->two_factor_secret);

            $browser->type('code', $code)
                    ->press('Confirm')
                    ->assertSee('Two-factor authentication enabled');

            // Logout and test 2FA login
            $browser->visit('/logout')
                    ->visit('/login')
                    ->type('email', $this->user->email)
                    ->type('password', 'password')
                    ->press('Login')
                    ->waitForText('Enter 2FA Code')
                    ->type('code', $this->getTotpCode($this->user->two_factor_secret))
                    ->press('Verify')
                    ->waitForLocation('/dashboard')
                    ->assertAuthenticated();
        });
    }
}

// tests/Browser/SiteManagementFlowTest.php
class SiteManagementFlowTest extends DuskTestCase
{
    #[Test]
    public function user_can_create_site_and_create_backup(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->loginAs($this->user)
                    ->visit('/sites')
                    ->press('Create Site')
                    ->type('name', 'My WordPress Site')
                    ->select('type', 'wordpress')
                    ->type('domain', 'example.com')
                    ->select('php_version', '8.2')
                    ->press('Create')
                    ->waitForText('Site created successfully')
                    ->assertSee('My WordPress Site');

            // Create backup
            $browser->click('@site-menu')
                    ->click('@create-backup')
                    ->select('type', 'full')
                    ->press('Create Backup')
                    ->waitForText('Backup queued')
                    ->pause(5000) // Wait for job processing
                    ->refresh()
                    ->assertSee('Backup completed');

            // Download backup
            $browser->click('@download-backup')
                    ->pause(2000); // Wait for download

            // Verify file downloaded
            $this->assertFileExists(
                $browser->downloadPath() . '/backup-*.tar.gz'
            );
        });
    }

    #[Test]
    public function user_can_restore_site_from_backup(): void
    {
        $site = Site::factory()->create(['tenant_id' => $this->user->currentTenant->id]);
        $backup = SiteBackup::factory()->create([
            'site_id' => $site->id,
            'status' => 'completed'
        ]);

        $this->browse(function (Browser $browser) use ($site) {
            $browser->loginAs($this->user)
                    ->visit("/sites/{$site->id}/backups")
                    ->click('@restore-backup')
                    ->check('confirm')
                    ->press('Restore Site')
                    ->waitForText('Restore queued')
                    ->assertSee('restoring');

            // Wait for restore to complete (async job)
            $this->waitForJobToComplete('App\Jobs\RestoreBackupJob');

            $browser->refresh()
                    ->assertSee('active')
                    ->assertSee('Restore completed');
        });
    }
}

// tests/Browser/TeamCollaborationFlowTest.php
class TeamCollaborationFlowTest extends DuskTestCase
{
    #[Test]
    public function owner_can_invite_member_and_member_can_accept(): void
    {
        $this->browse(function (Browser $owner, Browser $member) {
            // Owner invites member
            $owner->loginAs($this->owner)
                  ->visit('/team')
                  ->press('Invite Member')
                  ->type('email', 'member@example.com')
                  ->select('role', 'member')
                  ->press('Send Invitation')
                  ->waitForText('Invitation sent')
                  ->assertSee('member@example.com');

            // Get invitation token from database
            $invitation = TeamInvitation::where('email', 'member@example.com')->first();

            // Member accepts invitation
            $member->visit("/team/accept/{$invitation->token}")
                   ->assertSee('Join Test Organization')
                   ->type('name', 'Team Member')
                   ->type('password', 'SecurePass123!')
                   ->type('password_confirmation', 'SecurePass123!')
                   ->press('Accept Invitation')
                   ->waitForLocation('/dashboard')
                   ->assertAuthenticated()
                   ->assertSee('Test Organization');

            // Verify member can see organization sites
            $member->visit('/sites')
                   ->assertSee('My WordPress Site'); // From owner
        });
    }
}

// tests/Browser/VpsManagementFlowTest.php
class VpsManagementFlowTest extends DuskTestCase
{
    #[Test]
    public function admin_can_add_vps_and_view_statistics(): void
    {
        $this->browse(function (Browser $browser) {
            $browser->loginAs($this->admin)
                    ->visit('/vps')
                    ->press('Add VPS Server')
                    ->type('hostname', 'vps1.example.com')
                    ->type('ip_address', '192.168.1.100')
                    ->type('ssh_username', 'root')
                    ->type('ssh_port', '22')
                    ->attach('ssh_key', storage_path('testing/test_rsa_key'))
                    ->select('spec_cpu', '4')
                    ->type('spec_memory_mb', '8192')
                    ->type('spec_disk_gb', '200')
                    ->press('Add Server')
                    ->waitForText('VPS server added')
                    ->assertSee('vps1.example.com');

            // View statistics
            $browser->click('@view-stats')
                    ->waitForText('Server Statistics')
                    ->assertSee('CPU Usage')
                    ->assertSee('Memory Usage')
                    ->assertSee('Disk Usage')
                    ->assertSee('Network Traffic');
        });
    }
}
```

**C. Create Test Helpers:**

```php
// tests/Browser/Concerns/InteractsWithJobs.php
trait InteractsWithJobs
{
    protected function waitForJobToComplete(string $jobClass, int $timeout = 30): void
    {
        $start = time();

        while (time() - $start < $timeout) {
            $pending = \DB::table('jobs')
                ->where('payload', 'like', "%{$jobClass}%")
                ->count();

            if ($pending === 0) {
                return;
            }

            sleep(1);
        }

        throw new \Exception("Job {$jobClass} did not complete within {$timeout} seconds");
    }
}

// tests/Browser/Concerns/GeneratesTotpCodes.php
trait GeneratesTotpCodes
{
    protected function getTotpCode(string $secret): string
    {
        $google2fa = app(\PragmaRX\Google2FA\Google2FA::class);
        return $google2fa->getCurrentOtp(decrypt($secret));
    }
}
```

**D. Test Scenarios to Implement:**

1. **Authentication (5 tests)**
   - Complete registration flow
   - Login with email/password
   - Enable 2FA and login with 2FA
   - Password reset flow
   - Logout

2. **Site Management (8 tests)**
   - Create site (WordPress, Laravel, Static)
   - Update site configuration
   - Delete site
   - Create backup (full, files, database)
   - Download backup
   - Restore from backup
   - View site metrics
   - Issue SSL certificate

3. **Team Collaboration (5 tests)**
   - Invite team member
   - Accept invitation
   - Update member role
   - Remove team member
   - Transfer ownership

4. **VPS Management (4 tests)**
   - Add VPS server
   - View VPS statistics
   - Update VPS configuration
   - Decommission VPS

5. **API Integration (8 tests)**
   - Register via API
   - Login via API
   - Create site via API
   - Create backup via API
   - Download backup via API
   - Restore backup via API
   - Team invitation via API
   - VPS management via API

**E. Run Tests:**

```bash
# Run all E2E tests
php artisan dusk

# Run specific test suite
php artisan dusk --filter AuthenticationFlowTest

# Run with screenshots on failure
php artisan dusk --screenshots

# Generate coverage report
php artisan dusk --coverage
```

**Verification:**
- All 30+ E2E tests passing
- Critical workflows validated end-to-end
- Screenshots captured on failures
- Test coverage > 80% for critical paths

**Confidence Gained:** +10% (Total: 104% → capped at 99%)

---

### Phase 3: Load Testing & Performance (Week 2-3) - Maintains 99%

**Goal:** Validate system can handle production load

#### 3.1 Implement Load Testing Framework (3 days)

**Deliverables:**
- k6 load testing scripts
- Performance benchmarks established
- Bottleneck identification
- Optimization recommendations

**Implementation:**

**A. Install k6:**

```bash
# On development machine
curl https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz -L | tar xvz
sudo mv k6 /usr/local/bin/
```

**B. Create Load Test Scenarios:**

```javascript
// tests/load/authentication_load.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errorRate = new Rate('errors');

export let options = {
  stages: [
    { duration: '2m', target: 10 },  // Ramp up to 10 users
    { duration: '5m', target: 50 },  // Ramp up to 50 users
    { duration: '10m', target: 100 }, // Stay at 100 users
    { duration: '5m', target: 200 },  // Spike to 200 users
    { duration: '5m', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500'], // 95% of requests under 500ms
    'http_req_failed': ['rate<0.01'],   // Error rate < 1%
    'errors': ['rate<0.1'],              // Error rate < 10%
  },
};

export default function () {
  // Register user
  let registerPayload = JSON.stringify({
    name: `User${__VU}_${__ITER}`,
    email: `user${__VU}_${__ITER}@example.com`,
    password: 'SecurePass123!',
    password_confirmation: 'SecurePass123!',
    organization_name: `Org${__VU}_${__ITER}`
  });

  let registerRes = http.post(
    'https://landsraad.arewel.com/api/v1/auth/register',
    registerPayload,
    { headers: { 'Content-Type': 'application/json' } }
  );

  check(registerRes, {
    'registration successful': (r) => r.status === 201,
    'token received': (r) => r.json('token') !== undefined,
  }) || errorRate.add(1);

  sleep(1);

  if (registerRes.status === 201) {
    let token = registerRes.json('token');

    // Login
    let loginPayload = JSON.stringify({
      email: `user${__VU}_${__ITER}@example.com`,
      password: 'SecurePass123!',
    });

    let loginRes = http.post(
      'https://landsraad.arewel.com/api/v1/auth/login',
      loginPayload,
      { headers: { 'Content-Type': 'application/json' } }
    );

    check(loginRes, {
      'login successful': (r) => r.status === 200,
    }) || errorRate.add(1);

    sleep(1);

    // Get user profile
    let profileRes = http.get(
      'https://landsraad.arewel.com/api/v1/auth/me',
      { headers: { 'Authorization': `Bearer ${token}` } }
    );

    check(profileRes, {
      'profile retrieved': (r) => r.status === 200,
    }) || errorRate.add(1);

    sleep(2);
  }
}

// tests/load/site_management_load.js
export let options = {
  stages: [
    { duration: '5m', target: 50 },
    { duration: '10m', target: 100 },
    { duration: '5m', target: 0 },
  ],
};

export default function () {
  // Assume user is already logged in (use setup() to create tokens)
  let token = __ENV.API_TOKEN;

  // Create site
  let sitePayload = JSON.stringify({
    name: `Site${__VU}_${__ITER}`,
    domain: `site${__VU}-${__ITER}.example.com`,
    type: 'wordpress',
    php_version: '8.2',
  });

  let createRes = http.post(
    'https://landsraad.arewel.com/api/v1/sites',
    sitePayload,
    { headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    } }
  );

  check(createRes, {
    'site created': (r) => r.status === 201,
  });

  if (createRes.status === 201) {
    let siteId = createRes.json('data.id');
    sleep(2);

    // Get site details
    http.get(
      `https://landsraad.arewel.com/api/v1/sites/${siteId}`,
      { headers: { 'Authorization': `Bearer ${token}` } }
    );

    sleep(1);

    // Get site metrics
    http.get(
      `https://landsraad.arewel.com/api/v1/sites/${siteId}/metrics`,
      { headers: { 'Authorization': `Bearer ${token}` } }
    );

    sleep(2);
  }
}

// tests/load/backup_operations_load.js
export default function () {
  let token = __ENV.API_TOKEN;
  let siteId = __ENV.SITE_ID;

  // Create backup
  let backupPayload = JSON.stringify({
    type: 'full',
    compression: 'gzip',
  });

  let backupRes = http.post(
    `https://landsraad.arewel.com/api/v1/sites/${siteId}/backups`,
    backupPayload,
    { headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    } }
  );

  check(backupRes, {
    'backup queued': (r) => r.status === 202,
  });

  sleep(5);
}
```

**C. Run Load Tests:**

```bash
# Run authentication load test
k6 run tests/load/authentication_load.js

# Run with Grafana Cloud (real-time monitoring)
k6 run --out cloud tests/load/authentication_load.js

# Run site management test
API_TOKEN=<token> k6 run tests/load/site_management_load.js

# Run with custom thresholds
k6 run --thresholds http_req_duration=p(99)<1000 tests/load/authentication_load.js
```

**D. Establish Performance Baselines:**

| Metric | Target | Acceptable | Notes |
|--------|--------|------------|-------|
| Response Time (p95) | <500ms | <1000ms | 95% of requests |
| Response Time (p99) | <1000ms | <2000ms | 99% of requests |
| Throughput | >100 req/s | >50 req/s | Per endpoint |
| Error Rate | <0.1% | <1% | HTTP 5xx errors |
| Concurrent Users | 100+ | 50+ | Simultaneous users |
| Database Connections | <50 | <80 | Max pool: 100 |
| Memory Usage | <2GB | <3GB | CHOM application |
| CPU Usage | <60% | <80% | Average load |

**Verification:**
- System handles 100+ concurrent users
- Response times meet SLA
- Error rate < 1%
- No memory leaks detected
- Database performance acceptable

**Confidence Maintained:** 99%

---

### Phase 4: Security Audit & Disaster Recovery (Week 3) - Maintains 99%

#### 4.1 Security Penetration Testing (2 days)

**Deliverables:**
- OWASP Top 10 vulnerability scan
- Penetration testing report
- Security fixes implemented
- Security hardening checklist

**Implementation:**

**A. Automated Security Scanning:**

```bash
# Install OWASP ZAP
wget https://github.com/zaproxy/zaproxy/releases/download/v2.14.0/ZAP_2.14.0_Linux.tar.gz
tar -xvf ZAP_2.14.0_Linux.tar.gz

# Run baseline scan
./ZAP_2.14.0/zap.sh -cmd -quickurl https://landsraad.arewel.com -quickout zap_report.html

# Run full active scan
./ZAP_2.14.0/zap.sh -cmd \
  -quickurl https://landsraad.arewel.com \
  -quickout zap_full_report.html \
  -quickprogress

# Install Nikto
git clone https://github.com/sullo/nikto.git
cd nikto/program
./nikto.pl -h https://landsraad.arewel.com -output nikto_report.html

# Run SQLMap for SQL injection testing
sqlmap -u "https://landsraad.arewel.com/api/v1/sites?search=test" \
  --cookie="session=xxx" \
  --level=5 \
  --risk=3 \
  --batch

# Run Nmap for port scanning
nmap -sV -sC -O -A -p- landsraad.arewel.com -oN nmap_scan.txt
```

**B. Manual Security Testing:**

1. **Authentication Testing:**
   - Brute force protection (rate limiting)
   - Session fixation
   - Session timeout
   - Password complexity enforcement
   - 2FA bypass attempts

2. **Authorization Testing:**
   - Horizontal privilege escalation (access other users' data)
   - Vertical privilege escalation (member → admin)
   - IDOR (Insecure Direct Object References)
   - Missing function level access control

3. **Input Validation:**
   - SQL injection
   - XSS (Cross-Site Scripting)
   - CSRF (Cross-Site Request Forgery)
   - File upload vulnerabilities
   - Command injection

4. **API Security:**
   - API token leakage
   - Mass assignment vulnerabilities
   - API rate limiting
   - Insecure API endpoints

5. **Infrastructure:**
   - SSL/TLS configuration (test with ssllabs.com)
   - Security headers (CSP, X-Frame-Options, etc.)
   - Information disclosure
   - Directory traversal

**C. Security Hardening Checklist:**

```bash
# On landsraad VPS

# 1. Enable security headers in Nginx
cat >> /etc/nginx/snippets/security-headers.conf <<EOF
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
EOF

# Include in server block
include snippets/security-headers.conf;

# 2. Disable unnecessary PHP functions
echo "disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source" >> /etc/php/8.2/fpm/php.ini

# 3. Configure fail2ban for Laravel
cat >> /etc/fail2ban/filter.d/laravel.conf <<EOF
[Definition]
failregex = ^.*"POST /api/v1/auth/login HTTP.*" 401 .*$
            ^.*authentication attempt failed.*<HOST>.*$
ignoreregex =
EOF

cat >> /etc/fail2ban/jail.local <<EOF
[laravel-auth]
enabled = true
port = http,https
filter = laravel
logpath = /var/www/chom/storage/logs/laravel.log
maxretry = 5
bantime = 3600
findtime = 600
EOF

systemctl restart fail2ban

# 4. Enable AppArmor profiles
apt-get install -y apparmor-utils
aa-enforce /etc/apparmor.d/*

# 5. Configure firewall (UFW)
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw allow from 51.254.139.78 # Prometheus
ufw enable

# 6. Secure MariaDB
mysql_secure_installation

# 7. Configure Redis authentication
echo "requirepass $(openssl rand -base64 32)" >> /etc/redis/redis.conf
systemctl restart redis

# 8. Enable audit logging
apt-get install -y auditd
systemctl enable auditd
systemctl start auditd
```

**Verification:**
- OWASP ZAP scan shows 0 high-risk vulnerabilities
- Nikto scan shows no critical issues
- SSL Labs rating: A+
- Security headers all present
- Rate limiting working
- fail2ban blocking brute force attempts

**Confidence Maintained:** 99%

---

#### 4.2 Disaster Recovery Testing (2 days)

**Deliverables:**
- Backup/restore tested at production scale
- Database disaster recovery verified
- VPS snapshot/restore tested
- RTO/RPO documented

**Implementation:**

**A. Test Database Backup/Restore:**

```bash
# On landsraad VPS

# 1. Create full database backup
mysqldump -u root -p \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --all-databases \
  --routines \
  --triggers \
  --events \
  | gzip > /backup/chom_full_$(date +%Y%m%d_%H%M%S).sql.gz

# 2. Simulate database corruption
systemctl stop mysql
rm -rf /var/lib/mysql/chom/*
systemctl start mysql

# 3. Restore from backup
gunzip < /backup/chom_full_20260102_120000.sql.gz | mysql -u root -p

# 4. Verify data integrity
mysql -u root -p -e "SELECT COUNT(*) FROM chom.users;"
mysql -u root -p -e "SELECT COUNT(*) FROM chom.sites;"
mysql -u root -p -e "SELECT COUNT(*) FROM chom.organizations;"

# 5. Test point-in-time recovery (binary logs)
mysqlbinlog --start-datetime="2026-01-02 12:00:00" \
            --stop-datetime="2026-01-02 13:00:00" \
            /var/log/mysql/mysql-bin.000001 \
            | mysql -u root -p
```

**B. Test Application Backup/Restore:**

```bash
# 1. Create application backup
tar -czf /backup/chom_app_$(date +%Y%m%d_%H%M%S).tar.gz \
  --exclude='vendor' \
  --exclude='node_modules' \
  --exclude='storage/logs/*' \
  --exclude='storage/framework/cache/*' \
  /var/www/chom

# 2. Simulate application corruption
rm -rf /var/www/chom

# 3. Restore from backup
tar -xzf /backup/chom_app_20260102_120000.tar.gz -C /var/www/

# 4. Rebuild dependencies
cd /var/www/chom
composer install --no-dev --optimize-autoloader
php artisan config:cache
php artisan route:cache
php artisan view:cache

# 5. Verify application
curl -I https://landsraad.arewel.com
php artisan health:check
```

**C. Test VPS Snapshot/Restore:**

```bash
# Using OVH API or control panel:

# 1. Create VPS snapshot
# OVH Control Panel > VPS > Snapshots > Create Snapshot
# OR via API:
curl -X POST https://api.ovh.com/1.0/vps/landsraad.arewel.com/snapshot \
  -H "X-Ovh-Application: xxx" \
  -H "X-Ovh-Consumer: xxx" \
  -H "X-Ovh-Signature: xxx"

# 2. Note snapshot ID and timestamp

# 3. Simulate complete system failure
# (Don't actually do this in production!)

# 4. Restore from snapshot
# OVH Control Panel > VPS > Snapshots > Restore
# OR via API:
curl -X POST https://api.ovh.com/1.0/vps/landsraad.arewel.com/restore \
  -H "X-Ovh-Application: xxx" \
  -d '{"snapshotId": "snapshot-xxx"}'

# 5. Verify restoration
ssh root@51.77.150.96
systemctl status nginx mariadb redis php8.2-fpm
curl -I https://landsraad.arewel.com
```

**D. Document RTO/RPO:**

| Scenario | RTO (Recovery Time) | RPO (Data Loss) | Procedure |
|----------|---------------------|-----------------|-----------|
| **Database Corruption** | 30 minutes | 1 hour | Restore from automated backup |
| **Application Corruption** | 15 minutes | 0 (code only) | Restore from Git + composer |
| **Complete VPS Failure** | 2 hours | 24 hours | Restore from OVH snapshot |
| **Database Server Failure** | 1 hour | 1 hour | Restore to new VPS from backup |
| **Regional Outage (OVH)** | 4-8 hours | 24 hours | Deploy to alternate provider |

**E. Create Disaster Recovery Runbook:**

```markdown
# Disaster Recovery Procedures

## Scenario 1: Database Corruption

1. Stop application: `systemctl stop php8.2-fpm`
2. Identify latest backup: `ls -lh /backup/chom_full_*.sql.gz`
3. Restore: `gunzip < backup.sql.gz | mysql -u root -p`
4. Verify: `php artisan db:show`
5. Start application: `systemctl start php8.2-fpm`
6. Monitor: Check `/var/log/nginx/error.log`

**Estimated Time:** 30 minutes
**Data Loss:** Last backup (hourly = max 1 hour loss)

## Scenario 2: Complete VPS Failure

1. Create new VPS at OVH (Debian 13, 2vCPU/4GB)
2. Configure DNS to point to new IP
3. Run deployment script: `./setup-vpsmanager-vps.sh`
4. Restore database: `gunzip < backup.sql.gz | mysql -u root -p`
5. Clone application: `git clone ...`
6. Configure .env with backup database credentials
7. Run migrations: `php artisan migrate --force`
8. Restore uploaded files: `tar -xzf storage_backup.tar.gz`
9. Test application: `curl -I https://landsraad.arewel.com`
10. Update Prometheus to scrape new IP

**Estimated Time:** 2 hours
**Data Loss:** Last database backup

## Scenario 3: Security Breach

1. Isolate system: `ufw deny from any to any`
2. Create forensic snapshot
3. Identify breach vector
4. Restore from known-good snapshot (pre-breach)
5. Patch vulnerability
6. Force password reset for all users
7. Invalidate all API tokens
8. Notify affected users (if applicable)
9. Document incident and lessons learned

**Estimated Time:** 4-8 hours
**Data Loss:** Since breach occurred
```

**Verification:**
- Database backup/restore tested successfully
- Application restore tested
- VPS snapshot/restore documented
- RTO/RPO targets established
- Runbook created and validated

**Confidence Maintained:** 99%

---

## 📈 Confidence Improvement Tracking

| Phase | Duration | Deliverables | Confidence Before | Confidence After | Gain |
|-------|----------|--------------|-------------------|------------------|------|
| **Current State** | - | All bugs fixed, 94% tests passing | - | 82% | - |
| **Phase 1: Quick Wins** | Week 1 | Email, networking, dashboards | 82% | 94% | +12% |
| **Phase 2: Integration Tests** | Week 2 | E2E test suite (30+ tests) | 94% | 99%+ | +10% |
| **Phase 3: Load Testing** | Week 2-3 | k6 benchmarks, baselines | 99% | 99% | Validation |
| **Phase 4: Security & DR** | Week 3 | Pen test, disaster recovery | 99% | 99% | Validation |

**Timeline:** 3 weeks to 99% confidence
**Total Effort:** ~80-100 hours of focused work

---

## ✅ Success Criteria for 99% Confidence

### Observability Stack (99%)
- [x] DNS configured and working
- [ ] VPS-to-VPS connectivity tested
- [ ] Grafana dashboards loaded (5 dashboards)
- [ ] Alert rules defined (10+ rules)
- [ ] Alertmanager notifications working
- [ ] Load tested (100+ concurrent metric writes)
- [ ] Security headers configured
- [ ] Backup/restore tested

### CHOM Application (99%)
- [ ] Email service configured (SendGrid/Mailgun)
- [ ] E2E tests passing (30+ scenarios)
- [ ] Load tested (100+ concurrent users)
- [ ] Response times < 500ms (p95)
- [ ] Error rate < 0.1%
- [ ] All 362 tests passing (100%)
- [ ] Security audit passed (0 critical vulns)
- [ ] Disaster recovery tested
- [ ] Real metrics flowing to Grafana
- [ ] Production monitoring in place

---

## 🎯 Next Steps

### Week 1: Quick Wins
1. **Day 1:** Configure SendGrid email service (+5%)
2. **Day 2:** Test VPS connectivity and configure Prometheus scraping (+3%)
3. **Day 3-4:** Load Grafana dashboards and alert rules (+4%)
4. **Day 5:** Verify all quick wins, fix any issues

**Checkpoint:** 94% confidence

### Week 2: Integration & Load Testing
1. **Day 6-8:** Implement Laravel Dusk E2E test suite (+10%)
2. **Day 9-10:** Implement k6 load testing and establish baselines
3. **Day 11-12:** Fix any remaining test failures, optimize performance

**Checkpoint:** 99% confidence (target reached!)

### Week 3: Security & Validation
1. **Day 13-14:** Security penetration testing
2. **Day 15-16:** Disaster recovery testing
3. **Day 17-18:** Final validation, documentation updates
4. **Day 19-21:** Buffer for unexpected issues

**Final Checkpoint:** 99% confidence (validated and maintained)

---

## 📊 Resource Requirements

### Human Resources
- **DevOps Engineer:** 20-30 hours (deployment, infrastructure)
- **QA Engineer:** 30-40 hours (E2E testing, load testing)
- **Security Engineer:** 10-15 hours (pen testing, audit)
- **Developer:** 20-30 hours (bug fixes, optimizations)

**Total:** 80-115 hours over 3 weeks

### Infrastructure Costs
- **SendGrid:** Free tier (100 emails/day)
- **k6 Cloud:** Free tier (50 VUh/month) OR self-hosted (free)
- **Security Tools:** Free/open-source (ZAP, Nikto, SQLMap)
- **Monitoring:** Already included (Prometheus, Grafana)

**Additional Cost:** $0/month (using free tiers)

### Tools Required
- Laravel Dusk (included)
- k6 load testing (free)
- OWASP ZAP (free)
- Nikto (free)
- SQLMap (free)
- SendGrid (free tier)

---

## 🚨 Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| **E2E tests reveal critical bugs** | High | Medium (30%) | Fix bugs before production, may delay timeline |
| **Load testing shows bottlenecks** | High | Medium (40%) | Optimize queries, add caching, scale resources |
| **Security audit finds vulnerabilities** | Critical | Low (15%) | Fix immediately, may require code changes |
| **Email service issues** | Medium | Low (10%) | Have backup SMTP provider ready |
| **Timeline slippage** | Medium | Medium (50%) | Built-in buffer (3 weeks for 2 weeks work) |

---

## 📝 Deliverables Checklist

### Documentation
- [ ] E2E test suite documentation
- [ ] Load testing report with benchmarks
- [ ] Security audit report
- [ ] Disaster recovery runbook
- [ ] Performance optimization guide
- [ ] Monitoring dashboard guide
- [ ] Email service setup guide

### Code
- [ ] 30+ E2E test scenarios (Dusk)
- [ ] Load testing scripts (k6)
- [ ] Security hardening scripts
- [ ] Alert rule definitions
- [ ] Grafana dashboard JSON exports
- [ ] Backup/restore automation scripts

### Infrastructure
- [ ] Grafana dashboards (5 dashboards)
- [ ] Prometheus alert rules (10+ rules)
- [ ] Alertmanager configuration
- [ ] Email service integration
- [ ] Security headers configuration
- [ ] fail2ban rules

---

## 🎬 Final Recommendation

**Confidence Target:** 99% (EXCELLENT)
**Timeline:** 3 weeks
**Effort:** 80-115 hours
**Cost:** $0/month (free tier services)

### Phase Priority:
1. **MUST DO:** Phase 1 (Quick Wins) - Gets to 94%, essential for production
2. **SHOULD DO:** Phase 2 (Integration Tests) - Gets to 99%, validates critical workflows
3. **NICE TO HAVE:** Phase 3 (Load Testing) - Maintains 99%, finds performance limits
4. **OPTIONAL:** Phase 4 (Security & DR) - Maintains 99%, reduces risk

### Minimum for 99%:
- Phase 1: Email + Networking + Dashboards (Week 1) = 94%
- Phase 2: E2E Testing (Week 2) = 99%

**You can achieve 99% confidence in 2 weeks** if you focus on Phases 1-2 only.

Phases 3-4 are validation and risk reduction, not confidence increasers.

---

**Ready to start? Begin with Phase 1, Day 1: Configure SendGrid!**
