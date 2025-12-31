# CHOM Update and Upgrade Guide

This guide covers updating an existing CHOM deployment to a newer version.

## Update vs. Fresh Deployment

**Choose Update when:**
- You have an existing CHOM deployment
- Services are running and you want to upgrade
- You want to preserve data and configuration

**Choose Fresh Deployment when:**
- First-time installation
- Major version changes
- Complete infrastructure rebuild

## Pre-Update Checklist

Before updating, complete these steps:

### 1. Backup Current State

```bash
# On Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP

# Backup Prometheus data
sudo systemctl stop prometheus
sudo tar -czf ~/prometheus-backup-$(date +%Y%m%d).tar.gz /var/lib/prometheus
sudo systemctl start prometheus

# Backup Grafana
sudo systemctl stop grafana-server
sudo tar -czf ~/grafana-backup-$(date +%Y%m%d).tar.gz /var/lib/grafana /etc/grafana
sudo systemctl start grafana-server

# Copy backups to your control machine
exit
scp deploy@YOUR_OBSERVABILITY_IP:~/*-backup-*.tar.gz ./backups/
```

```bash
# On VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP

# Backup Laravel application and database
cd /var/www/vpsmanager
php artisan down  # Put in maintenance mode

# Backup database
sudo mysqldump -u vpsmanager -p vpsmanager > ~/vpsmanager-db-backup-$(date +%Y%m%d).sql

# Backup application files
sudo tar -czf ~/vpsmanager-app-backup-$(date +%Y%m%d).tar.gz /var/www/vpsmanager

php artisan up  # Take out of maintenance mode

# Copy backup to control machine
exit
scp deploy@YOUR_VPSMANAGER_IP:~/*-backup-*.tar.gz ./backups/
```

### 2. Document Current State

```bash
# Record current versions
ssh deploy@YOUR_OBSERVABILITY_IP "prometheus --version; grafana-server -v"
ssh deploy@YOUR_VPSMANAGER_IP "nginx -v; php --version; mysql --version"

# Take snapshots of configurations
ssh deploy@YOUR_OBSERVABILITY_IP "sudo tar -czf ~/config-backup.tar.gz /etc/prometheus /etc/grafana /etc/loki"
```

### 3. Check Deployment Script Version

```bash
cd /path/to/mentat/chom/deploy
./deploy-enhanced.sh --version

# Update repository to get latest version
git pull origin master
```

### 4. Review Changelog

Check for breaking changes:
- Review commit history
- Check for configuration changes
- Note any manual migration steps

## Update Procedures

### Option 1: In-Place Update (Recommended)

This updates components without full re-deployment.

#### Update Deployment Scripts

```bash
cd /path/to/mentat/chom/deploy
git pull origin master
```

#### Update Observability Stack

```bash
# Deploy only observability (idempotent - safe to re-run)
./deploy-enhanced.sh observability

# The script will:
# - Update to latest versions
# - Preserve existing data
# - Update configurations
# - Restart services
```

#### Update VPSManager Stack

```bash
# Put Laravel in maintenance mode first
ssh deploy@YOUR_VPSMANAGER_IP 'cd /var/www/vpsmanager && php artisan down'

# Deploy VPSManager
./deploy-enhanced.sh vpsmanager

# Run any new migrations
ssh deploy@YOUR_VPSMANAGER_IP 'cd /var/www/vpsmanager && php artisan migrate'

# Clear caches
ssh deploy@YOUR_VPSMANAGER_IP 'cd /var/www/vpsmanager && php artisan cache:clear && php artisan config:clear && php artisan view:clear'

# Take out of maintenance mode
ssh deploy@YOUR_VPSMANAGER_IP 'cd /var/www/vpsmanager && php artisan up'
```

### Option 2: Blue-Green Update

For zero-downtime updates, deploy to new VPS servers and switch.

#### Step 1: Provision New VPS Servers

- Provision 2 new VPS with Debian 13
- Set up sudo users (see SUDO-USER-SETUP.md)

#### Step 2: Update inventory.yaml

```yaml
# Keep old servers for rollback
observability_old:
  ip: "OLD_OBS_IP"
  # ...

# Add new servers
observability:
  ip: "NEW_OBS_IP"
  ssh_user: "deploy"
  ssh_port: 22
  hostname: "monitoring-new.example.com"

vpsmanager:
  ip: "NEW_VPS_IP"
  ssh_user: "deploy"
  ssh_port: 22
  hostname: "manager-new.example.com"
```

#### Step 3: Deploy to New Servers

```bash
# Validate new setup
./deploy-enhanced.sh --validate

# Deploy to new servers
./deploy-enhanced.sh all
```

#### Step 4: Migrate Data

```bash
# Restore Prometheus data
scp ./backups/prometheus-backup-*.tar.gz deploy@NEW_OBS_IP:~/
ssh deploy@NEW_OBS_IP 'sudo systemctl stop prometheus && sudo tar -xzf ~/prometheus-backup-*.tar.gz -C / && sudo systemctl start prometheus'

# Restore Grafana
scp ./backups/grafana-backup-*.tar.gz deploy@NEW_OBS_IP:~/
ssh deploy@NEW_OBS_IP 'sudo systemctl stop grafana-server && sudo tar -xzf ~/grafana-backup-*.tar.gz -C / && sudo systemctl start grafana-server'

# Restore database
scp ./backups/vpsmanager-db-backup-*.sql deploy@NEW_VPS_IP:~/
ssh deploy@NEW_VPS_IP 'mysql -u vpsmanager -p vpsmanager < ~/vpsmanager-db-backup-*.sql'

# Restore application files (if needed)
scp ./backups/vpsmanager-app-backup-*.tar.gz deploy@NEW_VPS_IP:~/
```

#### Step 5: Update DNS

Point your domain to new IP addresses.

#### Step 6: Verify

Test all functionality on new servers.

#### Step 7: Decommission Old Servers

After confirming everything works:
- Keep old servers for 7 days as rollback option
- Then destroy old VPS to save costs

### Option 3: Component-by-Component Update

Update individual components without touching others.

#### Update Prometheus Only

```bash
ssh deploy@YOUR_OBSERVABILITY_IP

# Stop Prometheus
sudo systemctl stop prometheus

# Backup current installation
sudo mv /usr/local/bin/prometheus /usr/local/bin/prometheus.old

# Download new version
VERSION="2.54.1"  # Check for latest version
wget https://github.com/prometheus/prometheus/releases/download/v${VERSION}/prometheus-${VERSION}.linux-amd64.tar.gz

# Extract and install
tar -xzf prometheus-${VERSION}.linux-amd64.tar.gz
sudo cp prometheus-${VERSION}.linux-amd64/prometheus /usr/local/bin/
sudo cp prometheus-${VERSION}.linux-amd64/promtool /usr/local/bin/
sudo chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

# Verify configuration
promtool check config /etc/prometheus/prometheus.yml

# Start Prometheus
sudo systemctl start prometheus
sudo systemctl status prometheus

# Verify version
prometheus --version
```

#### Update Grafana Only

```bash
ssh deploy@YOUR_OBSERVABILITY_IP

# Update Grafana
sudo apt-get update
sudo apt-get install --only-upgrade grafana

# Restart
sudo systemctl restart grafana-server
sudo systemctl status grafana-server
```

#### Update Laravel Application Only

```bash
ssh deploy@YOUR_VPSMANAGER_IP

cd /var/www/vpsmanager

# Maintenance mode
php artisan down

# Pull latest code
git pull origin main

# Update dependencies
composer install --no-dev --optimize-autoloader

# Run migrations
php artisan migrate --force

# Clear and rebuild caches
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Exit maintenance mode
php artisan up
```

## Post-Update Verification

### 1. Check Service Status

```bash
# Observability VPS
ssh deploy@YOUR_OBSERVABILITY_IP 'systemctl status prometheus grafana-server loki alertmanager'

# VPSManager VPS
ssh deploy@YOUR_VPSMANAGER_IP 'systemctl status nginx php8.4-fpm mariadb redis-server'
```

### 2. Verify Web Access

- Grafana: http://YOUR_OBS_IP:3000
- Prometheus: http://YOUR_OBS_IP:9090
- VPSManager: http://YOUR_VPS_IP:8080

### 3. Check Monitoring Integration

```bash
# Check Prometheus targets
# Open: http://YOUR_OBS_IP:9090/targets
# All should be "UP"

# Check Grafana dashboards
# Verify data is flowing

# Check logs in Loki
# Grafana → Explore → Loki → Query: {job="varlogs"}
```

### 4. Test Application Functionality

- Run manual tests on VPSManager
- Verify database connections
- Check API endpoints
- Test user authentication

## Rollback Procedures

If update fails, rollback using backups:

### Rollback Observability Stack

```bash
ssh deploy@YOUR_OBSERVABILITY_IP

# Stop services
sudo systemctl stop prometheus grafana-server loki

# Restore from backup
sudo tar -xzf ~/prometheus-backup-*.tar.gz -C /
sudo tar -xzf ~/grafana-backup-*.tar.gz -C /

# Start services
sudo systemctl start prometheus grafana-server loki
```

### Rollback VPSManager

```bash
ssh deploy@YOUR_VPSMANAGER_IP

cd /var/www/vpsmanager
php artisan down

# Restore database
mysql -u vpsmanager -p vpsmanager < ~/vpsmanager-db-backup-*.sql

# Restore application files
sudo tar -xzf ~/vpsmanager-app-backup-*.tar.gz -C /

# Restore permissions
sudo chown -R www-data:www-data /var/www/vpsmanager
sudo chmod -R 755 /var/www/vpsmanager

php artisan up
```

## Update Schedule

Recommended update schedule:

| Component | Frequency | When |
|-----------|-----------|------|
| Security patches | Immediately | As released |
| Minor updates | Monthly | 1st week of month |
| Major versions | Quarterly | After testing |
| Deployment scripts | As needed | When features needed |

## Common Update Issues

### Issue: Service Won't Start After Update

**Solution:**
```bash
# Check logs
journalctl -u prometheus -n 50
journalctl -u grafana-server -n 50

# Verify configuration
promtool check config /etc/prometheus/prometheus.yml

# Check permissions
sudo chown -R prometheus:prometheus /var/lib/prometheus
sudo chown -R grafana:grafana /var/lib/grafana
```

### Issue: Data Loss After Update

**Prevention:**
- Always backup before updating
- Test restore procedure
- Verify backups are complete

**Recovery:**
```bash
# Restore from backup (see Rollback section)
```

### Issue: Configuration Incompatibility

**Solution:**
```bash
# Review configuration changes
diff /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.old

# Merge configurations
# Update to new format if needed
```

### Issue: Port Conflicts

**Solution:**
```bash
# Find process using port
sudo lsof -i :9090

# Stop conflicting service
sudo systemctl stop <service>

# Restart monitoring service
sudo systemctl start prometheus
```

## Update Checklist

Print and use this checklist:

### Pre-Update
- [ ] Backup all data (Prometheus, Grafana, Database)
- [ ] Backup all configurations
- [ ] Document current versions
- [ ] Review changelog and breaking changes
- [ ] Schedule maintenance window
- [ ] Notify users (if applicable)
- [ ] Update git repository

### During Update
- [ ] Put applications in maintenance mode
- [ ] Run deployment script
- [ ] Verify no errors during update
- [ ] Check service status
- [ ] Monitor logs for errors

### Post-Update
- [ ] Verify all services running
- [ ] Test web access to all components
- [ ] Check Prometheus targets
- [ ] Verify data collection
- [ ] Test application functionality
- [ ] Run database migrations (if any)
- [ ] Clear application caches
- [ ] Take out of maintenance mode
- [ ] Monitor for 1 hour

### Cleanup
- [ ] Remove old backup files (after 30 days)
- [ ] Document any issues encountered
- [ ] Update internal documentation
- [ ] Remove old VPS (if blue-green)

## Best Practices

1. **Always backup before updating**
2. **Test updates in staging first** (if available)
3. **Update during low-traffic periods**
4. **Monitor closely after update** (first 24 hours)
5. **Keep rollback plan ready**
6. **Document all changes**
7. **Verify backups are restorable**

## Emergency Contacts

Document your rollback plan:
- **Backup location:** _________________
- **Rollback time estimate:** _________________
- **Emergency contact:** _________________

## Version History

Track your updates:

| Date | Version | Components Updated | Issues | Notes |
|------|---------|-------------------|---------|-------|
| | | | | |
| | | | | |
| | | | | |
