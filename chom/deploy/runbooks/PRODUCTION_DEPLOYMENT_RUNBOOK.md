# CHOM Production Deployment Runbook

**Version:** 1.0.0
**Last Updated:** 2026-01-02
**Environment:** Production (Bare VPS, Debian 13)
**Target Systems:**
- Observability: mentat.arewel.com (51.254.139.78)
- CHOM Application: landsraad.arewel.com (51.77.150.96)

---

## Table of Contents

1. [Overview](#1-overview)
2. [Pre-Deployment Checklist](#2-pre-deployment-checklist)
3. [Deployment Steps - Observability Stack](#3-deployment-steps---observability-stack)
4. [Deployment Steps - CHOM Application](#4-deployment-steps---chom-application)
5. [Post-Deployment Validation](#5-post-deployment-validation)
6. [Rollback Procedures](#6-rollback-procedures)
7. [Troubleshooting Guide](#7-troubleshooting-guide)
8. [Production Hardening](#8-production-hardening)
9. [Emergency Procedures](#9-emergency-procedures)
10. [Appendix](#10-appendix)

---

## 1. Overview

### 1.1 Purpose

This runbook provides step-by-step procedures for deploying the CHOM application and observability stack to production bare VPS servers running Debian 13.

### 1.2 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Production Architecture                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌────────────────────────┐    ┌─────────────────────────┐ │
│  │  mentat.arewel.com     │    │ landsraad.arewel.com    │ │
│  │  (51.254.139.78)       │    │ (51.77.150.96)          │ │
│  │  Observability Stack   │◄───┤ CHOM Application        │ │
│  │                        │    │                         │ │
│  │  - Prometheus:9090     │    │ - Nginx:80/443          │ │
│  │  - Grafana:3000        │    │ - PHP-FPM:9000          │ │
│  │  - Loki:3100           │    │ - MySQL:3306            │ │
│  │  - Tempo:4318          │    │ - Redis:6379            │ │
│  │  - Alertmanager:9093   │    │ - Queue Workers         │ │
│  └────────────────────────┘    │ - Promtail → Loki       │ │
│                                 │ - Metrics → Prometheus  │ │
│                                 └─────────────────────────┘ │
│                                                             │
│  Network Requirements:                                      │
│  - landsraad → mentat: 9090, 3100, 4318, 3000, 9093        │
│  - mentat → landsraad: 80, 443, /metrics endpoint          │
│  - Internet → landsraad: 80, 443 (public access)           │
│  - Internet → mentat: 3000 (Grafana public access)         │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Deployment Phases

| Phase | Component | Duration | Downtime |
|-------|-----------|----------|----------|
| 1 | Pre-deployment validation | 30 min | None |
| 2 | Observability stack deployment | 45 min | None |
| 3 | CHOM application deployment | 60 min | 5-10 min |
| 4 | Post-deployment validation | 30 min | None |
| **Total** | **Complete deployment** | **~3 hours** | **5-10 min** |

### 1.4 Roles and Responsibilities

| Role | Name | Contact | Responsibilities |
|------|------|---------|------------------|
| Deployment Lead | TBD | TBD | Overall deployment coordination |
| Infrastructure Engineer | TBD | TBD | VPS setup, network configuration |
| Application Engineer | TBD | TBD | CHOM deployment, configuration |
| Database Administrator | TBD | TBD | MySQL setup, migrations |
| Security Engineer | TBD | TBD | SSL, firewall, security hardening |
| Monitoring Engineer | TBD | TBD | Observability stack, alerts |

### 1.5 Communication Plan

- **Deployment Channel**: Slack #production-deploys
- **Incident Channel**: Slack #incidents
- **Status Page**: status.arewel.com (if available)
- **Escalation Path**: Engineer → Team Lead → Engineering Manager → CTO

---

## 2. Pre-Deployment Checklist

### 2.1 Infrastructure Prerequisites

#### 2.1.1 VPS Verification

**mentat.arewel.com (Observability)**

```bash
# Verify SSH access
ssh deploy@mentat.arewel.com "uname -a"
# Expected: Linux mentat 6.x.x Debian 13

# Verify resources
ssh deploy@mentat.arewel.com "free -h && df -h && nproc"
# Expected:
#   - RAM: 2GB minimum
#   - Disk: 40GB minimum, 20GB free
#   - CPU: 2 cores minimum

# Verify network
ssh deploy@mentat.arewel.com "ip addr show && ping -c 3 8.8.8.8"
# Expected: Public IP 51.254.139.78, internet connectivity

# Verify sudo access
ssh deploy@mentat.arewel.com "sudo whoami"
# Expected: root
```

**landsraad.arewel.com (CHOM)**

```bash
# Verify SSH access
ssh deploy@landsraad.arewel.com "uname -a"
# Expected: Linux landsraad 6.x.x Debian 13

# Verify resources
ssh deploy@landsraad.arewel.com "free -h && df -h && nproc"
# Expected:
#   - RAM: 4GB minimum (recommended 8GB+)
#   - Disk: 40GB minimum, 30GB free
#   - CPU: 2 cores minimum (recommended 4+)

# Verify network
ssh deploy@landsraad.arewel.com "ip addr show && ping -c 3 8.8.8.8"
# Expected: Public IP 51.77.150.96, internet connectivity

# Verify sudo access
ssh deploy@landsraad.arewel.com "sudo whoami"
# Expected: root
```

#### 2.1.2 DNS Verification

```bash
# Verify DNS records
dig +short mentat.arewel.com
# Expected: 51.254.139.78

dig +short landsraad.arewel.com
# Expected: 51.77.150.96

# Verify reverse DNS (optional but recommended)
dig +short -x 51.254.139.78
dig +short -x 51.77.150.96
```

**DNS Requirements Checklist:**

- [ ] mentat.arewel.com → 51.254.139.78 (A record)
- [ ] landsraad.arewel.com → 51.77.150.96 (A record)
- [ ] DNS propagation complete (check from multiple locations)
- [ ] TTL set appropriately (300s recommended during deployment)

#### 2.1.3 Network Connectivity Verification

```bash
# Test connectivity from landsraad to mentat
ssh deploy@landsraad.arewel.com "nc -zv 51.254.139.78 9090"  # Prometheus
ssh deploy@landsraad.arewel.com "nc -zv 51.254.139.78 3100"  # Loki
ssh deploy@landsraad.arewel.com "nc -zv 51.254.139.78 4318"  # Tempo
ssh deploy@landsraad.arewel.com "nc -zv 51.254.139.78 3000"  # Grafana
ssh deploy@landsraad.arewel.com "nc -zv 51.254.139.78 9093"  # Alertmanager

# Test connectivity from mentat to landsraad
ssh deploy@mentat.arewel.com "nc -zv 51.77.150.96 80"    # HTTP
ssh deploy@mentat.arewel.com "nc -zv 51.77.150.96 443"   # HTTPS
```

**Network Requirements Checklist:**

- [ ] Firewall rules allow bidirectional traffic between servers
- [ ] Observability ports accessible from landsraad to mentat
- [ ] Web ports (80, 443) accessible from internet to landsraad
- [ ] Grafana port (3000) accessible from internet to mentat
- [ ] No NAT/proxy issues affecting connectivity

### 2.2 Software Prerequisites

#### 2.2.1 Control Machine (Your Laptop/Workstation)

```bash
# Verify required tools
command -v git || echo "MISSING: git"
command -v ssh || echo "MISSING: ssh"
command -v scp || echo "MISSING: scp"
command -v yq || echo "MISSING: yq"
command -v jq || echo "MISSING: jq"

# Clone deployment repository
git clone https://github.com/YOUR_ORG/mentat.git /tmp/chom-deploy
cd /tmp/chom-deploy/chom/deploy

# Verify deployment scripts
ls -la deploy-enhanced.sh scripts/setup-observability-vps.sh scripts/setup-vpsmanager-vps.sh
```

#### 2.2.2 SSH Key Setup

```bash
# Generate SSH key pair (if not exists)
if [ ! -f ~/.ssh/chom_deploy_ed25519 ]; then
    ssh-keygen -t ed25519 -f ~/.ssh/chom_deploy_ed25519 -C "chom-deploy@arewel.com" -N ""
fi

# Copy public key to both VPS
ssh-copy-id -i ~/.ssh/chom_deploy_ed25519.pub deploy@mentat.arewel.com
ssh-copy-id -i ~/.ssh/chom_deploy_ed25519.pub deploy@landsraad.arewel.com

# Verify passwordless SSH
ssh -i ~/.ssh/chom_deploy_ed25519 deploy@mentat.arewel.com "echo 'SSH OK'"
ssh -i ~/.ssh/chom_deploy_ed25519 deploy@landsraad.arewel.com "echo 'SSH OK'"

# Add to SSH config for convenience
cat >> ~/.ssh/config << 'EOF'
Host mentat
    HostName mentat.arewel.com
    User deploy
    IdentityFile ~/.ssh/chom_deploy_ed25519

Host landsraad
    HostName landsraad.arewel.com
    User deploy
    IdentityFile ~/.ssh/chom_deploy_ed25519
EOF
```

### 2.3 Configuration Prerequisites

#### 2.3.1 Environment Configuration

Create production environment file:

```bash
# On your control machine
cat > /tmp/chom-deploy/chom/.env.production << 'EOF'
# ============================================================================
# CHOM Production Environment Configuration
# ============================================================================

# Application Settings
APP_NAME="CHOM"
APP_ENV=production
APP_KEY=                         # GENERATE: php artisan key:generate --show
APP_DEBUG=false
APP_URL=https://landsraad.arewel.com

# Localization
APP_LOCALE=en
APP_FALLBACK_LOCALE=en

# Logging Configuration
LOG_CHANNEL=observability
LOG_LEVEL=info

# Database Configuration
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=chom
DB_USERNAME=chom
DB_PASSWORD=                     # GENERATE: openssl rand -base64 32

# Session Configuration
SESSION_DRIVER=redis
SESSION_LIFETIME=120
SESSION_ENCRYPT=true
SESSION_SECURE_COOKIE=true
SESSION_SAME_SITE=strict
SESSION_EXPIRE_ON_CLOSE=true

# Cache & Queue Configuration
CACHE_STORE=redis
QUEUE_CONNECTION=redis

# Redis Configuration
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=                  # GENERATE: openssl rand -base64 32
REDIS_PORT=6379
REDIS_DB=0
REDIS_CACHE_DB=1
REDIS_QUEUE_DB=2
REDIS_SESSION_DB=3

# Observability Stack (mentat.arewel.com)
OBSERVABILITY_ENABLED=true

# Prometheus
PROMETHEUS_ENABLED=true
PROMETHEUS_URL=http://51.254.139.78:9090
PROMETHEUS_NAMESPACE=chom
PROMETHEUS_AUTH_ENABLED=true
PROMETHEUS_AUTH_USERNAME=prometheus
PROMETHEUS_AUTH_PASSWORD=        # GENERATE: openssl rand -base64 32

# Loki
LOKI_ENABLED=true
LOKI_URL=http://51.254.139.78:3100
LOKI_PUSH_ENABLED=false

# Tempo
TEMPO_ENABLED=true
TEMPO_ENDPOINT=http://51.254.139.78:4318
OTEL_SERVICE_NAME=chom
OTEL_EXPORTER_OTLP_ENDPOINT=http://51.254.139.78:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_TRACES_SAMPLER_ARG=0.1

# Grafana
GRAFANA_ENABLED=true
GRAFANA_URL=http://51.254.139.78:3000
GRAFANA_API_KEY=                 # GENERATE in Grafana after deployment

# Alertmanager
ALERTING_ENABLED=true
ALERTMANAGER_URL=http://51.254.139.78:9093

# Request Tracing
REQUEST_TRACING_ENABLED=true
SLOW_REQUEST_THRESHOLD=1000

# Security Settings
CORS_ALLOWED_ORIGINS=https://landsraad.arewel.com

# Sanctum API tokens
SANCTUM_TOKEN_EXPIRATION=60
SANCTUM_TOKEN_ROTATION_ENABLED=true
SANCTUM_STATEFUL_DOMAINS=landsraad.arewel.com

# Two-Factor Authentication
AUTH_2FA_ENABLED=true
AUTH_2FA_REQUIRED_ROLES=owner,admin
AUTH_2FA_GRACE_PERIOD_DAYS=7

# Email Configuration (Brevo)
MAIL_MAILER=smtp
MAIL_HOST=smtp-relay.brevo.com
MAIL_PORT=587
MAIL_USERNAME=                   # Your Brevo SMTP username
MAIL_PASSWORD=                   # Your Brevo SMTP password
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@arewel.com
MAIL_FROM_NAME="${APP_NAME}"

# Stripe (Production Keys)
STRIPE_KEY=                      # pk_live_xxxxx
STRIPE_SECRET=                   # sk_live_xxxxx
STRIPE_WEBHOOK_SECRET=           # whsec_xxxxx

# Development Tools (Disabled in Production)
TELESCOPE_ENABLED=false
DEBUGBAR_ENABLED=false
EOF

# Generate secure passwords and keys
echo "Generating secure credentials..."
cat > /tmp/credentials.txt << EOF
APP_KEY=$(php artisan key:generate --show 2>/dev/null || echo "base64:$(openssl rand -base64 32)")
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
PROMETHEUS_AUTH_PASSWORD=$(openssl rand -base64 32)
EOF

echo "Generated credentials saved to: /tmp/credentials.txt"
echo "IMPORTANT: Save these credentials securely!"
```

#### 2.3.2 Deployment Inventory Configuration

```bash
# Edit deployment inventory
cat > /tmp/chom-deploy/chom/deploy/configs/inventory.yaml << 'EOF'
# CHOM Production Deployment Inventory
version: "1.0"

deployment:
  environment: production
  region: eu-west
  deployment_date: "2026-01-02"
  deployed_by: "deploy@arewel.com"

observability:
  host: mentat.arewel.com
  ip: 51.254.139.78
  ssh_user: deploy
  ssh_port: 22
  domain: mentat.arewel.com
  ssl_email: admin@arewel.com
  components:
    - prometheus
    - grafana
    - loki
    - tempo
    - alertmanager
    - node_exporter

vpsmanager:
  host: landsraad.arewel.com
  ip: 51.77.150.96
  ssh_user: deploy
  ssh_port: 22
  domain: landsraad.arewel.com
  ssl_email: admin@arewel.com
  components:
    - nginx
    - php-fpm
    - mysql
    - redis
    - promtail
    - node_exporter
    - chom_application

network:
  allow_ssh_from: ["0.0.0.0/0"]  # SECURITY: Restrict to specific IPs in production
  allow_http_from: ["0.0.0.0/0"]
  allow_https_from: ["0.0.0.0/0"]
  internal_network:
    - 51.254.139.78/32  # mentat
    - 51.77.150.96/32   # landsraad

monitoring:
  scrape_interval: 15s
  evaluation_interval: 15s
  retention_days: 30
  alert_slack_webhook: ""  # Configure after deployment

backup:
  enabled: true
  retention_days: 30
  backup_window: "03:00-04:00"
  backup_destination: "/var/backups/chom"
EOF
```

### 2.4 SSL Certificate Preparation

#### 2.4.1 Let's Encrypt Setup

```bash
# SSL certificates will be automatically provisioned during deployment
# Verify Let's Encrypt rate limits before proceeding:
# - 50 certificates per registered domain per week
# - 5 duplicate certificates per week

# Pre-check DNS for SSL
dig +short landsraad.arewel.com
# Must return: 51.77.150.96

dig +short mentat.arewel.com
# Must return: 51.254.139.78

# Ensure ports 80 and 443 are accessible (required for ACME challenge)
curl -I http://landsraad.arewel.com
curl -I http://mentat.arewel.com
```

### 2.5 Email Service Verification

#### 2.5.1 Brevo SMTP Test

```bash
# Test Brevo SMTP connectivity
openssl s_client -connect smtp-relay.brevo.com:587 -starttls smtp
# Expected: Connection successful, 250 OK

# Test authentication (requires credentials)
cat > /tmp/test-email.sh << 'EOF'
#!/bin/bash
SMTP_USER="your-brevo-username"
SMTP_PASS="your-brevo-password"
FROM="noreply@arewel.com"
TO="admin@arewel.com"

curl --url 'smtp://smtp-relay.brevo.com:587' \
  --ssl-reqd \
  --mail-from "$FROM" \
  --mail-rcpt "$TO" \
  --user "$SMTP_USER:$SMTP_PASS" \
  --upload-file - << EMAIL
From: $FROM
To: $TO
Subject: CHOM Deployment Test Email

This is a test email to verify Brevo SMTP connectivity.

If you receive this, email is configured correctly.
EMAIL
EOF

chmod +x /tmp/test-email.sh
/tmp/test-email.sh
```

**Email Configuration Checklist:**

- [ ] Brevo account created and verified
- [ ] SMTP credentials generated
- [ ] Sender domain verified (arewel.com)
- [ ] Test email successfully sent and received
- [ ] SPF, DKIM, DMARC records configured (optional but recommended)

### 2.6 Backup Verification

#### 2.6.1 Pre-Deployment Snapshot

```bash
# Create VPS snapshots before deployment (if supported by provider)
# This provides a rollback point in case of critical failure

# Document current state
ssh deploy@mentat.arewel.com "sudo systemctl list-units --type=service --state=running > /tmp/pre-deploy-services.txt"
ssh deploy@landsraad.arewel.com "sudo systemctl list-units --type=service --state=running > /tmp/pre-deploy-services.txt"

# Copy state files to control machine
scp deploy@mentat.arewel.com:/tmp/pre-deploy-services.txt /tmp/mentat-pre-deploy.txt
scp deploy@landsraad.arewel.com:/tmp/pre-deploy-services.txt /tmp/landsraad-pre-deploy.txt
```

### 2.7 Final Pre-Deployment Checklist

**Before proceeding, verify ALL items are complete:**

#### Infrastructure
- [ ] VPS servers provisioned (mentat + landsraad)
- [ ] SSH access configured and verified
- [ ] Sudo users created with proper permissions
- [ ] Required resources available (CPU, RAM, Disk)
- [ ] Network connectivity verified between servers
- [ ] Internet connectivity verified on both servers

#### DNS & Networking
- [ ] DNS A records configured and propagated
- [ ] Reverse DNS configured (optional)
- [ ] Firewall rules configured
- [ ] Ports 80, 443 accessible from internet
- [ ] Observability ports accessible between servers

#### Configuration
- [ ] .env.production file created with all required values
- [ ] inventory.yaml configured with correct IPs and domains
- [ ] Secure credentials generated and saved
- [ ] Deployment scripts downloaded and verified

#### External Services
- [ ] Brevo SMTP account configured and tested
- [ ] SSL certificate requirements verified
- [ ] Backup destination prepared
- [ ] Monitoring alert channels configured (Slack, etc.)

#### Security
- [ ] SSH keys generated and deployed
- [ ] Strong passwords generated for all services
- [ ] 2FA configured for administrative access
- [ ] Security hardening checklist reviewed

#### Team Readiness
- [ ] Deployment team assembled and briefed
- [ ] Communication channels established
- [ ] Escalation procedures documented
- [ ] Rollback plan reviewed and understood
- [ ] Deployment window scheduled and communicated

#### Documentation
- [ ] This runbook reviewed by all team members
- [ ] Troubleshooting guide accessible
- [ ] Contact information for all roles verified
- [ ] Emergency procedures understood

**Deployment Approval:**

- [ ] Infrastructure Lead: _________________ Date: _______
- [ ] Application Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______

**Once all items are checked and approved, proceed to deployment.**

---

## 3. Deployment Steps - Observability Stack

**Deployment Target:** mentat.arewel.com (51.254.139.78)
**Duration:** ~45 minutes
**Downtime:** None (fresh installation)

### 3.1 Pre-Deployment Verification

```bash
# Verify deployment readiness
cd /tmp/chom-deploy/chom/deploy

# Run pre-flight checks
./deploy-enhanced.sh --validate observability

# Expected output:
# ✓ SSH connectivity to mentat.arewel.com
# ✓ Sudo access verified
# ✓ Required ports available
# ✓ Disk space sufficient
# ✓ Memory available
# ✓ Network connectivity
#
# All pre-flight checks passed ✓
```

### 3.2 Automated Deployment

```bash
# Execute observability stack deployment
./deploy-enhanced.sh observability

# The script will:
# 1. Install system dependencies
# 2. Download and install Prometheus
# 3. Download and install Loki
# 4. Download and install Grafana
# 5. Download and install Alertmanager
# 6. Download and install Node Exporter
# 7. Configure Nginx reverse proxy
# 8. Configure SSL with Let's Encrypt
# 9. Configure firewall rules
# 10. Start and enable all services

# Monitor deployment progress
# Expected duration: 30-45 minutes
# Watch for any errors in output
```

### 3.3 Manual Deployment (Alternative)

If automated deployment fails, use manual procedure:

#### 3.3.1 System Preparation

```bash
# SSH to observability server
ssh deploy@mentat.arewel.com

# Update system packages
sudo apt-get update
sudo apt-get upgrade -y

# Install dependencies
sudo apt-get install -y \
    wget \
    curl \
    gnupg \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    nginx \
    ufw \
    fail2ban \
    unattended-upgrades

# Create service user
sudo useradd --no-create-home --shell /bin/false prometheus
sudo useradd --no-create-home --shell /bin/false loki
sudo useradd --no-create-home --shell /bin/false alertmanager

# Create directories
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo mkdir -p /etc/loki /var/lib/loki
sudo mkdir -p /etc/alertmanager /var/lib/alertmanager
```

#### 3.3.2 Prometheus Installation

```bash
# Download Prometheus
cd /tmp
PROMETHEUS_VERSION="3.8.1"
wget https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz

# Extract and install
tar xzf prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz
cd prometheus-${PROMETHEUS_VERSION}.linux-amd64

sudo cp prometheus promtool /usr/local/bin/
sudo cp -r consoles console_libraries /etc/prometheus/

# Create configuration
sudo tee /etc/prometheus/prometheus.yml > /dev/null << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
        labels:
          instance: 'mentat.arewel.com'
          environment: 'production'

  - job_name: 'chom'
    scheme: https
    metrics_path: '/metrics'
    basic_auth:
      username: 'prometheus'
      password: 'YOUR_PROMETHEUS_AUTH_PASSWORD'
    static_configs:
      - targets: ['landsraad.arewel.com']
        labels:
          instance: 'landsraad.arewel.com'
          environment: 'production'
EOF

# Set permissions
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

# Create systemd service
sudo tee /etc/systemd/system/prometheus.service > /dev/null << 'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --storage.tsdb.retention.time=30d

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Prometheus
sudo systemctl daemon-reload
sudo systemctl enable prometheus
sudo systemctl start prometheus

# Verify
sudo systemctl status prometheus
curl http://localhost:9090/-/healthy
```

#### 3.3.3 Loki Installation

```bash
# Download Loki
cd /tmp
LOKI_VERSION="3.6.3"
wget https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip

# Extract and install
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki

# Create configuration
sudo tee /etc/loki/loki-config.yml > /dev/null << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /var/lib/loki/tsdb-index
    cache_location: /var/lib/loki/tsdb-cache

limits_config:
  retention_period: 720h  # 30 days
  ingestion_rate_mb: 16
  ingestion_burst_size_mb: 32
  max_query_length: 721h
EOF

# Set permissions
sudo chown -R loki:loki /etc/loki /var/lib/loki

# Create systemd service
sudo tee /etc/systemd/system/loki.service > /dev/null << 'EOF'
[Unit]
Description=Loki
Wants=network-online.target
After=network-online.target

[Service]
User=loki
Group=loki
Type=simple
ExecStart=/usr/local/bin/loki \
    -config.file=/etc/loki/loki-config.yml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Loki
sudo systemctl daemon-reload
sudo systemctl enable loki
sudo systemctl start loki

# Verify
sudo systemctl status loki
curl http://localhost:3100/ready
```

#### 3.3.4 Grafana Installation

```bash
# Add Grafana APT repository
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null

echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Install Grafana
sudo apt-get update
sudo apt-get install -y grafana

# Configure Grafana
sudo tee /etc/grafana/grafana.ini > /dev/null << 'EOF'
[server]
domain = mentat.arewel.com
root_url = https://mentat.arewel.com
http_port = 3000

[security]
admin_user = admin
admin_password = YOUR_SECURE_PASSWORD  # Change this!
secret_key = YOUR_SECRET_KEY          # Generate with: openssl rand -base64 32

[auth]
disable_login_form = false
disable_signout_menu = false

[auth.anonymous]
enabled = false

[database]
type = sqlite3
path = /var/lib/grafana/grafana.db

[session]
provider = file
provider_config = sessions
cookie_secure = true
cookie_samesite = strict

[log]
mode = file
level = info
EOF

# Start Grafana
sudo systemctl daemon-reload
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Verify
sudo systemctl status grafana-server
curl http://localhost:3000/api/health
```

#### 3.3.5 Alertmanager Installation

```bash
# Download Alertmanager
cd /tmp
ALERTMANAGER_VERSION="0.27.0"
wget https://github.com/prometheus/alertmanager/releases/download/v${ALERTMANAGER_VERSION}/alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz

# Extract and install
tar xzf alertmanager-${ALERTMANAGER_VERSION}.linux-amd64.tar.gz
cd alertmanager-${ALERTMANAGER_VERSION}.linux-amd64

sudo cp alertmanager amtool /usr/local/bin/

# Create configuration
sudo tee /etc/alertmanager/alertmanager.yml > /dev/null << 'EOF'
global:
  resolve_timeout: 5m
  smtp_smarthost: 'smtp-relay.brevo.com:587'
  smtp_from: 'alerts@arewel.com'
  smtp_auth_username: 'YOUR_BREVO_USERNAME'
  smtp_auth_password: 'YOUR_BREVO_PASSWORD'

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'email-notifications'

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'admin@arewel.com'
        headers:
          Subject: '[CHOM Alert] {{ .GroupLabels.alertname }}'

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname', 'cluster', 'service']
EOF

# Set permissions
sudo chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

# Create systemd service
sudo tee /etc/systemd/system/alertmanager.service > /dev/null << 'EOF'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=alertmanager
Group=alertmanager
Type=simple
ExecStart=/usr/local/bin/alertmanager \
    --config.file=/etc/alertmanager/alertmanager.yml \
    --storage.path=/var/lib/alertmanager/

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Alertmanager
sudo systemctl daemon-reload
sudo systemctl enable alertmanager
sudo systemctl start alertmanager

# Verify
sudo systemctl status alertmanager
curl http://localhost:9093/-/healthy
```

#### 3.3.6 Node Exporter Installation

```bash
# Download Node Exporter
cd /tmp
NODE_EXPORTER_VERSION="1.10.2"
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz

# Extract and install
tar xzf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/

# Create service user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Verify
sudo systemctl status node_exporter
curl http://localhost:9100/metrics
```

#### 3.3.7 Nginx Configuration

```bash
# Install Certbot for Let's Encrypt
sudo apt-get install -y certbot python3-certbot-nginx

# Configure Nginx for Grafana
sudo tee /etc/nginx/sites-available/grafana > /dev/null << 'EOF'
server {
    listen 80;
    server_name mentat.arewel.com;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name mentat.arewel.com;

    # SSL certificates (will be added by certbot)
    ssl_certificate /etc/letsencrypt/live/mentat.arewel.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mentat.arewel.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    # Proxy to Grafana
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/grafana /etc/nginx/sites-enabled/

# Test Nginx configuration
sudo nginx -t

# Obtain SSL certificate
sudo certbot --nginx -d mentat.arewel.com --non-interactive --agree-tos --email admin@arewel.com

# Reload Nginx
sudo systemctl reload nginx

# Verify
curl -I https://mentat.arewel.com
```

#### 3.3.8 Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Prometheus (from landsraad only)
sudo ufw allow from 51.77.150.96 to any port 9090 proto tcp

# Allow Loki (from landsraad only)
sudo ufw allow from 51.77.150.96 to any port 3100 proto tcp

# Allow Tempo (from landsraad only)
sudo ufw allow from 51.77.150.96 to any port 4318 proto tcp

# Allow Alertmanager (from landsraad only)
sudo ufw allow from 51.77.150.96 to any port 9093 proto tcp

# Enable firewall
sudo ufw --force enable

# Verify
sudo ufw status verbose
```

### 3.4 Post-Deployment Verification

```bash
# Verify all services are running
ssh deploy@mentat.arewel.com "sudo systemctl status prometheus loki grafana-server alertmanager node_exporter nginx"

# Verify service health endpoints
curl http://51.254.139.78:9090/-/healthy  # Prometheus
curl http://51.254.139.78:3100/ready      # Loki
curl http://51.254.139.78:3000/api/health # Grafana
curl http://51.254.139.78:9093/-/healthy  # Alertmanager
curl http://51.254.139.78:9100/metrics    # Node Exporter

# Verify HTTPS access
curl -I https://mentat.arewel.com

# Check for any errors in logs
ssh deploy@mentat.arewel.com "sudo journalctl -u prometheus -n 50 --no-pager"
ssh deploy@mentat.arewel.com "sudo journalctl -u loki -n 50 --no-pager"
ssh deploy@mentat.arewel.com "sudo journalctl -u grafana-server -n 50 --no-pager"
```

**Observability Stack Deployment Complete! ✓**

Continue to next section: CHOM Application Deployment

---

## 4. Deployment Steps - CHOM Application

**Deployment Target:** landsraad.arewel.com (51.77.150.96)
**Duration:** ~60 minutes
**Downtime:** 5-10 minutes (during cutover)

### 4.1 Pre-Deployment Verification

```bash
# Verify deployment readiness
cd /tmp/chom-deploy/chom/deploy

# Run pre-flight checks
./deploy-enhanced.sh --validate vpsmanager

# Expected output:
# ✓ SSH connectivity to landsraad.arewel.com
# ✓ Sudo access verified
# ✓ Required ports available
# ✓ Disk space sufficient (30GB+ free)
# ✓ Memory available (4GB+ free)
# ✓ Network connectivity to mentat.arewel.com
#
# All pre-flight checks passed ✓
```

### 4.2 Infrastructure Setup

#### 4.2.1 System Preparation

```bash
# SSH to CHOM server
ssh deploy@landsraad.arewel.com

# Update system packages
sudo apt-get update
sudo apt-get upgrade -y

# Install system dependencies
sudo apt-get install -y \
    nginx \
    mysql-server \
    redis-server \
    php8.4-fpm \
    php8.4-cli \
    php8.4-mysql \
    php8.4-redis \
    php8.4-mbstring \
    php8.4-xml \
    php8.4-curl \
    php8.4-zip \
    php8.4-gd \
    php8.4-bcmath \
    php8.4-intl \
    composer \
    git \
    unzip \
    curl \
    wget \
    ufw \
    fail2ban \
    certbot \
    python3-certbot-nginx

# Install Promtail for log shipping
cd /tmp
wget https://github.com/grafana/loki/releases/download/v3.6.3/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail

# Install Node Exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.10.2/node_exporter-1.10.2.linux-amd64.tar.gz
tar xzf node_exporter-1.10.2.linux-amd64.tar.gz
sudo mv node_exporter-1.10.2.linux-amd64/node_exporter /usr/local/bin/
```

#### 4.2.2 MySQL Configuration

```bash
# Secure MySQL installation
sudo mysql_secure_installation << EOF

y
YOUR_MYSQL_ROOT_PASSWORD
YOUR_MYSQL_ROOT_PASSWORD
y
y
y
y
EOF

# Create CHOM database and user
sudo mysql -u root -p << 'EOF'
CREATE DATABASE chom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'chom'@'localhost' IDENTIFIED BY 'YOUR_DB_PASSWORD';
GRANT ALL PRIVILEGES ON chom.* TO 'chom'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF

# Configure MySQL for production
sudo tee -a /etc/mysql/mysql.conf.d/mysqld.cnf > /dev/null << 'EOF'

# CHOM Production Configuration
max_connections = 200
innodb_buffer_pool_size = 1G
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT
query_cache_size = 0
query_cache_type = 0

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 2
log_queries_not_using_indexes = 1
EOF

# Restart MySQL
sudo systemctl restart mysql

# Verify MySQL
sudo systemctl status mysql
mysql -u chom -p -e "SELECT VERSION();"
```

#### 4.2.3 Redis Configuration

```bash
# Configure Redis
sudo tee /etc/redis/redis.conf > /dev/null << 'EOF'
bind 127.0.0.1
port 6379
requirepass YOUR_REDIS_PASSWORD
maxmemory 512mb
maxmemory-policy allkeys-lru

# Persistence
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice
logfile /var/log/redis/redis-server.log

# Security
protected-mode yes
EOF

# Restart Redis
sudo systemctl restart redis-server

# Verify Redis
redis-cli -a YOUR_REDIS_PASSWORD ping
# Expected: PONG
```

#### 4.2.4 PHP-FPM Configuration

```bash
# Configure PHP-FPM pool
sudo tee /etc/php/8.4/fpm/pool.d/chom.conf > /dev/null << 'EOF'
[chom]
user = www-data
group = www-data
listen = /run/php/php8.4-fpm-chom.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500

; PHP configuration
php_admin_value[error_log] = /var/log/php-fpm/chom-error.log
php_admin_flag[log_errors] = on
php_value[session.save_handler] = redis
php_value[session.save_path] = "tcp://127.0.0.1:6379?auth=YOUR_REDIS_PASSWORD"
EOF

# Configure PHP settings
sudo tee /etc/php/8.4/fpm/conf.d/99-chom.ini > /dev/null << 'EOF'
memory_limit = 256M
upload_max_filesize = 64M
post_max_size = 64M
max_execution_time = 300
max_input_time = 300
date.timezone = UTC
opcache.enable = 1
opcache.memory_consumption = 128
opcache.interned_strings_buffer = 8
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 2
opcache.fast_shutdown = 1
EOF

# Create log directory
sudo mkdir -p /var/log/php-fpm
sudo chown www-data:www-data /var/log/php-fpm

# Restart PHP-FPM
sudo systemctl restart php8.4-fpm

# Verify PHP-FPM
sudo systemctl status php8.4-fpm
```

### 4.3 Application Deployment

#### 4.3.1 Application Installation

```bash
# Create application directory
sudo mkdir -p /var/www/chom
sudo chown www-data:www-data /var/www/chom

# Clone repository (as www-data user)
sudo -u www-data git clone https://github.com/YOUR_ORG/mentat.git /tmp/chom-repo
sudo -u www-data cp -r /tmp/chom-repo/chom/* /var/www/chom/
sudo -u www-data rm -rf /tmp/chom-repo

# Set ownership
sudo chown -R www-data:www-data /var/www/chom

# Set permissions
sudo find /var/www/chom -type f -exec chmod 644 {} \;
sudo find /var/www/chom -type d -exec chmod 755 {} \;
sudo chmod -R 775 /var/www/chom/storage /var/www/chom/bootstrap/cache

# Install Composer dependencies
cd /var/www/chom
sudo -u www-data composer install --optimize-autoloader --no-dev

# Copy environment file
sudo -u www-data cp /tmp/chom-deploy/chom/.env.production /var/www/chom/.env

# Generate application key (if not set in .env)
sudo -u www-data php artisan key:generate

# Verify .env configuration
sudo -u www-data php artisan config:show
```

#### 4.3.2 Database Migration

```bash
# Review pending migrations
sudo -u www-data php artisan migrate:status

# Run migrations (PRODUCTION - this is destructive!)
sudo -u www-data php artisan migrate --force

# Verify migrations
sudo -u www-data php artisan migrate:status
# Expected: All migrations shown as "Ran"

# Seed database (if needed)
# WARNING: Only run if this is a fresh installation
# sudo -u www-data php artisan db:seed --force

# Verify database
mysql -u chom -p chom -e "SHOW TABLES;"
```

#### 4.3.3 Cache and Optimization

```bash
# Clear existing caches
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan route:clear
sudo -u www-data php artisan view:clear
sudo -u www-data php artisan cache:clear

# Optimize for production
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
sudo -u www-data php artisan event:cache

# Compile assets (if using Vite)
sudo -u www-data npm install
sudo -u www-data npm run build

# Verify optimization
ls -la /var/www/chom/bootstrap/cache/
# Expected: config.php, routes-v7.php, services.php, events.php
```

### 4.4 Queue Worker Configuration

```bash
# Create queue worker systemd service
sudo tee /etc/systemd/system/chom-queue-worker.service > /dev/null << 'EOF'
[Unit]
Description=CHOM Queue Worker
After=redis-server.service mysql.service
Requires=redis-server.service mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/chom
ExecStart=/usr/bin/php /var/www/chom/artisan queue:work redis --sleep=3 --tries=3 --max-time=3600
Restart=always
RestartSec=5

# Prevent memory leaks
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF

# Create multiple queue workers for different queues
for queue in default emails notifications reports; do
    sudo tee /etc/systemd/system/chom-queue-${queue}.service > /dev/null << EOF
[Unit]
Description=CHOM Queue Worker (${queue})
After=redis-server.service mysql.service
Requires=redis-server.service mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/chom
ExecStart=/usr/bin/php /var/www/chom/artisan queue:work redis --queue=${queue} --sleep=3 --tries=3 --max-time=3600
Restart=always
RestartSec=5

ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGTERM

[Install]
WantedBy=multi-user.target
EOF
done

# Start and enable queue workers
sudo systemctl daemon-reload
sudo systemctl enable chom-queue-worker
sudo systemctl enable chom-queue-default
sudo systemctl enable chom-queue-emails
sudo systemctl enable chom-queue-notifications
sudo systemctl enable chom-queue-reports

sudo systemctl start chom-queue-worker
sudo systemctl start chom-queue-default
sudo systemctl start chom-queue-emails
sudo systemctl start chom-queue-notifications
sudo systemctl start chom-queue-reports

# Verify queue workers
sudo systemctl status chom-queue-worker
sudo systemctl status chom-queue-default
```

### 4.5 Cron Job Setup

```bash
# Create Laravel scheduler cron job
sudo tee /etc/cron.d/chom-scheduler > /dev/null << 'EOF'
* * * * * www-data cd /var/www/chom && php artisan schedule:run >> /dev/null 2>&1
EOF

# Set permissions
sudo chmod 644 /etc/cron.d/chom-scheduler

# Verify cron job
sudo crontab -l -u www-data
# Or check cron directory
cat /etc/cron.d/chom-scheduler

# Test scheduler manually
sudo -u www-data php artisan schedule:run
```

### 4.6 Nginx Configuration

```bash
# Create Nginx server block
sudo tee /etc/nginx/sites-available/chom > /dev/null << 'EOF'
# HTTP server - redirect to HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name landsraad.arewel.com;

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name landsraad.arewel.com;

    root /var/www/chom/public;
    index index.php index.html;

    # SSL certificates (will be added by certbot)
    ssl_certificate /etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/landsraad.arewel.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Logging
    access_log /var/log/nginx/chom-access.log combined;
    error_log /var/log/nginx/chom-error.log warn;

    # Client body size
    client_max_body_size 64M;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml+rss application/json;

    # Root location
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.4-fpm-chom.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
        fastcgi_param PHP_VALUE "upload_max_filesize=64M \n post_max_size=64M";
        fastcgi_read_timeout 300;
    }

    # Deny access to hidden files
    location ~ /\. {
        deny all;
    }

    # Deny access to Laravel sensitive files
    location ~ /(\.env|\.git|storage|vendor|bootstrap/cache) {
        deny all;
    }

    # Prometheus metrics endpoint (basic auth protected)
    location /metrics {
        auth_basic "Prometheus Metrics";
        auth_basic_user_file /etc/nginx/.htpasswd-metrics;

        try_files $uri /index.php?$query_string;
    }

    # Health check endpoints (no auth)
    location ~ ^/health/(ready|live|basic|security|detailed) {
        try_files $uri /index.php?$query_string;
    }

    # Static assets caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Create htpasswd for metrics endpoint
sudo apt-get install -y apache2-utils
sudo htpasswd -bc /etc/nginx/.htpasswd-metrics prometheus YOUR_PROMETHEUS_AUTH_PASSWORD

# Enable site
sudo ln -sf /etc/nginx/sites-available/chom /etc/nginx/sites-enabled/

# Test Nginx configuration
sudo nginx -t

# If test passes, reload Nginx
sudo systemctl reload nginx
```

### 4.7 SSL Certificate Setup

```bash
# Obtain Let's Encrypt SSL certificate
sudo certbot --nginx \
    -d landsraad.arewel.com \
    --non-interactive \
    --agree-tos \
    --email admin@arewel.com \
    --redirect

# Verify SSL certificate
curl -I https://landsraad.arewel.com

# Test SSL configuration
openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com < /dev/null

# Verify auto-renewal
sudo certbot renew --dry-run

# Check renewal timer
sudo systemctl status certbot.timer
```

### 4.8 Promtail Configuration (Log Shipping)

```bash
# Create Promtail user
sudo useradd --no-create-home --shell /bin/false promtail

# Create Promtail configuration
sudo mkdir -p /etc/promtail
sudo tee /etc/promtail/promtail-config.yml > /dev/null << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://51.254.139.78:3100/loki/api/v1/push

scrape_configs:
  # CHOM application logs
  - job_name: chom-app
    static_configs:
      - targets:
          - localhost
        labels:
          job: chom
          environment: production
          host: landsraad.arewel.com
          __path__: /var/www/chom/storage/logs/*.log

  # Nginx access logs
  - job_name: nginx-access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          log_type: access
          environment: production
          host: landsraad.arewel.com
          __path__: /var/log/nginx/chom-access.log

  # Nginx error logs
  - job_name: nginx-error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          log_type: error
          environment: production
          host: landsraad.arewel.com
          __path__: /var/log/nginx/chom-error.log

  # MySQL slow query logs
  - job_name: mysql-slow
    static_configs:
      - targets:
          - localhost
        labels:
          job: mysql
          log_type: slow_query
          environment: production
          host: landsraad.arewel.com
          __path__: /var/log/mysql/slow-query.log

  # PHP-FPM error logs
  - job_name: php-fpm
    static_configs:
      - targets:
          - localhost
        labels:
          job: php-fpm
          environment: production
          host: landsraad.arewel.com
          __path__: /var/log/php-fpm/chom-error.log

  # System logs
  - job_name: syslog
    static_configs:
      - targets:
          - localhost
        labels:
          job: syslog
          environment: production
          host: landsraad.arewel.com
          __path__: /var/log/syslog
EOF

# Create positions directory
sudo mkdir -p /var/lib/promtail
sudo chown promtail:promtail /var/lib/promtail

# Set permissions for log access
sudo usermod -aG adm promtail
sudo usermod -aG www-data promtail

# Create systemd service
sudo tee /etc/systemd/system/promtail.service > /dev/null << 'EOF'
[Unit]
Description=Promtail Log Shipper
Wants=network-online.target
After=network-online.target

[Service]
User=promtail
Group=promtail
Type=simple
ExecStart=/usr/local/bin/promtail \
    -config.file=/etc/promtail/promtail-config.yml

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Promtail
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

# Verify Promtail
sudo systemctl status promtail
curl http://localhost:9080/metrics
```

### 4.9 Node Exporter Configuration

```bash
# Create Node Exporter user
sudo useradd --no-create-home --shell /bin/false node_exporter

# Create systemd service
sudo tee /etc/systemd/system/node_exporter.service > /dev/null << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Verify Node Exporter
sudo systemctl status node_exporter
curl http://localhost:9100/metrics
```

### 4.10 Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS (public access)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow MySQL (localhost only - already bound to 127.0.0.1)
# No firewall rule needed - MySQL not listening on public interface

# Allow Redis (localhost only - already bound to 127.0.0.1)
# No firewall rule needed - Redis not listening on public interface

# Allow Node Exporter (from mentat only)
sudo ufw allow from 51.254.139.78 to any port 9100 proto tcp

# Allow Promtail metrics (from mentat only)
sudo ufw allow from 51.254.139.78 to any port 9080 proto tcp

# Enable firewall
sudo ufw --force enable

# Verify firewall rules
sudo ufw status verbose
```

### 4.11 Application Final Setup

```bash
# Run post-deployment commands
cd /var/www/chom

# Clear all caches again (ensure fresh state)
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan route:clear
sudo -u www-data php artisan view:clear

# Re-cache for production
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
sudo -u www-data php artisan event:cache

# Run storage link (if needed)
sudo -u www-data php artisan storage:link

# Set final permissions
sudo chown -R www-data:www-data /var/www/chom
sudo chmod -R 755 /var/www/chom
sudo chmod -R 775 /var/www/chom/storage /var/www/chom/bootstrap/cache

# Verify application
sudo -u www-data php artisan --version
sudo -u www-data php artisan config:show app
```

**CHOM Application Deployment Complete! ✓**

---

## 5. Post-Deployment Validation

### 5.1 Service Health Checks

#### 5.1.1 Observability Stack Health

```bash
# Check all observability services
ssh deploy@mentat.arewel.com << 'EOF'
echo "=== Service Status ==="
sudo systemctl status prometheus --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status loki --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status grafana-server --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status alertmanager --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status node_exporter --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status nginx --no-pager | grep -E "(Active|Main PID)"

echo ""
echo "=== Health Endpoints ==="
curl -s http://localhost:9090/-/healthy && echo "Prometheus: OK" || echo "Prometheus: FAIL"
curl -s http://localhost:3100/ready && echo "Loki: OK" || echo "Loki: FAIL"
curl -s http://localhost:3000/api/health | jq '.database' && echo "Grafana: OK" || echo "Grafana: FAIL"
curl -s http://localhost:9093/-/healthy && echo "Alertmanager: OK" || echo "Alertmanager: FAIL"
curl -s http://localhost:9100/metrics | head -1 && echo "Node Exporter: OK" || echo "Node Exporter: FAIL"
curl -I https://mentat.arewel.com 2>&1 | grep "HTTP" && echo "HTTPS: OK" || echo "HTTPS: FAIL"
EOF
```

**Expected Results:**
- All services: `Active: active (running)`
- All health endpoints: Return successful responses
- HTTPS: Returns `HTTP/2 200` or `HTTP/2 302`

#### 5.1.2 CHOM Application Health

```bash
# Check all CHOM services
ssh deploy@landsraad.arewel.com << 'EOF'
echo "=== Service Status ==="
sudo systemctl status nginx --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status php8.4-fpm --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status mysql --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status redis-server --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status chom-queue-worker --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status promtail --no-pager | grep -E "(Active|Main PID)"
sudo systemctl status node_exporter --no-pager | grep -E "(Active|Main PID)"

echo ""
echo "=== Health Endpoints ==="
curl -s https://landsraad.arewel.com/health/ready | jq '.status' && echo "Ready: OK" || echo "Ready: FAIL"
curl -s https://landsraad.arewel.com/health/live | jq '.status' && echo "Live: OK" || echo "Live: FAIL"
curl -s https://landsraad.arewel.com/health/basic | jq '.database' && echo "Database: OK" || echo "Database: FAIL"
curl -s http://localhost:9100/metrics | head -1 && echo "Node Exporter: OK" || echo "Node Exporter: FAIL"
curl -s http://localhost:9080/metrics | head -1 && echo "Promtail: OK" || echo "Promtail: FAIL"

echo ""
echo "=== Database Connectivity ==="
mysql -u chom -pYOUR_DB_PASSWORD -e "SELECT 'MySQL OK';" && echo "MySQL: OK" || echo "MySQL: FAIL"

echo ""
echo "=== Redis Connectivity ==="
redis-cli -a YOUR_REDIS_PASSWORD ping && echo "Redis: OK" || echo "Redis: FAIL"

echo ""
echo "=== Queue Workers ==="
ps aux | grep "queue:work" | grep -v grep | wc -l
echo "Queue workers running (expected: 5)"
EOF
```

**Expected Results:**
- All services: `Active: active (running)`
- Health endpoints: Return `"status": "ok"`
- Database: Returns "MySQL OK"
- Redis: Returns "PONG"
- Queue workers: 5 processes running

### 5.2 Smoke Tests

#### 5.2.1 Web Application Smoke Test

```bash
# Test homepage
curl -I https://landsraad.arewel.com
# Expected: HTTP/2 200

# Test login page
curl -s https://landsraad.arewel.com/login | grep -q "csrf" && echo "Login page: OK" || echo "Login page: FAIL"

# Test API health endpoint
curl -s https://landsraad.arewel.com/api/health | jq '.'
# Expected: JSON response with status information

# Test metrics endpoint (with auth)
curl -s -u prometheus:YOUR_PROMETHEUS_AUTH_PASSWORD https://landsraad.arewel.com/metrics | grep -q "chom_" && echo "Metrics: OK" || echo "Metrics: FAIL"

# Test static assets
curl -I https://landsraad.arewel.com/build/manifest.json
# Expected: HTTP/2 200
```

#### 5.2.2 End-to-End Workflow Test

Manual testing required:

1. **User Registration**
   - Navigate to https://landsraad.arewel.com/register
   - Create a test account
   - Verify email sent (check Brevo dashboard)
   - Verify email received and account activated

2. **User Login**
   - Navigate to https://landsraad.arewel.com/login
   - Log in with test account
   - Verify redirect to dashboard
   - Verify session persists across page refreshes

3. **Core Functionality**
   - Create a test organization
   - Create a test site
   - Verify VPS provisioning workflow
   - Check database entries created
   - Verify logs in Loki (Grafana)

4. **Queue Processing**
   - Trigger a background job (e.g., send email)
   - Verify job processed by queue worker
   - Check job status in database
   - Verify job completion

### 5.3 Performance Verification

#### 5.3.1 Response Time Test

```bash
# Test homepage response time
for i in {1..10}; do
    curl -o /dev/null -s -w "Response time: %{time_total}s\n" https://landsraad.arewel.com
done

# Expected: < 1 second per request
```

#### 5.3.2 Load Test (Basic)

```bash
# Install Apache Bench (if not installed)
sudo apt-get install -y apache2-utils

# Run basic load test (100 requests, 10 concurrent)
ab -n 100 -c 10 https://landsraad.arewel.com/

# Expected results:
# - No failed requests
# - Average response time < 1 second
# - Server handles load without errors
```

### 5.4 Security Validation

#### 5.4.1 SSL/TLS Verification

```bash
# Test SSL certificate
echo | openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com 2>/dev/null | openssl x509 -noout -dates

# Test SSL configuration strength
sslscan landsraad.arewel.com

# Check for common SSL issues
testssl.sh landsraad.arewel.com

# Verify HSTS header
curl -I https://landsraad.arewel.com | grep -i strict-transport-security
# Expected: Strict-Transport-Security: max-age=31536000; includeSubDomains
```

#### 5.4.2 Security Headers Verification

```bash
# Check all security headers
curl -I https://landsraad.arewel.com

# Expected headers:
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
# X-Frame-Options: SAMEORIGIN
# X-Content-Type-Options: nosniff
# X-XSS-Protection: 1; mode=block
# Referrer-Policy: strict-origin-when-cross-origin
```

#### 5.4.3 Firewall Verification

```bash
# Verify firewall rules on both servers
ssh deploy@mentat.arewel.com "sudo ufw status verbose"
ssh deploy@landsraad.arewel.com "sudo ufw status verbose"

# Test blocked ports (should fail)
nc -zv landsraad.arewel.com 3306  # MySQL should be blocked
nc -zv landsraad.arewel.com 6379  # Redis should be blocked

# Test allowed ports (should succeed)
nc -zv landsraad.arewel.com 80    # HTTP should be open
nc -zv landsraad.arewel.com 443   # HTTPS should be open
```

### 5.5 Monitoring Validation

#### 5.5.1 Metrics Collection Verification

```bash
# Access Prometheus UI
open https://mentat.arewel.com/prometheus

# Run test queries:
# 1. up{job="chom"}
#    Expected: 1 (target is up)
#
# 2. chom_http_requests_total
#    Expected: Counter incrementing with requests
#
# 3. node_memory_MemAvailable_bytes{instance="landsraad.arewel.com"}
#    Expected: Memory metrics from CHOM server

# Verify targets in Prometheus
curl -s http://51.254.139.78:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Expected output:
# {
#   "job": "chom",
#   "health": "up"
# }
# {
#   "job": "node_exporter",
#   "health": "up"
# }
```

#### 5.5.2 Log Collection Verification

```bash
# Access Grafana
open https://mentat.arewel.com

# Log in with default credentials (change immediately!)
# Username: admin
# Password: YOUR_SECURE_PASSWORD (from configuration)

# Navigate to Explore > Loki
# Run test queries:
# 1. {job="chom"}
#    Expected: Application logs from CHOM
#
# 2. {job="nginx", log_type="access"}
#    Expected: Nginx access logs
#
# 3. {job="mysql", log_type="slow_query"}
#    Expected: MySQL slow query logs (if any)

# Verify log ingestion rate
curl -s http://51.254.139.78:3100/metrics | grep loki_ingester_streams_created_total

# Generate test logs
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan tinker --execute='logger()->info(\"Test log from deployment\");'"

# Wait 30 seconds, then search in Grafana for "Test log from deployment"
```

#### 5.5.3 Alert Configuration Verification

```bash
# Access Alertmanager
curl -s http://51.254.139.78:9093/api/v2/status | jq '.'

# Verify alert rules in Prometheus
curl -s http://51.254.139.78:9090/api/v1/rules | jq '.data.groups[].rules[] | {alert: .name, state: .state}'

# Test alert delivery (optional - will send real alerts!)
# Create test alert in Prometheus
curl -X POST http://51.254.139.78:9093/api/v1/alerts -H "Content-Type: application/json" -d '[
  {
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "Test alert from deployment verification"
    }
  }
]'

# Check email for alert notification
```

### 5.6 Backup Verification

```bash
# Verify backup directories exist
ssh deploy@landsraad.arewel.com "ls -la /var/backups/chom"

# Test database backup
ssh deploy@landsraad.arewel.com << 'EOF'
sudo mysqldump -u chom -pYOUR_DB_PASSWORD chom > /tmp/test-backup.sql
ls -lh /tmp/test-backup.sql
rm /tmp/test-backup.sql
EOF

# Verify automated backup cron job
ssh deploy@landsraad.arewel.com "sudo crontab -l | grep backup"
```

### 5.7 Post-Deployment Checklist

**Verify ALL items before marking deployment as successful:**

#### Services Health
- [ ] Prometheus: Running and healthy
- [ ] Loki: Running and healthy
- [ ] Grafana: Running and accessible
- [ ] Alertmanager: Running and healthy
- [ ] Node Exporter (mentat): Running
- [ ] Node Exporter (landsraad): Running
- [ ] Nginx (both servers): Running
- [ ] PHP-FPM: Running
- [ ] MySQL: Running and accessible
- [ ] Redis: Running and accessible
- [ ] Promtail: Running and shipping logs
- [ ] Queue Workers: All 5 workers running

#### Application Functionality
- [ ] Homepage loads successfully
- [ ] Login page accessible
- [ ] User registration works
- [ ] Email delivery works (Brevo)
- [ ] Database queries executing
- [ ] Cache working (Redis)
- [ ] Queue jobs processing
- [ ] Scheduled tasks configured

#### Monitoring & Observability
- [ ] Prometheus scraping CHOM metrics
- [ ] Loki receiving logs from CHOM
- [ ] Grafana accessible and configured
- [ ] Dashboards visible in Grafana
- [ ] Alerts configured in Alertmanager
- [ ] Test alert delivered successfully

#### Security
- [ ] SSL certificates valid and auto-renewing
- [ ] HTTPS redirect working
- [ ] Security headers present
- [ ] Firewall rules active on both servers
- [ ] SSH key authentication working
- [ ] Fail2ban configured and active
- [ ] Metrics endpoint protected with basic auth
- [ ] Database not accessible from internet
- [ ] Redis not accessible from internet

#### Performance
- [ ] Homepage response time < 1 second
- [ ] API response time acceptable
- [ ] No 500 errors in logs
- [ ] Resource usage within acceptable limits
- [ ] Load test passed (100 requests)

#### Documentation
- [ ] Deployment documented in change log
- [ ] Credentials securely stored
- [ ] Access information shared with team
- [ ] Monitoring alerts configured
- [ ] Runbook updated with actual values

**Final Approval:**

- [ ] Application Engineer: _________________ Date: _______
- [ ] Infrastructure Engineer: _________________ Date: _______
- [ ] Security Engineer: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______

**Deployment Status: [ ] SUCCESS [ ] FAILED [ ] NEEDS REVIEW**

---

## 6. Rollback Procedures

See **ROLLBACK_PROCEDURES.md** for detailed rollback steps.

Quick rollback checklist:

1. **Immediate Actions (< 5 minutes)**
   - Enable maintenance mode
   - Stop queue workers
   - Restore database from backup
   - Revert code to previous version
   - Clear caches
   - Disable maintenance mode

2. **Verification**
   - Test critical functionality
   - Verify database integrity
   - Check error logs

3. **Post-Rollback**
   - Document rollback reason
   - Create incident report
   - Schedule post-mortem

---

## 7. Troubleshooting Guide

See **TROUBLESHOOTING_GUIDE.md** for comprehensive troubleshooting procedures.

Common issues and quick fixes:

### 7.1 Service Won't Start

```bash
# Check service status
sudo systemctl status SERVICE_NAME

# Check logs
sudo journalctl -u SERVICE_NAME -n 100 --no-pager

# Common fixes:
# 1. Permissions issue
sudo chown -R USER:GROUP /path/to/directory

# 2. Port already in use
sudo lsof -i :PORT
sudo kill -9 PID

# 3. Configuration error
sudo SERVICE_NAME -t  # Test configuration
```

### 7.2 Database Connection Failed

```bash
# Verify MySQL is running
sudo systemctl status mysql

# Test connection
mysql -u chom -p -e "SELECT 1;"

# Check credentials in .env
grep DB_ /var/www/chom/.env

# Verify database exists
mysql -u root -p -e "SHOW DATABASES LIKE 'chom';"

# Check MySQL logs
sudo tail -f /var/log/mysql/error.log
```

### 7.3 Queue Jobs Not Processing

```bash
# Check queue workers
sudo systemctl status chom-queue-worker

# Check queue depth in Redis
redis-cli -a YOUR_REDIS_PASSWORD LLEN queues:default

# Restart queue workers
sudo systemctl restart chom-queue-worker

# Check worker logs
sudo journalctl -u chom-queue-worker -f
```

### 7.4 High Memory/CPU Usage

```bash
# Check system resources
top
htop
free -h
df -h

# Check process-specific usage
ps aux --sort=-%mem | head -10
ps aux --sort=-%cpu | head -10

# Restart high-memory services
sudo systemctl restart php8.4-fpm
sudo systemctl restart chom-queue-worker

# Clear application cache
cd /var/www/chom
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan config:cache
```

### 7.5 SSL Certificate Issues

```bash
# Check certificate expiry
openssl x509 -in /etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem -noout -dates

# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Check Nginx configuration
sudo nginx -t
sudo systemctl reload nginx
```

---

## 8. Production Hardening

### 8.1 Security Hardening

See **PRODUCTION_CONFIGURATION.md** for complete security hardening procedures.

**Critical security measures:**

1. **Disable root login via SSH**
   ```bash
   sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
   sudo systemctl restart sshd
   ```

2. **Configure Fail2ban**
   ```bash
   sudo systemctl enable fail2ban
   sudo systemctl start fail2ban
   ```

3. **Enable automatic security updates**
   ```bash
   sudo apt-get install -y unattended-upgrades
   sudo dpkg-reconfigure -plow unattended-upgrades
   ```

4. **Set up audit logging**
   ```bash
   sudo apt-get install -y auditd
   sudo systemctl enable auditd
   sudo systemctl start auditd
   ```

5. **Implement rate limiting**
   - Configure in Nginx
   - Configure in Laravel middleware
   - Monitor with Prometheus

### 8.2 Performance Tuning

1. **PHP-FPM tuning**
   - Adjust `pm.max_children` based on available memory
   - Monitor with `/status` endpoint
   - Set appropriate `php.ini` values

2. **MySQL tuning**
   - Configure `innodb_buffer_pool_size` (70% of available RAM)
   - Enable slow query log
   - Monitor with Prometheus MySQL exporter

3. **Redis tuning**
   - Set `maxmemory` appropriately
   - Configure eviction policy
   - Enable persistence if needed

4. **Nginx tuning**
   - Configure worker processes
   - Set appropriate buffer sizes
   - Enable gzip compression
   - Configure caching headers

### 8.3 Monitoring Setup

1. **Configure Grafana dashboards**
   - Import CHOM dashboard
   - Import Node Exporter dashboard
   - Import MySQL dashboard
   - Create custom dashboards

2. **Set up alerts**
   - High CPU usage (> 80%)
   - High memory usage (> 90%)
   - Disk space low (< 20%)
   - Service down
   - High error rate (> 1%)
   - Slow response time (> 2s)
   - Queue backlog (> 1000 jobs)

3. **Configure log retention**
   - Loki: 30 days
   - Prometheus: 30 days
   - Nginx logs: 30 days (rotate)
   - Application logs: 30 days (rotate)

### 8.4 Backup Configuration

1. **Database backups**
   ```bash
   # Daily automated backup at 3 AM
   sudo tee /etc/cron.d/chom-db-backup > /dev/null << 'EOF'
   0 3 * * * root /usr/local/bin/backup-chom-db.sh
   EOF
   ```

2. **Application backups**
   ```bash
   # Daily application backup at 4 AM
   sudo tee /etc/cron.d/chom-app-backup > /dev/null << 'EOF'
   0 4 * * * root /usr/local/bin/backup-chom-app.sh
   EOF
   ```

3. **Backup verification**
   ```bash
   # Weekly backup restoration test
   sudo tee /etc/cron.d/chom-backup-test > /dev/null << 'EOF'
   0 5 * * 0 root /usr/local/bin/test-chom-backup.sh
   EOF
   ```

---

## 9. Emergency Procedures

### 9.1 Emergency Contacts

| Role | Name | Phone | Email | Availability |
|------|------|-------|-------|--------------|
| On-Call Engineer | TBD | TBD | TBD | 24/7 |
| Backup Engineer | TBD | TBD | TBD | 24/7 |
| Engineering Manager | TBD | TBD | TBD | Business hours |
| CTO | TBD | TBD | TBD | Escalation only |

### 9.2 Incident Response Procedures

1. **Detect and Alert**
   - Monitor alerts in Slack #incidents
   - Check Grafana dashboards
   - Review error logs in Loki

2. **Assess Severity**
   - SEV1 (Critical): Complete outage, data loss
   - SEV2 (High): Major functionality impaired
   - SEV3 (Medium): Minor functionality impaired
   - SEV4 (Low): No user impact

3. **Incident Response**
   - Create incident ticket
   - Notify stakeholders
   - Investigate root cause
   - Implement fix or rollback
   - Verify resolution
   - Post-mortem review

### 9.3 Emergency Rollback

```bash
# EMERGENCY ROLLBACK SCRIPT
# Use only when application is severely broken

# 1. Enable maintenance mode
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan down"

# 2. Stop queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl stop chom-queue-*"

# 3. Restore database (DESTRUCTIVE!)
ssh deploy@landsraad.arewel.com "sudo mysql -u root -p chom < /var/backups/chom/latest-backup.sql"

# 4. Revert code to previous version
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data git checkout PREVIOUS_COMMIT_HASH"

# 5. Clear caches
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan config:clear && sudo -u www-data php artisan cache:clear"

# 6. Start queue workers
ssh deploy@landsraad.arewel.com "sudo systemctl start chom-queue-*"

# 7. Disable maintenance mode
ssh deploy@landsraad.arewel.com "cd /var/www/chom && sudo -u www-data php artisan up"

# 8. Verify
curl -I https://landsraad.arewel.com
```

### 9.4 Data Recovery

In case of data loss:

1. **Identify scope of data loss**
2. **Locate most recent backup**
3. **Estimate recovery time**
4. **Notify stakeholders**
5. **Perform recovery**
6. **Verify data integrity**
7. **Document incident**

---

## 10. Appendix

### 10.1 Configuration Files Reference

| File | Location | Purpose |
|------|----------|---------|
| .env.production | /var/www/chom/.env | Application configuration |
| prometheus.yml | /etc/prometheus/prometheus.yml | Metrics scraping |
| loki-config.yml | /etc/loki/loki-config.yml | Log aggregation |
| grafana.ini | /etc/grafana/grafana.ini | Grafana settings |
| nginx-chom.conf | /etc/nginx/sites-available/chom | Web server config |
| promtail-config.yml | /etc/promtail/promtail-config.yml | Log shipping |

### 10.2 Service Ports Reference

| Service | Port | Protocol | Access |
|---------|------|----------|--------|
| HTTP | 80 | TCP | Public |
| HTTPS | 443 | TCP | Public |
| SSH | 22 | TCP | Restricted |
| MySQL | 3306 | TCP | Localhost only |
| Redis | 6379 | TCP | Localhost only |
| PHP-FPM | 9000 | Unix socket | Localhost only |
| Prometheus | 9090 | TCP | Internal only |
| Grafana | 3000 | TCP | Public (HTTPS) |
| Loki | 3100 | TCP | Internal only |
| Tempo | 4318 | TCP | Internal only |
| Alertmanager | 9093 | TCP | Internal only |
| Node Exporter | 9100 | TCP | Internal only |
| Promtail | 9080 | TCP | Internal only |

### 10.3 Useful Commands Reference

```bash
# Service Management
sudo systemctl status SERVICE_NAME
sudo systemctl start SERVICE_NAME
sudo systemctl stop SERVICE_NAME
sudo systemctl restart SERVICE_NAME
sudo systemctl reload SERVICE_NAME
sudo systemctl enable SERVICE_NAME
sudo systemctl disable SERVICE_NAME

# Log Viewing
sudo journalctl -u SERVICE_NAME -f
sudo journalctl -u SERVICE_NAME -n 100 --no-pager
sudo tail -f /var/log/nginx/chom-access.log
sudo tail -f /var/www/chom/storage/logs/laravel.log

# Laravel Artisan
cd /var/www/chom
sudo -u www-data php artisan cache:clear
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:cache
sudo -u www-data php artisan queue:restart
sudo -u www-data php artisan migrate:status
sudo -u www-data php artisan health:check

# Database
mysql -u chom -p
mysqldump -u chom -p chom > backup.sql
mysql -u chom -p chom < backup.sql

# Redis
redis-cli -a PASSWORD
redis-cli -a PASSWORD MONITOR
redis-cli -a PASSWORD INFO
redis-cli -a PASSWORD LLEN queues:default

# Monitoring
curl https://landsraad.arewel.com/health/ready
curl -u prometheus:PASSWORD https://landsraad.arewel.com/metrics
curl http://51.254.139.78:9090/-/healthy

# Network
sudo ufw status verbose
sudo netstat -tulpn
sudo ss -tulpn
sudo iptables -L -n -v

# Disk Usage
df -h
du -sh /var/www/chom/*
du -sh /var/lib/mysql
du -sh /var/log/*

# Process Monitoring
top
htop
ps aux | grep php-fpm
ps aux | grep queue:work
ps aux | grep nginx
```

### 10.4 Log Locations Reference

| Component | Log Location |
|-----------|--------------|
| Nginx Access | /var/log/nginx/chom-access.log |
| Nginx Error | /var/log/nginx/chom-error.log |
| PHP-FPM | /var/log/php-fpm/chom-error.log |
| Laravel | /var/www/chom/storage/logs/laravel.log |
| MySQL Error | /var/log/mysql/error.log |
| MySQL Slow Query | /var/log/mysql/slow-query.log |
| Redis | /var/log/redis/redis-server.log |
| Prometheus | journalctl -u prometheus |
| Loki | journalctl -u loki |
| Grafana | journalctl -u grafana-server |
| Queue Workers | journalctl -u chom-queue-worker |
| Promtail | journalctl -u promtail |
| System | /var/log/syslog |
| Auth | /var/log/auth.log |

### 10.5 Backup Locations Reference

| Backup Type | Location | Retention |
|-------------|----------|-----------|
| Database | /var/backups/chom/db/ | 30 days |
| Application | /var/backups/chom/app/ | 30 days |
| Configuration | /var/backups/chom/config/ | 30 days |
| Nginx Config | /var/backups/chom/nginx/ | 30 days |

---

## Document Control

**Document Information:**
- **Version:** 1.0.0
- **Created:** 2026-01-02
- **Last Updated:** 2026-01-02
- **Next Review:** 2026-02-02

**Change Log:**
| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2026-01-02 | DevOps Team | Initial production runbook |

**Approval:**
- [ ] Infrastructure Lead: _________________ Date: _______
- [ ] Application Lead: _________________ Date: _______
- [ ] Security Lead: _________________ Date: _______
- [ ] Operations Manager: _________________ Date: _______

---

**END OF PRODUCTION DEPLOYMENT RUNBOOK**
