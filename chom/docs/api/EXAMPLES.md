# CHOM API Examples

Real-world examples and code samples for common CHOM API use cases. Copy, paste, and adapt these examples to your needs.

## Table of Contents

- [Example 1: Create a WordPress Site](#example-1-create-a-wordpress-site)
- [Example 2: Automate Daily Backups](#example-2-automate-daily-backups)
- [Example 3: Monitor Site Metrics](#example-3-monitor-site-metrics)
- [Example 4: Manage Team Members](#example-4-manage-team-members)
- [Example 5: Restore from Backup](#example-5-restore-from-backup)
- [Example 6: Bulk Site Management](#example-6-bulk-site-management)
- [Example 7: SSL Certificate Management](#example-7-ssl-certificate-management)
- [Example 8: Site Migration Workflow](#example-8-site-migration-workflow)

---

## Example 1: Create a WordPress Site

**Use Case:** Provision a new WordPress site with SSL and custom PHP version.

### Using cURL

```bash
# 1. Login and get token
TOKEN=$(curl -X POST https://api.chom.example.com/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john@example.com",
    "password": "SecurePass123!"
  }' | jq -r '.data.token')

# 2. Create the site
curl -X POST https://api.chom.example.com/api/v1/sites \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "myblog.com",
    "site_type": "wordpress",
    "php_version": "8.2",
    "ssl_enabled": true
  }' | jq .

# 3. Check site status
SITE_ID="550e8400-e29b-41d4-a716-446655440000"
curl -X GET https://api.chom.example.com/api/v1/sites/$SITE_ID \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Using PHP

```php
<?php

class ChomClient {
    private $baseUrl = 'https://api.chom.example.com/api/v1';
    private $token;

    public function __construct($email, $password) {
        $this->token = $this->login($email, $password);
    }

    private function login($email, $password) {
        $response = $this->request('POST', '/auth/login', [
            'email' => $email,
            'password' => $password
        ]);
        return $response['data']['token'];
    }

    public function createSite($domain, $siteType = 'wordpress', $phpVersion = '8.2') {
        return $this->request('POST', '/sites', [
            'domain' => $domain,
            'site_type' => $siteType,
            'php_version' => $phpVersion,
            'ssl_enabled' => true
        ]);
    }

    public function getSite($siteId) {
        return $this->request('GET', "/sites/{$siteId}");
    }

    private function request($method, $endpoint, $data = null) {
        $url = $this->baseUrl . $endpoint;
        $headers = [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->token
        ];

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $method);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, $headers);

        if ($data !== null) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }

        $response = curl_exec($ch);
        curl_close($ch);

        return json_decode($response, true);
    }
}

// Usage
$chom = new ChomClient('john@example.com', 'SecurePass123!');

// Create site
$result = $chom->createSite('myblog.com', 'wordpress', '8.2');
echo "Site created: " . $result['data']['id'] . "\n";

// Check site status
$siteId = $result['data']['id'];
$site = $chom->getSite($siteId);
echo "Site status: " . $site['data']['status'] . "\n";
```

### Using JavaScript (Node.js)

```javascript
const axios = require('axios');

class ChomClient {
  constructor(baseUrl = 'https://api.chom.example.com/api/v1') {
    this.baseUrl = baseUrl;
    this.token = null;
  }

  async login(email, password) {
    const response = await axios.post(`${this.baseUrl}/auth/login`, {
      email,
      password
    });
    this.token = response.data.data.token;
    return this.token;
  }

  async createSite(domain, siteType = 'wordpress', phpVersion = '8.2') {
    const response = await axios.post(
      `${this.baseUrl}/sites`,
      {
        domain,
        site_type: siteType,
        php_version: phpVersion,
        ssl_enabled: true
      },
      {
        headers: { 'Authorization': `Bearer ${this.token}` }
      }
    );
    return response.data;
  }

  async getSite(siteId) {
    const response = await axios.get(
      `${this.baseUrl}/sites/${siteId}`,
      {
        headers: { 'Authorization': `Bearer ${this.token}` }
      }
    );
    return response.data;
  }

  async waitForSiteActive(siteId, maxAttempts = 30) {
    for (let i = 0; i < maxAttempts; i++) {
      const site = await this.getSite(siteId);
      const status = site.data.status;

      console.log(`Attempt ${i + 1}: Site status is ${status}`);

      if (status === 'active') {
        return site;
      } else if (status === 'failed') {
        throw new Error('Site creation failed');
      }

      // Wait 10 seconds before next check
      await new Promise(resolve => setTimeout(resolve, 10000));
    }

    throw new Error('Site creation timeout');
  }
}

// Usage
(async () => {
  const chom = new ChomClient();

  try {
    // Login
    await chom.login('john@example.com', 'SecurePass123!');
    console.log('Logged in successfully');

    // Create site
    const result = await chom.createSite('myblog.com');
    console.log('Site creation started:', result.data.id);

    // Wait for site to become active
    const site = await chom.waitForSiteActive(result.data.id);
    console.log('Site is now active:', site.data.url);

  } catch (error) {
    console.error('Error:', error.response?.data || error.message);
  }
})();
```

### Using Python

```python
import requests
import time
from typing import Optional

class ChomClient:
    def __init__(self, base_url: str = 'https://api.chom.example.com/api/v1'):
        self.base_url = base_url
        self.token: Optional[str] = None

    def login(self, email: str, password: str) -> str:
        """Login and store the authentication token"""
        response = requests.post(
            f'{self.base_url}/auth/login',
            json={'email': email, 'password': password}
        )
        response.raise_for_status()
        self.token = response.json()['data']['token']
        return self.token

    def _headers(self) -> dict:
        """Get request headers with authentication"""
        return {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        }

    def create_site(self, domain: str, site_type: str = 'wordpress',
                   php_version: str = '8.2') -> dict:
        """Create a new site"""
        response = requests.post(
            f'{self.base_url}/sites',
            headers=self._headers(),
            json={
                'domain': domain,
                'site_type': site_type,
                'php_version': php_version,
                'ssl_enabled': True
            }
        )
        response.raise_for_status()
        return response.json()

    def get_site(self, site_id: str) -> dict:
        """Get site details"""
        response = requests.get(
            f'{self.base_url}/sites/{site_id}',
            headers=self._headers()
        )
        response.raise_for_status()
        return response.json()

    def wait_for_site_active(self, site_id: str, max_attempts: int = 30) -> dict:
        """Poll site status until it becomes active"""
        for attempt in range(max_attempts):
            site = self.get_site(site_id)
            status = site['data']['status']

            print(f"Attempt {attempt + 1}: Site status is {status}")

            if status == 'active':
                return site
            elif status == 'failed':
                raise Exception('Site creation failed')

            time.sleep(10)  # Wait 10 seconds

        raise Exception('Site creation timeout')

# Usage
if __name__ == '__main__':
    chom = ChomClient()

    # Login
    chom.login('john@example.com', 'SecurePass123!')
    print('Logged in successfully')

    # Create site
    result = chom.create_site('myblog.com')
    site_id = result['data']['id']
    print(f'Site creation started: {site_id}')

    # Wait for site to become active
    site = chom.wait_for_site_active(site_id)
    print(f"Site is now active: {site['data']['url']}")
```

---

## Example 2: Automate Daily Backups

**Use Case:** Create automated backup script that runs daily via cron.

### Bash Script for Cron

```bash
#!/bin/bash
# File: /opt/scripts/chom-backup.sh
# Cron: 0 2 * * * /opt/scripts/chom-backup.sh

set -e

# Configuration
CHOM_API="https://api.chom.example.com/api/v1"
CHOM_EMAIL="admin@example.com"
CHOM_PASSWORD="SecurePass123!"
LOG_FILE="/var/log/chom-backup.log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Login and get token
log "Logging in to CHOM API..."
TOKEN=$(curl -s -X POST "$CHOM_API/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$CHOM_EMAIL\",\"password\":\"$CHOM_PASSWORD\"}" \
    | jq -r '.data.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    log "ERROR: Failed to authenticate"
    exit 1
fi

log "Successfully authenticated"

# Get all active sites
log "Fetching active sites..."
SITES=$(curl -s -X GET "$CHOM_API/sites?status=active&per_page=100" \
    -H "Authorization: Bearer $TOKEN" \
    | jq -r '.data[].id')

# Create backup for each site
for SITE_ID in $SITES; do
    log "Creating backup for site: $SITE_ID"

    BACKUP_RESULT=$(curl -s -X POST "$CHOM_API/sites/$SITE_ID/backups" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "backup_type": "full",
            "retention_days": 30
        }')

    BACKUP_ID=$(echo "$BACKUP_RESULT" | jq -r '.data.id')

    if [ "$BACKUP_ID" != "null" ]; then
        log "  ✓ Backup queued: $BACKUP_ID"
    else
        ERROR=$(echo "$BACKUP_RESULT" | jq -r '.error.message')
        log "  ✗ Backup failed: $ERROR"
    fi
done

log "Backup process completed"
```

### Python Script with Email Notifications

```python
#!/usr/bin/env python3
# File: /opt/scripts/chom_backup.py

import requests
import smtplib
from email.mime.text import MIMEText
from datetime import datetime
import logging

# Configuration
CHOM_API = 'https://api.chom.example.com/api/v1'
CHOM_EMAIL = 'admin@example.com'
CHOM_PASSWORD = 'SecurePass123!'

SMTP_SERVER = 'smtp.gmail.com'
SMTP_PORT = 587
SMTP_USER = 'notifications@example.com'
SMTP_PASSWORD = 'smtp-password'
NOTIFY_EMAIL = 'admin@example.com'

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/chom-backup.log'),
        logging.StreamHandler()
    ]
)

class BackupManager:
    def __init__(self):
        self.token = None
        self.results = {'success': [], 'failed': []}

    def login(self):
        """Authenticate with CHOM API"""
        response = requests.post(
            f'{CHOM_API}/auth/login',
            json={'email': CHOM_EMAIL, 'password': CHOM_PASSWORD}
        )
        response.raise_for_status()
        self.token = response.json()['data']['token']
        logging.info('Successfully authenticated')

    def get_headers(self):
        return {
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        }

    def get_active_sites(self):
        """Fetch all active sites"""
        response = requests.get(
            f'{CHOM_API}/sites',
            headers=self.get_headers(),
            params={'status': 'active', 'per_page': 100}
        )
        response.raise_for_status()
        return response.json()['data']

    def create_backup(self, site_id, domain):
        """Create backup for a site"""
        try:
            response = requests.post(
                f'{CHOM_API}/sites/{site_id}/backups',
                headers=self.get_headers(),
                json={'backup_type': 'full', 'retention_days': 30}
            )
            response.raise_for_status()

            backup_id = response.json()['data']['id']
            logging.info(f'✓ Backup queued for {domain}: {backup_id}')
            self.results['success'].append(domain)

        except requests.exceptions.RequestException as e:
            logging.error(f'✗ Backup failed for {domain}: {str(e)}')
            self.results['failed'].append(domain)

    def send_notification(self):
        """Send email notification with results"""
        success_count = len(self.results['success'])
        failed_count = len(self.results['failed'])

        subject = f'CHOM Backup Report - {success_count} Success, {failed_count} Failed'

        body = f"""CHOM Backup Report - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

Successful Backups ({success_count}):
{chr(10).join('  ✓ ' + site for site in self.results['success']) if self.results['success'] else '  None'}

Failed Backups ({failed_count}):
{chr(10).join('  ✗ ' + site for site in self.results['failed']) if self.results['failed'] else '  None'}

Total Sites Processed: {success_count + failed_count}
"""

        msg = MIMEText(body)
        msg['Subject'] = subject
        msg['From'] = SMTP_USER
        msg['To'] = NOTIFY_EMAIL

        try:
            with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
                server.starttls()
                server.login(SMTP_USER, SMTP_PASSWORD)
                server.send_message(msg)
            logging.info('Notification email sent')
        except Exception as e:
            logging.error(f'Failed to send notification: {str(e)}')

    def run(self):
        """Main backup routine"""
        logging.info('Starting backup process')

        try:
            self.login()
            sites = self.get_active_sites()

            logging.info(f'Found {len(sites)} active sites')

            for site in sites:
                self.create_backup(site['id'], site['domain'])

            logging.info('Backup process completed')
            self.send_notification()

        except Exception as e:
            logging.error(f'Backup process failed: {str(e)}')
            raise

if __name__ == '__main__':
    manager = BackupManager()
    manager.run()
```

---

## Example 3: Monitor Site Metrics

**Use Case:** Monitor site performance and send alerts when metrics exceed thresholds.

### Node.js Monitoring Script

```javascript
const axios = require('axios');
const nodemailer = require('nodemailer');

class SiteMonitor {
  constructor(config) {
    this.config = config;
    this.token = null;
    this.alerts = [];
  }

  async login() {
    const response = await axios.post(
      `${this.config.apiUrl}/auth/login`,
      {
        email: this.config.email,
        password: this.config.password
      }
    );
    this.token = response.data.data.token;
  }

  getHeaders() {
    return { 'Authorization': `Bearer ${this.token}` };
  }

  async getSites() {
    const response = await axios.get(
      `${this.config.apiUrl}/sites`,
      {
        headers: this.getHeaders(),
        params: { status: 'active', per_page: 100 }
      }
    );
    return response.data.data;
  }

  async getSiteMetrics(siteId) {
    const response = await axios.get(
      `${this.config.apiUrl}/sites/${siteId}/metrics`,
      { headers: this.getHeaders() }
    );
    return response.data.data;
  }

  checkThresholds(site, metrics) {
    const alerts = [];
    const m = metrics.metrics;

    // Check response time
    if (m.response_time_ms > this.config.thresholds.responseTime) {
      alerts.push({
        site: site.domain,
        metric: 'Response Time',
        value: m.response_time_ms,
        threshold: this.config.thresholds.responseTime,
        severity: 'warning'
      });
    }

    // Check storage usage
    if (m.storage_used_mb > this.config.thresholds.storage) {
      alerts.push({
        site: site.domain,
        metric: 'Storage Usage',
        value: m.storage_used_mb,
        threshold: this.config.thresholds.storage,
        severity: 'warning'
      });
    }

    // Check request rate
    if (m.requests_per_minute > this.config.thresholds.requestRate) {
      alerts.push({
        site: site.domain,
        metric: 'Request Rate',
        value: m.requests_per_minute,
        threshold: this.config.thresholds.requestRate,
        severity: 'info'
      });
    }

    return alerts;
  }

  async sendAlerts() {
    if (this.alerts.length === 0) {
      console.log('No alerts to send');
      return;
    }

    const transporter = nodemailer.createTransport({
      host: this.config.smtp.host,
      port: this.config.smtp.port,
      secure: false,
      auth: {
        user: this.config.smtp.user,
        pass: this.config.smtp.password
      }
    });

    const alertsText = this.alerts.map(a =>
      `[${a.severity.toUpperCase()}] ${a.site} - ${a.metric}: ${a.value} (threshold: ${a.threshold})`
    ).join('\n');

    await transporter.sendMail({
      from: this.config.smtp.user,
      to: this.config.notifyEmail,
      subject: `CHOM Site Monitoring Alert - ${this.alerts.length} issues detected`,
      text: `Site Monitoring Report\n\n${alertsText}`
    });

    console.log(`Sent alert email with ${this.alerts.length} issues`);
  }

  async monitor() {
    try {
      console.log('Starting site monitoring...');

      await this.login();
      const sites = await this.getSites();

      console.log(`Monitoring ${sites.length} sites`);

      for (const site of sites) {
        try {
          const metrics = await this.getSiteMetrics(site.id);
          const alerts = this.checkThresholds(site, metrics);
          this.alerts.push(...alerts);

          console.log(`${site.domain}: ${alerts.length} alerts`);
        } catch (error) {
          console.error(`Failed to get metrics for ${site.domain}:`, error.message);
        }
      }

      await this.sendAlerts();
      console.log('Monitoring completed');

    } catch (error) {
      console.error('Monitoring failed:', error.message);
      throw error;
    }
  }
}

// Configuration
const config = {
  apiUrl: 'https://api.chom.example.com/api/v1',
  email: 'admin@example.com',
  password: 'SecurePass123!',
  notifyEmail: 'alerts@example.com',
  thresholds: {
    responseTime: 500,    // milliseconds
    storage: 5000,        // MB
    requestRate: 1000     // requests per minute
  },
  smtp: {
    host: 'smtp.gmail.com',
    port: 587,
    user: 'notifications@example.com',
    password: 'smtp-password'
  }
};

// Run monitoring
const monitor = new SiteMonitor(config);
monitor.monitor().catch(console.error);
```

---

## Example 4: Manage Team Members

**Use Case:** Bulk invite team members and manage roles programmatically.

### Python Script for Team Management

```python
import requests
import csv
from typing import List, Dict

class TeamManager:
    def __init__(self, api_url: str, email: str, password: str):
        self.api_url = api_url
        self.token = self._login(email, password)

    def _login(self, email: str, password: str) -> str:
        response = requests.post(
            f'{self.api_url}/auth/login',
            json={'email': email, 'password': password}
        )
        response.raise_for_status()
        return response.json()['data']['token']

    def _headers(self) -> dict:
        return {'Authorization': f'Bearer {self.token}'}

    def invite_member(self, email: str, role: str, name: str = None) -> dict:
        """Invite a new team member"""
        payload = {'email': email, 'role': role}
        if name:
            payload['name'] = name

        response = requests.post(
            f'{self.api_url}/team/invitations',
            headers=self._headers(),
            json=payload
        )
        response.raise_for_status()
        return response.json()

    def bulk_invite_from_csv(self, csv_file: str) -> Dict[str, List]:
        """Invite multiple members from a CSV file

        CSV format: email,role,name
        Example:
            jane@example.com,member,Jane Doe
            bob@example.com,admin,Bob Smith
        """
        results = {'success': [], 'failed': []}

        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    result = self.invite_member(
                        email=row['email'],
                        role=row['role'],
                        name=row.get('name')
                    )
                    results['success'].append(row['email'])
                    print(f"✓ Invited {row['email']} as {row['role']}")
                except Exception as e:
                    results['failed'].append({
                        'email': row['email'],
                        'error': str(e)
                    })
                    print(f"✗ Failed to invite {row['email']}: {str(e)}")

        return results

    def list_members(self) -> List[dict]:
        """Get all team members"""
        response = requests.get(
            f'{self.api_url}/team/members',
            headers=self._headers(),
            params={'per_page': 100}
        )
        response.raise_for_status()
        return response.json()['data']

    def update_member_role(self, user_id: str, new_role: str) -> dict:
        """Update a team member's role"""
        response = requests.patch(
            f'{self.api_url}/team/members/{user_id}',
            headers=self._headers(),
            json={'role': new_role}
        )
        response.raise_for_status()
        return response.json()

    def remove_member(self, user_id: str) -> dict:
        """Remove a team member"""
        response = requests.delete(
            f'{self.api_url}/team/members/{user_id}',
            headers=self._headers()
        )
        response.raise_for_status()
        return response.json()

# Usage example
if __name__ == '__main__':
    manager = TeamManager(
        api_url='https://api.chom.example.com/api/v1',
        email='admin@example.com',
        password='SecurePass123!'
    )

    # Bulk invite from CSV
    results = manager.bulk_invite_from_csv('team_members.csv')
    print(f"\nInvitations sent: {len(results['success'])}")
    print(f"Failed invitations: {len(results['failed'])}")

    # List all members
    members = manager.list_members()
    print(f"\nTotal team members: {len(members)}")
    for member in members:
        print(f"  - {member['email']} ({member['role']})")
```

---

## Example 5: Restore from Backup

**Use Case:** Restore a site from the most recent backup.

### Bash Script

```bash
#!/bin/bash
# restore-site.sh - Restore a site from its most recent backup

set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <email> <password> <site_id>"
    exit 1
fi

API_URL="https://api.chom.example.com/api/v1"
EMAIL="$1"
PASSWORD="$2"
SITE_ID="$3"

# Login
echo "Logging in..."
TOKEN=$(curl -s -X POST "$API_URL/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    | jq -r '.data.token')

# Get site backups
echo "Fetching backups for site..."
BACKUPS=$(curl -s -X GET "$API_URL/sites/$SITE_ID/backups?per_page=100" \
    -H "Authorization: Bearer $TOKEN")

# Get most recent completed backup
LATEST_BACKUP=$(echo "$BACKUPS" | jq -r '.data | map(select(.is_ready == true)) | sort_by(.created_at) | reverse | .[0]')

if [ "$LATEST_BACKUP" == "null" ]; then
    echo "ERROR: No completed backups found for this site"
    exit 1
fi

BACKUP_ID=$(echo "$LATEST_BACKUP" | jq -r '.id')
BACKUP_DATE=$(echo "$LATEST_BACKUP" | jq -r '.created_at')
BACKUP_SIZE=$(echo "$LATEST_BACKUP" | jq -r '.size')

echo "Found backup:"
echo "  ID: $BACKUP_ID"
echo "  Date: $BACKUP_DATE"
echo "  Size: $BACKUP_SIZE"
echo ""

read -p "Do you want to restore from this backup? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

# Initiate restore
echo "Initiating restore..."
RESTORE_RESULT=$(curl -s -X POST "$API_URL/backups/$BACKUP_ID/restore" \
    -H "Authorization: Bearer $TOKEN")

SUCCESS=$(echo "$RESTORE_RESULT" | jq -r '.success')

if [ "$SUCCESS" == "true" ]; then
    echo "✓ Restore initiated successfully"
    echo "  Message: $(echo "$RESTORE_RESULT" | jq -r '.message')"
    echo ""
    echo "The restore process may take several minutes."
    echo "Monitor site status with: GET /sites/$SITE_ID"
else
    echo "✗ Restore failed"
    echo "  Error: $(echo "$RESTORE_RESULT" | jq -r '.error.message')"
    exit 1
fi
```

---

## Example 6: Bulk Site Management

**Use Case:** Manage multiple sites at once (upgrade PHP, enable/disable, etc.).

### Python Script

```python
import requests
from typing import List
import concurrent.futures

class BulkSiteManager:
    def __init__(self, api_url: str, token: str):
        self.api_url = api_url
        self.token = token

    def _headers(self):
        return {'Authorization': f'Bearer {self.token}'}

    def get_all_sites(self, status: str = None) -> List[dict]:
        """Fetch all sites, optionally filtered by status"""
        params = {'per_page': 100}
        if status:
            params['status'] = status

        response = requests.get(
            f'{self.api_url}/sites',
            headers=self._headers(),
            params=params
        )
        response.raise_for_status()
        return response.json()['data']

    def update_php_version(self, site_id: str, php_version: str) -> dict:
        """Update PHP version for a site"""
        response = requests.patch(
            f'{self.api_url}/sites/{site_id}',
            headers=self._headers(),
            json={'php_version': php_version}
        )
        response.raise_for_status()
        return response.json()

    def bulk_update_php(self, php_version: str, filter_type: str = None):
        """Update PHP version for multiple sites"""
        sites = self.get_all_sites(status='active')

        # Filter by type if specified
        if filter_type:
            sites = [s for s in sites if s['site_type'] == filter_type]

        print(f"Updating PHP version to {php_version} for {len(sites)} sites...")

        results = {'success': [], 'failed': []}

        # Use thread pool for parallel updates
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_site = {
                executor.submit(
                    self.update_php_version,
                    site['id'],
                    php_version
                ): site for site in sites
            }

            for future in concurrent.futures.as_completed(future_to_site):
                site = future_to_site[future]
                try:
                    future.result()
                    results['success'].append(site['domain'])
                    print(f"✓ Updated {site['domain']}")
                except Exception as e:
                    results['failed'].append({
                        'domain': site['domain'],
                        'error': str(e)
                    })
                    print(f"✗ Failed {site['domain']}: {str(e)}")

        return results

    def bulk_enable_ssl(self):
        """Enable SSL for all sites that don't have it"""
        sites = self.get_all_sites(status='active')
        sites_without_ssl = [s for s in sites if not s.get('ssl_enabled')]

        print(f"Enabling SSL for {len(sites_without_ssl)} sites...")

        for site in sites_without_ssl:
            try:
                requests.post(
                    f'{self.api_url}/sites/{site["id"]}/ssl',
                    headers=self._headers()
                )
                print(f"✓ SSL enabled for {site['domain']}")
            except Exception as e:
                print(f"✗ Failed {site['domain']}: {str(e)}")

# Usage
if __name__ == '__main__':
    # Login first
    auth_response = requests.post(
        'https://api.chom.example.com/api/v1/auth/login',
        json={'email': 'admin@example.com', 'password': 'SecurePass123!'}
    )
    token = auth_response.json()['data']['token']

    manager = BulkSiteManager('https://api.chom.example.com/api/v1', token)

    # Update all WordPress sites to PHP 8.4
    results = manager.bulk_update_php('8.4', filter_type='wordpress')
    print(f"\nUpdated: {len(results['success'])} sites")
    print(f"Failed: {len(results['failed'])} sites")

    # Enable SSL for all sites
    manager.bulk_enable_ssl()
```

---

## Example 7: SSL Certificate Management

**Use Case:** Monitor SSL certificate expiration and renew certificates.

### JavaScript SSL Monitor

```javascript
const axios = require('axios');

class SSLMonitor {
  constructor(apiUrl, token) {
    this.apiUrl = apiUrl;
    this.token = token;
  }

  async getSites() {
    const response = await axios.get(
      `${this.apiUrl}/sites`,
      {
        headers: { 'Authorization': `Bearer ${this.token}` },
        params: { status: 'active', per_page: 100 }
      }
    );
    return response.data.data;
  }

  async renewSSL(siteId) {
    const response = await axios.post(
      `${this.apiUrl}/sites/${siteId}/ssl`,
      {},
      { headers: { 'Authorization': `Bearer ${this.token}` } }
    );
    return response.data;
  }

  isExpiringSoon(expiresAt, days = 30) {
    if (!expiresAt) return false;

    const expiryDate = new Date(expiresAt);
    const now = new Date();
    const daysUntilExpiry = (expiryDate - now) / (1000 * 60 * 60 * 24);

    return daysUntilExpiry <= days && daysUntilExpiry > 0;
  }

  async checkAndRenewCertificates() {
    const sites = await this.getSites();
    const sslSites = sites.filter(s => s.ssl_enabled);

    console.log(`Checking ${sslSites.length} sites with SSL...`);

    const expiring = [];
    const renewed = [];
    const failed = [];

    for (const site of sslSites) {
      if (this.isExpiringSoon(site.ssl_expires_at, 30)) {
        expiring.push(site);

        try {
          await this.renewSSL(site.id);
          renewed.push(site.domain);
          console.log(`✓ Renewed SSL for ${site.domain}`);
        } catch (error) {
          failed.push({ domain: site.domain, error: error.message });
          console.log(`✗ Failed to renew ${site.domain}: ${error.message}`);
        }
      }
    }

    return { expiring, renewed, failed };
  }
}

// Usage
(async () => {
  // Login
  const authResponse = await axios.post(
    'https://api.chom.example.com/api/v1/auth/login',
    { email: 'admin@example.com', password: 'SecurePass123!' }
  );
  const token = authResponse.data.data.token;

  // Check and renew
  const monitor = new SSLMonitor('https://api.chom.example.com/api/v1', token);
  const results = await monitor.checkAndRenewCertificates();

  console.log(`\nExpiring soon: ${results.expiring.length}`);
  console.log(`Renewed: ${results.renewed.length}`);
  console.log(`Failed: ${results.failed.length}`);
})();
```

---

## Example 8: Site Migration Workflow

**Use Case:** Migrate a site to a new domain with backup and restore.

### Complete Migration Script (Python)

```python
import requests
import time
from typing import Optional

class SiteMigration:
    def __init__(self, api_url: str, token: str):
        self.api_url = api_url
        self.token = token

    def _headers(self):
        return {'Authorization': f'Bearer {self.token}'}

    def create_backup(self, site_id: str) -> str:
        """Create a backup and return backup ID"""
        print(f"Creating backup...")
        response = requests.post(
            f'{self.api_url}/sites/{site_id}/backups',
            headers=self._headers(),
            json={'backup_type': 'full', 'retention_days': 7}
        )
        response.raise_for_status()
        return response.json()['data']['id']

    def wait_for_backup(self, backup_id: str, timeout: int = 600):
        """Wait for backup to complete"""
        print(f"Waiting for backup to complete...")
        start_time = time.time()

        while time.time() - start_time < timeout:
            response = requests.get(
                f'{self.api_url}/backups/{backup_id}',
                headers=self._headers()
            )
            backup = response.json()['data']

            if backup['is_ready']:
                print(f"✓ Backup completed ({backup['size']})")
                return backup

            print(f"  Backup status: In progress...")
            time.sleep(10)

        raise TimeoutError('Backup timeout')

    def create_site(self, domain: str, site_type: str = 'wordpress') -> str:
        """Create new site and return site ID"""
        print(f"Creating new site: {domain}")
        response = requests.post(
            f'{self.api_url}/sites',
            headers=self._headers(),
            json={
                'domain': domain,
                'site_type': site_type,
                'ssl_enabled': True
            }
        )
        response.raise_for_status()
        return response.json()['data']['id']

    def wait_for_site_active(self, site_id: str, timeout: int = 600):
        """Wait for site to become active"""
        print(f"Waiting for site to become active...")
        start_time = time.time()

        while time.time() - start_time < timeout:
            response = requests.get(
                f'{self.api_url}/sites/{site_id}',
                headers=self._headers()
            )
            site = response.json()['data']

            if site['status'] == 'active':
                print(f"✓ Site is now active")
                return site
            elif site['status'] == 'failed':
                raise Exception('Site creation failed')

            print(f"  Site status: {site['status']}")
            time.sleep(10)

        raise TimeoutError('Site creation timeout')

    def migrate(self, source_site_id: str, new_domain: str):
        """Complete migration workflow"""
        print(f"\n=== Starting Migration ===")
        print(f"Source Site ID: {source_site_id}")
        print(f"New Domain: {new_domain}\n")

        try:
            # Step 1: Create backup of source
            backup_id = self.create_backup(source_site_id)
            backup = self.wait_for_backup(backup_id)

            # Step 2: Create new site
            new_site_id = self.create_site(new_domain)
            new_site = self.wait_for_site_active(new_site_id)

            # Step 3: Restore backup to new site
            print(f"\nNote: Restore backup {backup_id} to new site {new_site_id} manually")
            print(f"      (Automated cross-site restore may not be supported)")

            print(f"\n=== Migration Completed ===")
            print(f"New Site ID: {new_site_id}")
            print(f"New Site URL: {new_site['url']}")
            print(f"Backup ID: {backup_id}")

            return {
                'backup_id': backup_id,
                'new_site_id': new_site_id,
                'new_site': new_site
            }

        except Exception as e:
            print(f"\n✗ Migration failed: {str(e)}")
            raise

# Usage
if __name__ == '__main__':
    # Login
    auth_response = requests.post(
        'https://api.chom.example.com/api/v1/auth/login',
        json={'email': 'admin@example.com', 'password': 'SecurePass123!'}
    )
    token = auth_response.json()['data']['token']

    # Migrate site
    migration = SiteMigration('https://api.chom.example.com/api/v1', token)
    result = migration.migrate(
        source_site_id='550e8400-e29b-41d4-a716-446655440000',
        new_domain='newdomain.com'
    )
```

---

## Additional Resources

- **[Quick Start Guide](./QUICK-START.md)** - Get started in 5 minutes
- **[API Cheat Sheet](./CHEAT-SHEET.md)** - Quick reference for all endpoints
- **[Error Handling Guide](./ERRORS.md)** - Comprehensive error reference
- **[OpenAPI Specification](../../openapi.yaml)** - Complete API documentation

## Tips for Production Use

1. **Error Handling**: Always implement proper error handling and retry logic
2. **Rate Limiting**: Respect rate limits and implement backoff strategies
3. **Logging**: Log all API interactions for debugging and auditing
4. **Security**: Never hardcode credentials - use environment variables
5. **Monitoring**: Set up monitoring and alerting for critical operations
6. **Testing**: Test scripts in a staging environment first

---

**Need help?** Contact support@chom.example.com or check the [API documentation](../API-README.md).
