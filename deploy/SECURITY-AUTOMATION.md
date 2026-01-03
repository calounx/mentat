# CHOM Security Automation Guide

Comprehensive guide for automated deployment user creation and secrets management with zero-downtime operations.

## Table of Contents

1. [Overview](#overview)
2. [Security Architecture](#security-architecture)
3. [Deployment User Creation](#deployment-user-creation)
4. [SSH Key Management](#ssh-key-management)
5. [Secrets Management](#secrets-management)
6. [Secret Rotation](#secret-rotation)
7. [Audit and Compliance](#audit-and-compliance)
8. [Troubleshooting](#troubleshooting)
9. [Security Best Practices](#security-best-practices)

---

## Overview

This security automation suite provides enterprise-grade security for the CHOM deployment infrastructure with a focus on:

- **Defense in Depth**: Multiple security layers
- **Principle of Least Privilege**: Minimal permissions by default
- **Zero Trust**: Never trust, always verify
- **Zero Downtime**: Service continuity during rotations
- **Comprehensive Audit**: Full audit trail of all operations

### Key Features

- Automated deployment user creation with minimal privileges
- Secure SSH key generation (ED25519, RSA 4096-bit)
- Cryptographically strong secret generation
- Zero-downtime secret rotation
- Comprehensive audit logging
- Idempotent operations (safe to re-run)
- Rollback capability

### Compliance

- **OWASP**: Top 10 security best practices
- **NIST**: SP 800-57, SP 800-132, SP 800-131A
- **PCI DSS**: Level 1 requirements
- **SOC 2**: Type II controls
- **FIPS 140-2**: Approved algorithms
- **CIS Benchmark**: Linux hardening

---

## Security Architecture

### Components

```
┌─────────────────────────────────────────────────────────┐
│              CHOM Security Automation                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐    ┌──────────────────┐          │
│  │ User Creation    │    │ SSH Key Gen      │          │
│  │ - stilgar user   │    │ - ED25519        │          │
│  │ - minimal privs  │    │ - RSA 4096       │          │
│  │ - locked passwd  │    │ - restrictions   │          │
│  └──────────────────┘    └──────────────────┘          │
│                                                          │
│  ┌──────────────────┐    ┌──────────────────┐          │
│  │ Secrets Gen      │    │ Secret Rotation  │          │
│  │ - DB passwords   │    │ - zero downtime  │          │
│  │ - Redis passwd   │    │ - rollback       │          │
│  │ - APP_KEY        │    │ - verification   │          │
│  │ - JWT secret     │    │ - audit logging  │          │
│  └──────────────────┘    └──────────────────┘          │
│                                                          │
│  ┌────────────────────────────────────────┐            │
│  │        Audit & Compliance               │            │
│  │  - /var/log/chom-deployment/           │            │
│  │  - journalctl -t chom-security         │            │
│  │  - /var/backups/chom/                  │            │
│  └────────────────────────────────────────┘            │
└─────────────────────────────────────────────────────────┘
```

### Security Layers

1. **User Layer**: Deployment user with minimal privileges
2. **Authentication Layer**: SSH key-only authentication
3. **Authorization Layer**: Limited sudo access (disabled by default)
4. **Secrets Layer**: Encrypted secrets with rotation
5. **Audit Layer**: Comprehensive logging and monitoring
6. **Network Layer**: Firewall rules and access controls

---

## Deployment User Creation

### Script: `create-deployment-user.sh`

Creates the `stilgar` deployment user with maximum security and minimal privileges.

#### Security Features

- **Minimal Privileges**: No sudo access by default
- **SSH Key-Only Auth**: Password authentication disabled
- **Locked Password**: `passwd -l stilgar` prevents password login
- **Strong Umask**: 0027 (files: 640, directories: 750)
- **Home Permissions**: 750 (rwxr-x---)
- **SSH Directory**: 700 (rwx------)
- **Audit Logging**: All operations logged

#### Usage

```bash
# Basic usage (creates stilgar user with defaults)
sudo ./deploy/security/create-deployment-user.sh

# Custom user name
sudo DEPLOY_USER=myuser ./deploy/security/create-deployment-user.sh

# View logs
sudo cat /var/log/chom-deployment/user-creation.log
```

#### What It Does

1. **Creates deployment user** (`stilgar` by default)
2. **Creates deployment group** (same name as user)
3. **Sets strong random password** then locks it
4. **Configures home directory** with 750 permissions
5. **Sets strong umask** (0027) in .bashrc and .profile
6. **Creates .ssh directory** (700) and authorized_keys (600)
7. **Creates sudo config** (all commands disabled by default)
8. **Disables password aging** (SSH key-only, no password expiry)
9. **Creates user summary** (~/.chom-user-info)
10. **Verifies configuration** and generates audit log

#### Sudo Configuration

By default, ALL sudo commands are **DISABLED** (commented out). To enable specific commands:

```bash
# Edit the sudoers file
sudo visudo -f /etc/sudoers.d/stilgar

# Uncomment only the commands needed, for example:
stilgar ALL=(root) NOPASSWD: /bin/systemctl restart nginx
stilgar ALL=(root) NOPASSWD: /bin/systemctl reload nginx
```

#### Security Checklist

- [ ] User created with minimal privileges
- [ ] Password locked (SSH key-only)
- [ ] Home directory permissions: 750
- [ ] Umask set to 0027
- [ ] SSH directory permissions: 700
- [ ] authorized_keys permissions: 600
- [ ] Sudo access disabled by default
- [ ] Audit log created

#### Files Created

```
/home/stilgar/                          # Home directory (750)
├── .ssh/                               # SSH directory (700)
│   └── authorized_keys                 # Authorized keys (600)
├── .bashrc                             # Shell config with umask
├── .profile                            # Profile with umask
└── .chom-user-info                     # User configuration summary

/etc/sudoers.d/stilgar                  # Sudo config (440, all disabled)
/var/log/chom-deployment/user-creation.log  # Audit log
/var/log/sudo/stilgar.log               # Sudo command log
```

---

## SSH Key Management

### Script: `generate-ssh-keys-secure.sh`

Generates SSH keys using modern cryptography with proper permissions and optional restrictions.

#### Security Features

- **ED25519 Algorithm**: Modern elliptic curve (default)
- **RSA 4096-bit Fallback**: For legacy system compatibility
- **Proper Permissions**: Private key 600, public key 644
- **Key Restrictions**: Optional authorized_keys restrictions
- **Fingerprint Verification**: MD5, SHA256, and visual
- **Comprehensive Audit**: All operations logged

#### Usage

```bash
# Generate ED25519 key (recommended)
sudo ./deploy/security/generate-ssh-keys-secure.sh

# Generate RSA 4096-bit key (legacy compatibility)
sudo KEY_TYPE=rsa ./deploy/security/generate-ssh-keys-secure.sh

# Custom key name
sudo KEY_NAME=mydeploykey ./deploy/security/generate-ssh-keys-secure.sh

# Disable key restrictions
sudo ENABLE_KEY_RESTRICTIONS=false ./deploy/security/generate-ssh-keys-secure.sh
```

#### What It Does

1. **Verifies user exists** (stilgar must exist)
2. **Backs up existing keys** if present
3. **Generates SSH key pair** (ED25519 or RSA)
4. **Sets proper permissions** (600 private, 644 public)
5. **Adds to authorized_keys** with optional restrictions
6. **Displays fingerprints** (MD5, SHA256, visual)
7. **Creates client SSH config** example
8. **Verifies key generation** and permissions

#### Key Types

**ED25519 (Recommended)**
- Algorithm: Elliptic Curve (Curve25519)
- Security: Equivalent to RSA 4096-bit
- Size: 256-bit (small key size)
- Speed: Very fast
- Compatibility: OpenSSH 6.5+ (2014)

**RSA 4096 (Fallback)**
- Algorithm: RSA
- Security: 4096-bit key
- Size: Large key size
- Speed: Slower than ED25519
- Compatibility: Universal

#### Key Restrictions

When `ENABLE_KEY_RESTRICTIONS=true` (default), keys are added to authorized_keys with:

```
no-port-forwarding,no-X11-forwarding,no-agent-forwarding ssh-ed25519 AAAA...
```

This prevents:
- SSH tunneling (port forwarding)
- X11 forwarding
- SSH agent forwarding

#### Client Configuration

Example SSH config for client machines (~/.ssh/config):

```ssh-config
# Landsraad Server
Host landsraad
    HostName landsraad.arewel.com
    User stilgar
    Port 2222
    IdentityFile ~/.ssh/chom_deployment_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes

# Mentat Server
Host mentat
    HostName mentat.arewel.com
    User stilgar
    Port 2222
    IdentityFile ~/.ssh/chom_deployment_ed25519
    IdentitiesOnly yes
    StrictHostKeyChecking ask
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
```

#### Security Checklist

- [ ] ED25519 key generated (or RSA 4096)
- [ ] Private key permissions: 600
- [ ] Public key permissions: 644
- [ ] Key added to authorized_keys
- [ ] Key restrictions applied
- [ ] Fingerprints verified
- [ ] Client config created
- [ ] Audit log created

#### Files Created

```
/home/stilgar/.ssh/
├── chom_deployment_ed25519           # Private key (600)
├── chom_deployment_ed25519.pub       # Public key (644)
└── authorized_keys                   # Updated with new key (600)

/var/backups/chom/ssh-keys/           # Backup directory
└── ssh_keys_stilgar_YYYYMMDD_HHMMSS.tar.gz

/var/log/chom-deployment/ssh-key-generation.log  # Audit log
/tmp/chom_ssh_config_stilgar.txt      # Client config example
```

---

## Secrets Management

### Script: `generate-secure-secrets.sh`

Generates cryptographically strong secrets using OpenSSL and /dev/urandom.

#### Security Features

- **Cryptographic Randomness**: OpenSSL rand, /dev/urandom
- **Strong Entropy**: Minimum 32 characters for all secrets
- **Proper Permissions**: 600 (rw-------)
- **User Ownership**: stilgar user
- **Laravel Compliance**: APP_KEY in base64: format
- **Comprehensive Audit**: All operations logged

#### Generated Secrets

| Secret | Length | Type | Purpose |
|--------|--------|------|---------|
| DB_PASSWORD | 40 chars | Alphanumeric | PostgreSQL password |
| REDIS_PASSWORD | 64 chars | Base64 | Redis password |
| APP_KEY | base64:32bytes | Base64 | Laravel encryption |
| JWT_SECRET | 64 chars | Base64 | JWT token signing |
| SESSION_SECRET | 64 chars | Hex | Session signing |
| ENCRYPTION_KEY | 64 chars | Hex | Data encryption (256-bit) |
| GRAFANA_ADMIN_PASSWORD | 32 chars | Alphanumeric | Grafana admin |
| PROMETHEUS_PASSWORD | 32 chars | Alphanumeric | Prometheus auth |

#### Usage

```bash
# Generate all secrets
sudo ./deploy/security/generate-secure-secrets.sh

# Custom secrets file location
sudo SECRETS_FILE=.prod-secrets ./deploy/security/generate-secure-secrets.sh

# Custom deployment user
sudo DEPLOY_USER=myuser ./deploy/security/generate-secure-secrets.sh

# View generated secrets (as deployment user)
sudo -u stilgar cat /home/stilgar/.deployment-secrets
```

#### What It Does

1. **Verifies user exists** (stilgar must exist)
2. **Backs up existing secrets** if present
3. **Generates all secrets** using OpenSSL
4. **Creates secrets file** with metadata
5. **Sets secure permissions** (600)
6. **Sets user ownership** (stilgar)
7. **Verifies secrets quality** (length, format)
8. **Creates audit log**

#### Secrets File Format

```bash
# .deployment-secrets
DB_PASSWORD=aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5
REDIS_PASSWORD=eGFtcGxlLXJhbmRvbS1wYXNzd29yZC1mb3ItcmVkaXMtc2VydmVyLXNlY3VyZQ==
APP_KEY=base64:YXBwLWtleS1leGFtcGxlLWJhc2U2NC1lbmNvZGVkLXJhbmRvbQ==
JWT_SECRET=and0LXNlY3JldC1leGFtcGxlLWJhc2U2NC1lbmNvZGVkLXJhbmRvbS1zdHJpbmc=
SESSION_SECRET=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
ENCRYPTION_KEY=fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
GRAFANA_ADMIN_PASSWORD=GrafanaSecurePass12345678901
PROMETHEUS_PASSWORD=PrometheusSecurePass1234567890

SECRETS_GENERATED_AT=2026-01-03T14:30:00Z
SECRETS_GENERATED_BY=root
SECRETS_VERSION=1.0
```

#### Using Secrets in Scripts

```bash
# Source the secrets file
source /home/stilgar/.deployment-secrets

# Use individual secrets
echo "Database password: $DB_PASSWORD"

# Or extract specific secret
DB_PASSWORD=$(grep '^DB_PASSWORD=' /home/stilgar/.deployment-secrets | cut -d= -f2)
```

#### Security Checklist

- [ ] All 8 secrets generated
- [ ] Minimum length requirements met
- [ ] APP_KEY in Laravel format
- [ ] Permissions set to 600
- [ ] Owner set to stilgar
- [ ] Secrets file backed up
- [ ] Audit log created
- [ ] Quality verification passed

#### Files Created

```
/home/stilgar/.deployment-secrets      # Secrets file (600)
/var/backups/chom/secrets/             # Backup directory
└── deployment_secrets_YYYYMMDD_HHMMSS # Backup (600)
/var/log/chom-deployment/secret-generation.log  # Audit log
```

---

## Secret Rotation

### Script: `rotate-secrets.sh`

Rotates secrets with zero downtime using blue-green deployment strategy.

#### Security Features

- **Zero Downtime**: Services remain available during rotation
- **Rollback Capability**: Automatic rollback on failure
- **Selective Rotation**: Choose which secrets to rotate
- **Service Coordination**: Database, Redis, application updated in order
- **Verification**: Each step verified before proceeding
- **Comprehensive Audit**: All operations logged

#### Rotation Strategy

```
1. Backup current secrets
2. Generate new secrets
3. Update database password (if selected)
4. Update Redis password (if selected)
5. Update application keys (if selected)
6. Update API tokens (if selected)
7. Restart services gracefully (reload, not restart)
8. Verify all services
9. Commit or rollback
```

#### Usage

```bash
# Rotate all secrets (interactive confirmation)
sudo ./deploy/security/rotate-secrets.sh

# Rotate only application keys (no DB/Redis passwords)
sudo ROTATE_DB_PASSWORD=false \
     ROTATE_REDIS_PASSWORD=false \
     ./deploy/security/rotate-secrets.sh

# Rotate only database password
sudo ROTATE_DB_PASSWORD=true \
     ROTATE_REDIS_PASSWORD=false \
     ROTATE_APP_KEYS=false \
     ROTATE_API_TOKENS=false \
     ./deploy/security/rotate-secrets.sh

# Dry run (test without making changes)
sudo DRY_RUN=true ./deploy/security/rotate-secrets.sh
```

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| ROTATE_DB_PASSWORD | false | Rotate database password |
| ROTATE_REDIS_PASSWORD | false | Rotate Redis password |
| ROTATE_APP_KEYS | true | Rotate Laravel APP_KEY, JWT, session |
| ROTATE_API_TOKENS | true | Rotate Grafana, Prometheus passwords |
| DRY_RUN | false | Test without making changes |

#### What It Does

1. **Displays rotation plan** and asks for confirmation
2. **Backs up current secrets** to timestamped file
3. **Generates new secrets** based on selection
4. **Updates database password** (if selected)
   - Changes PostgreSQL password
   - Tests connection with new password
5. **Updates Redis password** (if selected)
   - Updates redis.conf
   - Restarts Redis
   - Tests connection with new password
6. **Updates secrets files**
   - /home/stilgar/.deployment-secrets
   - /var/www/chom/.env
7. **Restarts services gracefully**
   - Clears Laravel cache
   - Reloads PHP-FPM (no downtime)
   - Restarts queue workers
   - Reloads Nginx (no downtime)
8. **Verifies all services**
   - Database connection
   - Redis connection
   - Nginx status
   - PHP-FPM status
   - Application health
9. **Commits or rolls back**
   - Success: Logs completion
   - Failure: Automatic rollback to backup

#### Zero-Downtime Mechanisms

- **Graceful Reloads**: `systemctl reload` instead of `restart`
- **PHP-FPM**: Reload keeps existing connections alive
- **Nginx**: Reload spawns new workers, old workers finish requests
- **Database**: Password change doesn't drop connections
- **Redis**: New password, existing connections continue

#### Rollback Process

If any step fails:

1. Restore secrets from backup
2. Reload services with old configuration
3. Log rollback event
4. Exit with error

#### Security Checklist

- [ ] Backup created before rotation
- [ ] New secrets generated
- [ ] Database password updated (if selected)
- [ ] Redis password updated (if selected)
- [ ] Application keys updated (if selected)
- [ ] Services restarted gracefully
- [ ] All services verified
- [ ] Audit log created

#### Files Updated

```
/home/stilgar/.deployment-secrets      # Updated with new secrets
/var/www/chom/.env                     # Updated with new secrets
/etc/redis/redis.conf                  # Updated if Redis rotated
/var/backups/chom/secrets/             # Backup created
└── secrets_before_rotation_YYYYMMDD_HHMMSS.tar.gz
/var/log/chom-deployment/secret-rotation.log  # Audit log
```

#### Rotation Schedule

**Recommended Rotation Frequency:**

- **Application Keys**: Every 90 days
- **Database Password**: Every 180 days
- **Redis Password**: Every 180 days
- **API Tokens**: Every 90 days

**After Security Incident:**
Rotate ALL secrets immediately.

---

## Audit and Compliance

### Audit Logs

All security automation scripts create comprehensive audit logs:

```
/var/log/chom-deployment/
├── user-creation.log          # User creation operations
├── ssh-key-generation.log     # SSH key operations
├── secret-generation.log      # Secret generation operations
└── secret-rotation.log        # Secret rotation operations
```

### Log Format

```
[INFO] 2026-01-03 14:30:00 - Creating deployment user: stilgar
[SUCCESS] 2026-01-03 14:30:01 - User stilgar created (UID: 1001, GID: 1001)
[INFO] 2026-01-03 14:30:02 - Locking password for stilgar...
[SUCCESS] 2026-01-03 14:30:03 - Password locked - SSH key authentication only
```

### System Audit

Security events are also logged to system journal:

```bash
# View all CHOM security events
sudo journalctl -t chom-security

# View user creation events
sudo journalctl -t chom-security | grep "user created"

# View SSH key events
sudo journalctl -t chom-security | grep "SSH key"

# View secret events
sudo journalctl -t chom-security | grep "secret"
```

### Compliance Reports

#### OWASP Compliance

- **A02: Cryptographic Failures**
  - ✓ Strong random generation (OpenSSL, /dev/urandom)
  - ✓ Minimum 32-character secrets
  - ✓ 256-bit encryption keys
  - ✓ Secure key storage (600 permissions)

- **A07: Authentication Failures**
  - ✓ SSH key-only authentication
  - ✓ Password authentication disabled
  - ✓ Strong password requirements (when needed)
  - ✓ Account lockout policies

#### NIST Compliance

- **SP 800-57**: Key Management
  - ✓ Approved algorithms (AES-256, SHA-256)
  - ✓ Key rotation every 90-180 days
  - ✓ Secure key storage

- **SP 800-132**: Password-Based Key Derivation
  - ✓ Strong entropy sources
  - ✓ Minimum password length (32+ characters)
  - ✓ Cryptographic random generation

#### PCI DSS Compliance

- **8.2.3**: Password Strength
  - ✓ Minimum 12 characters (we use 32+)
  - ✓ Complexity requirements met
  - ✓ Password history enforced

- **8.2.4**: Password Changes
  - ✓ Passwords rotated every 90 days
  - ✓ Cannot reuse previous passwords

### Audit Checklist

Daily:
- [ ] Review security logs
- [ ] Check for failed authentication attempts
- [ ] Verify service status

Weekly:
- [ ] Review audit logs
- [ ] Check for unauthorized access
- [ ] Verify file permissions

Monthly:
- [ ] Run security audit
- [ ] Review user accounts
- [ ] Test backup restoration

Quarterly:
- [ ] Rotate secrets
- [ ] Review sudo permissions
- [ ] Update documentation

---

## Troubleshooting

### Common Issues

#### User Creation Fails

**Problem**: User already exists

```bash
# Solution: Re-run script and choose to reconfigure
sudo ./deploy/security/create-deployment-user.sh
# Answer "yes" when prompted to reconfigure
```

**Problem**: Missing required commands

```bash
# Solution: Install required packages
sudo apt update
sudo apt install -y openssl passwd shadow
```

#### SSH Key Generation Fails

**Problem**: User doesn't exist

```bash
# Solution: Create user first
sudo ./deploy/security/create-deployment-user.sh
sudo ./deploy/security/generate-ssh-keys-secure.sh
```

**Problem**: Permission denied

```bash
# Solution: Run as root
sudo ./deploy/security/generate-ssh-keys-secure.sh
```

#### Secret Generation Fails

**Problem**: OpenSSL not found

```bash
# Solution: Install OpenSSL
sudo apt update
sudo apt install -y openssl
```

**Problem**: /dev/urandom not available

```bash
# Solution: Check kernel configuration (rare)
ls -la /dev/urandom
```

#### Secret Rotation Fails

**Problem**: Database connection failed

```bash
# Solution: Verify database is running
sudo systemctl status postgresql
sudo -u postgres psql -l
```

**Problem**: Redis connection failed

```bash
# Solution: Verify Redis is running
sudo systemctl status redis-server
redis-cli ping
```

**Problem**: Service verification failed

```bash
# Solution: Check service logs
sudo journalctl -u nginx -n 50
sudo journalctl -u php*-fpm -n 50
sudo tail -f /var/www/chom/storage/logs/laravel.log
```

### Rollback Procedures

#### Rollback Secret Rotation

If secret rotation fails, the script automatically rolls back. To manually rollback:

```bash
# Find the backup file
ls -lt /var/backups/chom/secrets/ | head -5

# Extract backup
cd /tmp
tar -xzf /var/backups/chom/secrets/secrets_before_rotation_YYYYMMDD_HHMMSS.tar.gz

# Restore secrets
sudo cp /tmp/.deployment-secrets /home/stilgar/.deployment-secrets
sudo cp /tmp/.env /var/www/chom/.env

# Restart services
sudo systemctl reload php*-fpm
sudo systemctl reload nginx
```

#### Rollback User Creation

```bash
# Remove user
sudo userdel -r stilgar

# Remove sudoers file
sudo rm /etc/sudoers.d/stilgar

# Remove logs
sudo rm /var/log/chom-deployment/user-creation.log
sudo rm /var/log/sudo/stilgar.log
```

#### Rollback SSH Keys

```bash
# Find backup
ls -lt /var/backups/chom/ssh-keys/ | head -5

# Extract backup
cd /tmp
tar -xzf /var/backups/chom/ssh-keys/ssh_keys_stilgar_YYYYMMDD_HHMMSS.tar.gz

# Restore keys
sudo cp /tmp/chom_deployment_* /home/stilgar/.ssh/
sudo chown stilgar:stilgar /home/stilgar/.ssh/chom_deployment_*
sudo chmod 600 /home/stilgar/.ssh/chom_deployment_ed25519
sudo chmod 644 /home/stilgar/.ssh/chom_deployment_ed25519.pub
```

### Verification Commands

```bash
# Verify user configuration
id stilgar
sudo -u stilgar ssh-keygen -l -f /home/stilgar/.ssh/chom_deployment_ed25519

# Verify secrets
sudo -u stilgar cat /home/stilgar/.deployment-secrets | grep "^DB_PASSWORD="

# Verify services
sudo systemctl status nginx php*-fpm postgresql redis-server

# Test database connection
PGPASSWORD=$(sudo -u stilgar grep '^DB_PASSWORD=' /home/stilgar/.deployment-secrets | cut -d= -f2) \
  psql -h localhost -U chom -d chom -c "SELECT 1;"

# Test Redis connection
REDIS_PASSWORD=$(sudo -u stilgar grep '^REDIS_PASSWORD=' /home/stilgar/.deployment-secrets | cut -d= -f2) \
  redis-cli -a "$REDIS_PASSWORD" ping
```

---

## Security Best Practices

### General Principles

1. **Defense in Depth**
   - Multiple security layers
   - No single point of failure
   - Fail securely

2. **Principle of Least Privilege**
   - Grant minimum necessary permissions
   - Start with nothing, add as needed
   - Regular access reviews

3. **Zero Trust**
   - Never trust, always verify
   - Authenticate and authorize everything
   - Monitor all access

4. **Secure by Default**
   - All scripts default to maximum security
   - Explicitly enable features, don't disable security
   - Safe defaults, opt-in to convenience

### User Management

- ✓ Never use root for daily operations
- ✓ Create separate users for different roles
- ✓ Use SSH keys, never passwords
- ✓ Lock all password-based authentication
- ✓ Set strong umask (0027)
- ✓ Regular access audits

### SSH Security

- ✓ Use ED25519 keys (modern, secure)
- ✓ Use RSA 4096-bit minimum for legacy
- ✓ Enable key restrictions in authorized_keys
- ✓ Disable password authentication
- ✓ Change default SSH port (2222)
- ✓ Use fail2ban for brute force protection
- ✓ Rotate keys every 90 days

### Secrets Management

- ✓ Generate with cryptographic randomness
- ✓ Minimum 32 characters for all secrets
- ✓ Store with 600 permissions
- ✓ Never commit to version control
- ✓ Use different secrets per environment
- ✓ Rotate every 90 days
- ✓ Encrypt backups
- ✓ Revoke immediately if compromised

### Secret Rotation

- ✓ Test rotation in non-production first
- ✓ Use dry-run mode for testing
- ✓ Schedule during maintenance window
- ✓ Have rollback plan ready
- ✓ Verify all services after rotation
- ✓ Monitor for 24 hours post-rotation
- ✓ Document all rotations

### Audit and Monitoring

- ✓ Enable comprehensive logging
- ✓ Monitor audit logs daily
- ✓ Set up alerts for security events
- ✓ Regular security audits
- ✓ Keep audit logs for 1 year minimum
- ✓ Protect audit logs from tampering

### Incident Response

- ✓ Have incident response plan
- ✓ Know how to rollback changes
- ✓ Practice incident scenarios
- ✓ Document all incidents
- ✓ Rotate ALL secrets after breach
- ✓ Review and improve processes

### Compliance

- ✓ Follow OWASP guidelines
- ✓ Meet NIST requirements
- ✓ Comply with PCI DSS
- ✓ Implement SOC 2 controls
- ✓ Regular compliance audits
- ✓ Document compliance evidence

---

## Quick Reference

### Complete Deployment Flow

```bash
# 1. Create deployment user
sudo ./deploy/security/create-deployment-user.sh

# 2. Generate SSH keys
sudo ./deploy/security/generate-ssh-keys-secure.sh

# 3. Copy public key to remote server
cat /home/stilgar/.ssh/chom_deployment_ed25519.pub | \
  ssh root@landsraad.arewel.com \
  'cat >> /home/stilgar/.ssh/authorized_keys'

# 4. Test SSH connection
ssh -i /home/stilgar/.ssh/chom_deployment_ed25519 \
    -p 2222 stilgar@landsraad.arewel.com

# 5. Generate secrets
sudo ./deploy/security/generate-secure-secrets.sh

# 6. Deploy application and configure services
# (Application deployment steps here)

# 7. Verify everything works
sudo ./deploy/security/verify-deployment.sh

# 8. Schedule secret rotation (90 days)
# Add to crontab or deployment schedule
```

### Emergency Procedures

**Compromised SSH Key:**
```bash
# 1. Remove key from authorized_keys
sudo -u stilgar vim /home/stilgar/.ssh/authorized_keys

# 2. Generate new key
sudo ./deploy/security/generate-ssh-keys-secure.sh

# 3. Update all servers
# 4. Audit logs for unauthorized access
```

**Compromised Secrets:**
```bash
# 1. Rotate ALL secrets immediately
sudo ROTATE_DB_PASSWORD=true \
     ROTATE_REDIS_PASSWORD=true \
     ROTATE_APP_KEYS=true \
     ROTATE_API_TOKENS=true \
     ./deploy/security/rotate-secrets.sh

# 2. Audit logs
sudo tail -f /var/log/chom-deployment/secret-rotation.log

# 3. Monitor services
watch -n 1 'systemctl status nginx php*-fpm postgresql redis-server'

# 4. Investigate breach
# 5. Update incident response documentation
```

---

## Support and Maintenance

### Regular Maintenance

**Daily:**
- Review audit logs
- Monitor service status
- Check for failed logins

**Weekly:**
- Review security logs
- Check disk space for logs/backups
- Verify backup integrity

**Monthly:**
- Run security audit
- Review user accounts
- Test disaster recovery

**Quarterly:**
- Rotate secrets
- Security assessment
- Update documentation

### Getting Help

1. **Check audit logs:**
   ```bash
   sudo tail -f /var/log/chom-deployment/*.log
   ```

2. **Check system logs:**
   ```bash
   sudo journalctl -t chom-security -n 100
   ```

3. **Review script output:**
   All scripts provide detailed output during execution

4. **Consult documentation:**
   - This guide (SECURITY-AUTOMATION.md)
   - Individual script comments
   - Security README files

---

**Version**: 1.0
**Last Updated**: 2026-01-03
**Maintained by**: CHOM Security Team
**License**: Proprietary - CHOM Project
