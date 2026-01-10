# CHOM Test Environment Setup

This document describes the test environment configuration for the CHOM (Cloud Hosting & Observability Manager) homelab project.

## Overview

The test environment consists of:

1. **Vagrant VMs** - Local two-server setup mimicking production
2. **GitHub Actions CI/CD** - Automated testing and deployment pipeline
3. **Test User Setup** - Scripts for creating test users and data

## Vagrant Test Environment

### Architecture

The Vagrant configuration creates two VMs that mirror the production infrastructure:

**Mentat VM** (Observability Server)
- IP: 192.168.56.10
- RAM: 2GB
- CPU: 1 core
- Services: Prometheus, Grafana, Loki, Promtail, AlertManager, Node Exporter

**Landsraad VM** (Application Server)
- IP: 192.168.56.11
- RAM: 4GB
- CPU: 2 cores
- Services: Laravel, Nginx, PostgreSQL 15, Redis, PHP 8.2-FPM, Node Exporter

### Prerequisites

- [VirtualBox](https://www.virtualbox.org/) 7.0+
- [Vagrant](https://www.vagrantup.com/) 2.3+
- Minimum 8GB RAM on host machine
- Minimum 20GB free disk space

### Quick Start

1. **Start the VMs**:
   ```bash
   vagrant up
   ```

   This will:
   - Download Debian 12 base box
   - Create both VMs (mentat + landsraad)
   - Install all dependencies
   - Configure services
   - Set up networking

2. **Access the Application Server**:
   ```bash
   vagrant ssh landsraad
   ```

3. **Set up CHOM Application**:
   ```bash
   cd /vagrant
   cp .env.example .env.vagrant

   # Edit .env.vagrant with test database credentials
   # DB_DATABASE=chom_test
   # DB_USERNAME=chom_user
   # DB_PASSWORD=chom_password

   composer install
   npm install
   php artisan key:generate
   php artisan migrate --seed
   npm run build
   ```

4. **Start Development Server**:
   ```bash
   php artisan serve --host=0.0.0.0 --port=8000
   ```

5. **Access Application**:
   - Application: http://localhost:8080
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000 (admin/admin)
   - Loki: http://localhost:3100
   - AlertManager: http://localhost:9093

### Vagrant Commands

```bash
# Start all VMs
vagrant up

# Start specific VM
vagrant up mentat
vagrant up landsraad

# SSH into VM
vagrant ssh mentat
vagrant ssh landsraad

# Check VM status
vagrant status

# Suspend VMs (save state)
vagrant suspend

# Resume VMs
vagrant resume

# Restart VMs
vagrant reload

# Reprovision (re-run setup scripts)
vagrant provision

# Destroy VMs (delete everything)
vagrant destroy
vagrant destroy -f  # Force without confirmation
```

### Shared Folders

The project directory is automatically mounted at `/vagrant` in both VMs, allowing you to edit files on your host machine and see changes immediately in the VMs.

### Network Configuration

- **Private Network**: VMs can communicate with each other on 192.168.56.0/24
- **Port Forwarding**: Key services are forwarded to localhost
- **DNS**: VMs use host DNS resolver for internet access

### Testing in Vagrant

```bash
# SSH into landsraad
vagrant ssh landsraad

# Run all tests
cd /vagrant
php artisan test

# Run specific tests
php artisan test --filter=BackupTenantIsolation

# Run with coverage
php artisan test --coverage

# Run VPSManager tests
cd /vagrant/deploy/vpsmanager/tests
./run-all-tests.sh
```

### Troubleshooting Vagrant

**VMs won't start**:
```bash
# Check VirtualBox is running
VBoxManage --version

# Check Vagrant version
vagrant --version

# Try provisioning again
vagrant provision
```

**Network issues**:
```bash
# Reload VMs
vagrant reload

# Check host-only network in VirtualBox
VBoxManage list hostonlyifs
```

**Performance issues**:
```bash
# Increase VM resources in Vagrantfile
# Edit memory and CPU settings, then:
vagrant reload
```

**Port conflicts**:
```bash
# Check what's using the port
lsof -i :9090  # On macOS/Linux
netstat -ano | findstr :9090  # On Windows

# Change port in Vagrantfile if needed
```

---

## GitHub Actions CI/CD Pipeline

The GitHub Actions pipeline automates testing and deployment workflows.

### Pipeline Configuration

Located at `.github/workflows/ci.yml`

### Workflow Triggers

- **Push** to `main` or `develop` branches
- **Pull Requests** to `main` branch
- **Manual** workflow dispatch

### Pipeline Stages

1. **Lint & Code Quality**
   - Run Laravel Pint (code formatter)
   - Check code standards
   - Validate syntax

2. **Unit & Feature Tests**
   - Set up PHP 8.2
   - Install Composer dependencies
   - Run PHPUnit tests
   - Generate coverage report

3. **Multi-Tenancy Tests**
   - Run isolation test suite
   - Validate tenant filtering
   - Check cross-tenant access prevention

4. **Security Scan**
   - Run security audit
   - Check for vulnerabilities
   - Validate authentication/authorization

5. **Build Assets**
   - Set up Node.js 20
   - Install npm dependencies
   - Build frontend assets with Vite

6. **Deployment Tests**
   - Validate deployment scripts
   - Run idempotence tests
   - Check VPSManager functionality

### Environment Secrets

Required GitHub Secrets for CI/CD:

```
STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
DB_PASSWORD=...
CHOM_SSH_KEY=...
```

Set these in: Repository Settings → Secrets and variables → Actions

### Running Locally

Simulate CI/CD locally using [act](https://github.com/nektos/act):

```bash
# Install act
brew install act  # macOS
# or download from https://github.com/nektos/act/releases

# Run all workflows
act

# Run specific job
act -j test

# Run specific event
act pull_request
```

### Pipeline Artifacts

The pipeline generates artifacts that can be downloaded:

- Test coverage reports (HTML)
- Security scan results (JSON/MD)
- Build logs
- Deployment validation reports

Access artifacts: Actions → Workflow run → Artifacts section

---

## Test User Setup

### Automated Test User Creation

Use the `scripts/create-test-users.sh` script to create test users and organizations:

```bash
cd /vagrant
./scripts/create-test-users.sh
```

This creates:

1. **Super Admin User**
   - Email: admin@chom.test
   - Password: password
   - Role: Super Admin

2. **Organization Owner (Starter Plan)**
   - Email: starter@chom.test
   - Password: password
   - Organization: Starter Org
   - Plan: Starter ($29/mo)

3. **Organization Owner (Pro Plan)**
   - Email: pro@chom.test
   - Password: password
   - Organization: Pro Org
   - Plan: Pro ($79/mo)

4. **Organization Owner (Enterprise Plan)**
   - Email: enterprise@chom.test
   - Password: password
   - Organization: Enterprise Org
   - Plan: Enterprise ($249/mo)

5. **Team Members**
   - Email: member@chom.test (Member role)
   - Email: viewer@chom.test (Viewer role)

### Manual Test User Creation

```bash
# SSH into landsraad
vagrant ssh landsraad
cd /vagrant

# Create super admin
php artisan tinker
>>> $user = User::create([
...   'name' => 'Test Admin',
...   'email' => 'admin@test.local',
...   'password' => Hash::make('password'),
...   'is_super_admin' => true,
...   'email_verified_at' => now(),
... ]);

# Create organization
>>> $org = Organization::create([
...   'name' => 'Test Organization',
...   'is_approved' => true,
... ]);

# Create tenant (billing unit)
>>> $tenant = Tenant::create([
...   'organization_id' => $org->id,
...   'name' => 'Test Tenant',
...   'is_approved' => true,
... ]);

# Attach user to organization
>>> $org->users()->attach($user->id, ['role' => 'owner']);
```

### Seeding Test Data

```bash
# Run all seeders
php artisan db:seed

# Run specific seeder
php artisan db:seed --class=TestUserSeeder
php artisan db:seed --class=SiteSeeder
php artisan db:seed --class=BackupSeeder
```

### Test Stripe Subscriptions

For testing Stripe integration without real payments:

```bash
# Use Stripe test mode
STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...

# Test cards (never charge)
# Success: 4242 4242 4242 4242
# Decline: 4000 0000 0000 0002
# Requires authentication: 4000 0025 0000 3155
```

### Test Data Cleanup

```bash
# Reset database and re-seed
php artisan migrate:fresh --seed

# Clear all data but keep schema
php artisan db:wipe

# Delete specific test users
php artisan tinker
>>> User::where('email', 'LIKE', '%@chom.test')->delete();
```

---

## Testing Workflows

### Local Development Workflow

```bash
# 1. Start Vagrant VMs
vagrant up

# 2. SSH into landsraad
vagrant ssh landsraad

# 3. Install dependencies
cd /vagrant
composer install
npm install

# 4. Set up environment
cp .env.example .env.vagrant
php artisan key:generate

# 5. Set up database
php artisan migrate --seed

# 6. Create test users
./scripts/create-test-users.sh

# 7. Build frontend
npm run dev

# 8. Start server
php artisan serve --host=0.0.0.0

# 9. Run tests
php artisan test
```

### Testing Observability Stack

```bash
# 1. SSH into mentat
vagrant ssh mentat

# 2. Check service status
sudo systemctl status prometheus
sudo systemctl status grafana-server
sudo systemctl status loki

# 3. Test Prometheus
curl http://localhost:9090/-/healthy

# 4. Test Grafana
curl http://localhost:3000/api/health

# 5. Test Loki
curl http://localhost:3100/ready
```

### Testing Multi-Tenancy

```bash
# Run isolation tests
php artisan test --filter=BackupTenantIsolation

# Manual testing
php artisan tinker
>>> $tenant1 = Tenant::first();
>>> $tenant2 = Tenant::skip(1)->first();
>>> $backup = SiteBackup::where('tenant_id', $tenant1->id)->first();
>>> # Try to access from tenant2 context - should fail
```

### Testing Deployment

```bash
# Test deployment script locally
cd deploy
./deploy-chom-automated.sh --dry-run

# Test VPSManager
cd vpsmanager/tests
./run-all-tests.sh

# Test idempotence
./test-idempotence.sh
```

---

## Environment Variables for Testing

Create a `.env.testing` file for test-specific configuration:

```bash
APP_NAME=CHOM_Test
APP_ENV=testing
APP_KEY=base64:...
APP_DEBUG=true
APP_URL=http://localhost:8080

DB_CONNECTION=sqlite
DB_DATABASE=:memory:

CACHE_DRIVER=array
QUEUE_CONNECTION=sync
SESSION_DRIVER=array

MAIL_MAILER=log

STRIPE_KEY=pk_test_...
STRIPE_SECRET=sk_test_...
```

---

## Performance Testing

### Load Testing with Apache Bench

```bash
# Install Apache Bench
apt-get install -y apache2-utils

# Test login endpoint
ab -n 1000 -c 10 http://localhost:8080/login

# Test API endpoint
ab -n 1000 -c 10 -H "Authorization: Bearer TOKEN" http://localhost:8080/api/v1/sites
```

### Database Query Profiling

```bash
# Enable query logging
php artisan tinker
>>> DB::enableQueryLog();
>>> # Run your code
>>> dd(DB::getQueryLog());
```

---

## Continuous Integration Best Practices

1. **Run tests locally** before pushing
2. **Keep CI fast** - parallelize tests when possible
3. **Use caching** for dependencies (Composer, npm)
4. **Monitor CI failures** - set up notifications
5. **Keep secrets secure** - never commit credentials
6. **Document CI requirements** in this file
7. **Update CI when adding dependencies**

---

## Troubleshooting

### Common Issues

**Tests fail in CI but pass locally**:
- Check environment differences (.env.testing vs .env)
- Verify database state (migrations, seeders)
- Check for timezone issues

**Vagrant provisioning fails**:
- Check internet connection
- Verify VirtualBox installation
- Try `vagrant destroy && vagrant up`

**Can't access forwarded ports**:
- Check firewall settings
- Verify services are running inside VM
- Check for port conflicts on host

**Database connection errors**:
- Verify PostgreSQL is running: `systemctl status postgresql`
- Check credentials in .env
- Verify database exists: `psql -l`

---

## Additional Resources

- [Vagrant Documentation](https://www.vagrantup.com/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Laravel Testing](https://laravel.com/docs/12.x/testing)
- [PHPUnit Documentation](https://phpunit.de/documentation.html)

---

**Last Updated**: 2025-01-10
**Version**: 1.0.0
