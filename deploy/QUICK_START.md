# CHOM Deployment Quick Start Guide

Get the CHOM application deployed in production in under 30 minutes.

## Prerequisites

- Two Debian 13 servers (mentat and landsraad)
- Root or sudo access to both servers
- Domain name pointing to landsraad server
- Git repository access

## Step 1: Initial Server Setup (10 minutes)

### On Mentat (Observability Server)

```bash
# SSH as root
ssh root@mentat.arewel.com

# Download deployment scripts
git clone <REPO_URL> /opt/chom-deployment
cd /opt/chom-deployment/deploy

# Run preparation script
./scripts/prepare-mentat.sh

# Setup firewall
./scripts/setup-firewall.sh --server mentat

# Setup SSH keys for stilgar user
su - stilgar
./scripts/setup-ssh-keys.sh --user stilgar
```

### On Landsraad (Application Server)

```bash
# SSH as root
ssh root@landsraad.arewel.com

# Download deployment scripts
git clone <REPO_URL> /opt/chom-deployment
cd /opt/chom-deployment/deploy

# Run preparation script
./scripts/prepare-landsraad.sh

# Setup firewall
./scripts/setup-firewall.sh --server landsraad

# Setup SSL certificate
./scripts/setup-ssl.sh --domain chom.arewel.com --email admin@example.com

# Setup SSH keys for stilgar user
su - stilgar
./scripts/setup-ssh-keys.sh --user stilgar
```

## Step 2: SSH Key Exchange (2 minutes)

### From Mentat to Landsraad

```bash
# On mentat as stilgar
ssh stilgar@mentat.arewel.com
./scripts/setup-ssh-keys.sh --user stilgar --target-host landsraad.arewel.com

# Test connection
ssh stilgar@landsraad.arewel.com "hostname"
```

## Step 3: Deploy Configuration Files (5 minutes)

### On Landsraad

```bash
ssh root@landsraad.arewel.com

# Copy Nginx configuration
cp /opt/chom-deployment/deploy/config/landsraad/nginx.conf /etc/nginx/sites-available/chom
ln -s /etc/nginx/sites-available/chom /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Copy PHP-FPM configuration
cp /opt/chom-deployment/deploy/config/landsraad/php-fpm.conf /etc/php/8.2/fpm/pool.d/chom.conf
systemctl restart php8.2-fpm

# Copy PostgreSQL tuning
mkdir -p /etc/postgresql/15/main/conf.d
cp /opt/chom-deployment/deploy/config/landsraad/postgresql.conf /etc/postgresql/15/main/conf.d/chom-tuning.conf
systemctl restart postgresql

# Copy Redis configuration (optional - append to existing)
# cat /opt/chom-deployment/deploy/config/landsraad/redis.conf >> /etc/redis/redis.conf
# systemctl restart redis-server

# Copy Supervisor configuration
cp /opt/chom-deployment/deploy/config/landsraad/supervisor.conf /etc/supervisor/conf.d/chom-worker.conf
supervisorctl reread
supervisorctl update
```

### On Mentat

```bash
ssh root@mentat.arewel.com

# Copy deployment scripts to stilgar's home
mkdir -p /home/stilgar/deploy
cp -r /opt/chom-deployment/deploy/* /home/stilgar/deploy/
chown -R stilgar:stilgar /home/stilgar/deploy
```

## Step 4: Configure Application Environment (3 minutes)

### On Landsraad

```bash
ssh root@landsraad.arewel.com

# Create shared directory
mkdir -p /var/www/chom/shared
chown stilgar:www-data /var/www/chom/shared

# Create .env file from template
cp /opt/chom-deployment/deploy/config/landsraad/.env.production.template /var/www/chom/shared/.env

# Edit with actual values
nano /var/www/chom/shared/.env

# Required values to set:
# - APP_KEY (generate with: php artisan key:generate)
# - DB_PASSWORD (use password from prepare-landsraad.sh output)
# - OPENAI_API_KEY
# - JWT_SECRET
# - VPS provider API tokens

# Secure the file
chown stilgar:www-data /var/www/chom/shared/.env
chmod 640 /var/www/chom/shared/.env

# Copy deployment scripts to application directory
mkdir -p /var/www/chom/deploy
cp -r /opt/chom-deployment/deploy/* /var/www/chom/deploy/
chown -R stilgar:www-data /var/www/chom/deploy
```

## Step 5: Deploy Observability Stack (5 minutes)

### On Mentat

```bash
ssh stilgar@mentat.arewel.com
cd /home/stilgar/deploy

# Deploy observability stack
./scripts/deploy-observability.sh

# Verify deployment
docker compose -f /opt/observability/docker-compose.yml ps

# Access Grafana: http://mentat.arewel.com:3000
# Default credentials: admin / admin (change on first login)
```

## Step 6: First Application Deployment (5 minutes)

### On Mentat

```bash
ssh stilgar@mentat.arewel.com
cd /home/stilgar/deploy

# Set environment variables
export REPO_URL="https://github.com/your-org/chom.git"
export GITHUB_TOKEN="your_github_token"  # For private repos

# Optional: Configure notifications
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."
export EMAIL_RECIPIENTS="ops@example.com"

# Run deployment
./deploy-chom.sh --environment=production --branch=main

# Expected output:
# - Pre-deployment backup created
# - Repository cloned
# - Dependencies installed
# - Assets built
# - Migrations run
# - Health checks passed
# - Deployment successful
```

## Step 7: Verify Deployment (2 minutes)

### Test Application

```bash
# Test HTTP endpoint
curl -I https://chom.arewel.com

# Should return: HTTP/2 200

# Test health endpoint
curl https://chom.arewel.com/health

# Check application version
ssh stilgar@landsraad.arewel.com "cd /var/www/chom/current && php artisan --version"
```

### Check Services

```bash
# On landsraad
ssh stilgar@landsraad.arewel.com "sudo systemctl status nginx php8.2-fpm postgresql redis-server | grep Active"

# Check queue workers
ssh stilgar@landsraad.arewel.com "sudo supervisorctl status chom:*"
```

### Access Monitoring

- Grafana: http://mentat.arewel.com:3000 (admin/admin)
- Prometheus: http://mentat.arewel.com:9090
- AlertManager: http://mentat.arewel.com:9093

## Troubleshooting

### Deployment Failed

```bash
# Check logs
ssh stilgar@mentat.arewel.com
tail -100 /var/log/chom-deploy/deployment-*.log

# Rollback if needed
ssh stilgar@landsraad.arewel.com "/var/www/chom/deploy/scripts/rollback.sh"
```

### Services Not Running

```bash
# Restart all services
ssh root@landsraad.arewel.com "systemctl restart nginx php8.2-fpm postgresql redis-server"

# Check logs
journalctl -u nginx -n 50
journalctl -u php8.2-fpm -n 50
```

### SSL Certificate Issues

```bash
# Check certificate status
ssh root@landsraad.arewel.com "certbot certificates"

# Renew if needed
ssh root@landsraad.arewel.com "certbot renew"
```

### Permission Issues

```bash
# Fix application permissions
ssh root@landsraad.arewel.com "chown -R stilgar:www-data /var/www/chom && chmod -R 755 /var/www/chom && chmod -R 775 /var/www/chom/shared/storage"
```

## Post-Deployment Checklist

- [ ] Application accessible via HTTPS
- [ ] Health check endpoint returns 200
- [ ] Queue workers running
- [ ] Logs being written (no errors)
- [ ] Monitoring dashboards showing metrics
- [ ] SSL certificate valid
- [ ] Database migrations completed
- [ ] Backup created successfully
- [ ] Email notifications working (if configured)
- [ ] All services running

## Next Steps

1. **Configure Grafana Dashboards**
   - Import Laravel dashboard
   - Set up alerting rules
   - Create custom dashboards

2. **Set Up Automated Backups**
   - Configure cron job for daily backups
   - Set up off-site backup storage

3. **Configure Monitoring Alerts**
   - Edit `/opt/observability/config/alertmanager.yml`
   - Set up email/Slack notifications
   - Define alert thresholds

4. **Security Hardening**
   - Change default Grafana password
   - Review firewall rules
   - Enable two-factor authentication (if available)
   - Configure fail2ban rules

5. **Documentation**
   - Document custom configurations
   - Create team runbook
   - Set up on-call schedule

## Regular Maintenance

### Daily
- Check monitoring dashboards for anomalies
- Review error logs

### Weekly
- Review deployment logs
- Check disk space usage
- Verify backups are running

### Monthly
- Update system packages
- Rotate old releases and backups
- Review and optimize database
- Security patches

## Support

For detailed documentation, see:
- [README.md](README.md) - Complete deployment documentation
- [RUNBOOK.md](RUNBOOK.md) - Operational procedures
- Deployment logs: `/var/log/chom-deploy/`

## Summary

You now have:
- CHOM application running on landsraad.arewel.com
- Observability stack on mentat.arewel.com
- Zero-downtime deployment system
- Automatic backups and rollback capability
- Comprehensive monitoring and logging
- Production-ready infrastructure

Total setup time: ~30 minutes
