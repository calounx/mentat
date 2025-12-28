# Troubleshooting Guide

Central index of all troubleshooting resources in the Mentat repository.

---

## Quick Navigation

**By Component:**
- [Observability Stack](#observability-stack-issues)
- [CHOM (Laravel Application)](#chom-issues)
- [Deployment & Installation](#deployment-issues)
- [Network & Connectivity](#network-issues)
- [Security & Authentication](#security-issues)

**By Symptom:**
- [Services won't start](#services-wont-start)
- [Can't access web interfaces](#cant-access-web-interfaces)
- [No metrics/logs appearing](#no-data-appearing)
- [SSL/TLS certificate errors](#ssltls-errors)
- [High resource usage](#performance-issues)

---

## Observability Stack Issues

### Installation Problems

**📖 Primary Resource:** [observability-stack/QUICK_START.md - Troubleshooting Section](../observability-stack/QUICK_START.md#troubleshooting)

Covers:
- Services not starting (ports in use, permissions, config errors)
- Metrics not appearing (firewall, target files, network)
- Grafana login issues (password reset, connectivity)
- SSL certificate failures (DNS, port blocking)
- High memory usage (retention, scrape frequency)
- Logs not showing in Loki (Promtail config, connectivity)

**Additional Resources:**
- [Deployment Troubleshooting](../observability-stack/deploy/README.md#troubleshooting)
- [Quick Test Reference](../observability-stack/tests/QUICK_TEST_REFERENCE.md) - Verify installation
- [Secrets Troubleshooting](../observability-stack/docs/SECRETS.md#troubleshooting)

### Upgrade Issues

**📖 Primary Resource:** [Upgrade Quickstart - Troubleshooting](../observability-stack/docs/upgrade/UPGRADE_QUICKSTART.md#troubleshooting)

Covers:
- Failed upgrades and rollback procedures
- Version compatibility issues
- Data migration problems
- Service restart failures

**Additional Resources:**
- [Upgrade Orchestration Guide](../observability-stack/docs/upgrade/UPGRADE_ORCHESTRATION.md)
- [Version Update Runbook](../observability-stack/docs/upgrade/VERSION_UPDATE_RUNBOOK.md)

### Services Won't Start

**Symptoms:**
- `systemctl status prometheus` shows failed/inactive
- Services repeatedly crashing
- "Address already in use" errors

**Solutions:**

1. **Check service status and logs:**
   ```bash
   systemctl status prometheus grafana-server loki
   journalctl -u prometheus -n 50 --no-pager
   ```

2. **Check for port conflicts:**
   ```bash
   sudo netstat -tlnp | grep -E ':(3000|9090|3100)'
   ```

3. **Validate configuration:**
   ```bash
   # Prometheus
   promtool check config /etc/prometheus/prometheus.yml

   # Check file permissions
   ls -la /etc/prometheus /var/lib/prometheus
   ```

**📖 Detailed Guide:** [QUICK_START.md - Services Not Starting](../observability-stack/QUICK_START.md#services-not-starting)

### No Metrics/Logs Appearing

**Symptoms:**
- Grafana shows "No data"
- Prometheus has no targets
- Loki queries return empty

**Solutions:**

1. **Check Prometheus targets:**
   ```bash
   curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job, instance, health}'
   ```

2. **Test exporter connectivity:**
   ```bash
   curl -m 5 http://MONITORED_HOST_IP:9100/metrics
   ```

3. **Verify firewall rules:**
   ```bash
   sudo ufw status verbose
   # Should allow connections from Observability VPS
   ```

**📖 Detailed Guide:** [QUICK_START.md - Metrics Not Appearing](../observability-stack/QUICK_START.md#metrics-not-appearing-in-grafana)

### Grafana Access Issues

**Symptoms:**
- Can't login to Grafana
- Forgot admin password
- Connection refused

**Solutions:**

1. **Reset admin password:**
   ```bash
   sudo grafana-cli admin reset-admin-password NEW_PASSWORD
   sudo systemctl restart grafana-server
   ```

2. **Check Grafana is running:**
   ```bash
   sudo systemctl status grafana-server
   sudo netstat -tlnp | grep 3000
   ```

3. **Check Nginx proxy (if using domain):**
   ```bash
   sudo nginx -t
   sudo systemctl status nginx
   ```

**📖 Detailed Guide:** [QUICK_START.md - Grafana Login Issues](../observability-stack/QUICK_START.md#grafana-login-issues)

---

## CHOM Issues

### Laravel Application Problems

**📖 Primary Resource:** [chom/README.md - Development Section](../chom/README.md#development)

Common issues:
- Database connection errors
- Missing dependencies
- Asset build failures
- Queue worker issues

**Quick fixes:**

```bash
# Clear all caches
cd chom
php artisan optimize:clear

# Rebuild dependencies
composer install
npm install && npm run build

# Reset database (development only!)
php artisan migrate:fresh

# Check logs
tail -f storage/logs/laravel.log
```

### Deployment Issues

**📖 Primary Resource:** [chom/deploy/README.md](../chom/deploy/README.md)

Covers:
- VPS setup problems
- Observability integration issues
- Stripe webhook failures
- SSH key permissions

---

## Deployment Issues

### Bootstrap Installer Problems

**📖 Primary Resource:** [observability-stack/deploy/README.md - Troubleshooting](../observability-stack/deploy/README.md#troubleshooting)

Common issues:
- Script fails with permission errors
- Dependencies not installing
- Role selection confusion
- Config validation failures

**Solutions:**

1. **Run as root:**
   ```bash
   sudo bash bootstrap.sh
   # or
   curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash
   ```

2. **Check prerequisites:**
   ```bash
   # Debian 13 or Ubuntu 22.04+
   lsb_release -a

   # Internet connectivity
   ping -c 3 1.1.1.1

   # Sufficient disk space
   df -h
   ```

3. **Enable debug mode:**
   ```bash
   export DEBUG=1
   sudo bash bootstrap.sh
   ```

### Installation Script Failures

**Symptoms:**
- Script exits with error code
- Partial installation
- Missing components

**Diagnosis:**

```bash
# Check what was installed
systemctl list-units --type=service | grep -E 'prometheus|grafana|loki'

# Review installation logs
journalctl -xe | tail -100

# Verify file structure
ls -la /opt/observability-stack/
ls -la /etc/prometheus/
```

**📖 Detailed Guide:** [Installation Tools Documentation](../observability-stack/scripts/tools/INSTALLATION.md)

---

## Network Issues

### Firewall Blocking Connections

**Symptoms:**
- Timeout when accessing services
- Prometheus can't scrape exporters
- Promtail can't send logs to Loki

**Solutions:**

1. **Check UFW status:**
   ```bash
   sudo ufw status verbose
   ```

2. **Allow required ports:**
   ```bash
   # From Observability VPS to monitored host
   sudo ufw allow from OBSERVABILITY_IP to any port 9100

   # Grafana public access
   sudo ufw allow 443/tcp
   ```

3. **Test connectivity:**
   ```bash
   # From Observability VPS
   telnet MONITORED_HOST_IP 9100

   # From monitored host
   telnet OBSERVABILITY_IP 9090
   ```

**📖 Reference:** [SECURITY.md - Network Security](../observability-stack/SECURITY.md#network-security)

### DNS Resolution Problems

**Symptoms:**
- Can't resolve domain names
- SSL certificate validation fails
- Services can't connect by hostname

**Solutions:**

1. **Test DNS resolution:**
   ```bash
   dig your-domain.com
   nslookup your-domain.com
   ```

2. **Check /etc/hosts:**
   ```bash
   cat /etc/hosts
   # Ensure no conflicts
   ```

3. **Verify DNS servers:**
   ```bash
   cat /etc/resolv.conf
   ```

### SSL/TLS Errors

**Symptoms:**
- "Certificate not valid" errors
- Let's Encrypt validation fails
- SSL handshake failures

**Solutions:**

1. **Verify DNS points to server:**
   ```bash
   dig +short your-domain.com
   # Should return your server's IP
   ```

2. **Check certificate status:**
   ```bash
   sudo certbot certificates
   ```

3. **Manual certificate renewal:**
   ```bash
   sudo certbot renew --force-renewal
   sudo systemctl reload nginx
   ```

4. **Check certificate expiry:**
   ```bash
   echo | openssl s_client -connect your-domain.com:443 2>/dev/null | openssl x509 -noout -dates
   ```

**📖 Detailed Guide:** [QUICK_START.md - SSL Certificate Failed](../observability-stack/QUICK_START.md#ssl-certificate-failed)

---

## Security Issues

### Authentication Failures

**Symptoms:**
- Can't login to Grafana
- HTTP 401 errors from Prometheus/Loki
- SSH connection refused

**Solutions:**

1. **Grafana password issues:**
   ```bash
   # Reset admin password
   sudo grafana-cli admin reset-admin-password NEW_PASSWORD
   sudo systemctl restart grafana-server
   ```

2. **HTTP Basic Auth:**
   ```bash
   # Check htpasswd file exists
   ls -la /etc/nginx/.htpasswd

   # Test authentication
   curl -u username:password https://domain.com/prometheus/-/healthy
   ```

3. **SSH access:**
   ```bash
   # Check SSH service
   sudo systemctl status sshd

   # Verify firewall allows SSH
   sudo ufw status | grep 22
   ```

**📖 Reference:** [SECURITY.md - Authentication](../observability-stack/SECURITY.md#authentication--authorization)

### Secrets Management Issues

**Symptoms:**
- Can't access secrets
- Services fail to start due to missing credentials
- Permission denied errors

**Solutions:**

1. **Check secrets directory:**
   ```bash
   sudo ls -la /opt/observability-stack/secrets/
   # Should show: drwx------ (700)
   ```

2. **Re-initialize secrets:**
   ```bash
   cd observability-stack
   sudo ./scripts/init-secrets.sh
   ```

3. **Verify secret references:**
   ```bash
   # In config files, should use format:
   # ${SECRET:secret_name}
   grep -r "SECRET:" config/
   ```

**📖 Detailed Guide:** [Secrets Management Documentation](../observability-stack/docs/SECRETS.md)

---

## Performance Issues

### High Memory Usage

**Symptoms:**
- OOM (Out of Memory) errors
- Services being killed
- Slow query performance

**Solutions:**

1. **Check memory usage:**
   ```bash
   free -h
   systemctl status prometheus | grep Memory
   systemctl status loki | grep Memory
   ```

2. **Reduce retention:**
   ```bash
   # Edit Prometheus retention
   sudo nano /etc/systemd/system/prometheus.service
   # Change --storage.tsdb.retention.time=30d to 15d

   sudo systemctl daemon-reload
   sudo systemctl restart prometheus
   ```

3. **Reduce scrape frequency:**
   ```bash
   sudo nano /etc/prometheus/prometheus.yml
   # Change scrape_interval from 15s to 30s or 60s

   sudo systemctl reload prometheus
   ```

**📖 Detailed Guide:** [QUICK_START.md - High Memory Usage](../observability-stack/QUICK_START.md#high-memory-usage)

### High Disk Usage

**Symptoms:**
- Disk full warnings
- Services unable to write data
- Database corruption

**Solutions:**

1. **Check disk usage:**
   ```bash
   df -h
   du -sh /var/lib/prometheus/*
   du -sh /var/lib/loki/*
   ```

2. **Reduce retention periods:**
   ```bash
   # Prometheus (see High Memory Usage above)
   # Loki
   sudo nano /etc/loki/config.yml
   # Adjust retention_period under table_manager

   sudo systemctl restart loki
   ```

3. **Clean up old data:**
   ```bash
   # Prometheus (automatic based on retention)
   # Loki
   sudo systemctl stop loki
   sudo rm -rf /var/lib/loki/index/*
   sudo rm -rf /var/lib/loki/chunks/*
   sudo systemctl start loki
   ```

### Slow Dashboard Loading

**Symptoms:**
- Grafana dashboards timeout
- Queries take too long
- UI feels sluggish

**Solutions:**

1. **Optimize queries:**
   - Use recording rules for complex queries
   - Reduce time range
   - Limit number of series returned

2. **Check query performance:**
   ```bash
   # Prometheus query stats
   curl http://localhost:9090/api/v1/status/tsdb
   ```

3. **Increase query timeout:**
   ```bash
   sudo nano /etc/systemd/system/prometheus.service
   # Add --query.timeout=2m

   sudo systemctl daemon-reload
   sudo systemctl restart prometheus
   ```

---

## Testing & Validation

### Running Diagnostic Tests

**📖 Primary Resource:** [Test Index](../observability-stack/tests/TEST_INDEX.md)

Quick validation:

```bash
cd observability-stack

# All tests
make test-all

# Quick health check
make test-quick

# Security tests
make test-security

# Integration tests
make test-integration
```

**📖 Additional Resources:**
- [Quick Test Reference](../observability-stack/tests/QUICK_TEST_REFERENCE.md)
- [Security Test Guide](../observability-stack/tests/SECURITY_TEST_GUIDE.md)

### Preflight Checks

Run before deployment to verify prerequisites:

```bash
cd observability-stack
./observability preflight --observability-vps
./observability preflight --vpsmanager
./observability preflight --monitored-host
```

---

## Getting Help

### Before Asking for Help

1. **Check this troubleshooting guide** for your issue
2. **Review the logs:**
   ```bash
   journalctl -xe
   journalctl -u SERVICE_NAME -n 100
   ```
3. **Run diagnostic tests:**
   ```bash
   cd observability-stack && make test-quick
   ```
4. **Search existing issues:** https://github.com/calounx/mentat/issues

### How to Ask for Help

**Open a GitHub Issue with:**

1. **Environment information:**
   ```bash
   # Operating system
   lsb_release -a

   # Version
   git describe --tags

   # Service status
   systemctl status SERVICE_NAME
   ```

2. **Error messages and logs:**
   ```bash
   journalctl -u SERVICE_NAME -n 50 --no-pager
   ```

3. **Steps to reproduce** the issue

4. **What you've already tried** from this guide

### Additional Resources

**Internal Documentation:**
- [Main README](../README.md) - Project overview
- [Observability Stack README](../observability-stack/README.md) - Component details
- [CHOM README](../chom/README.md) - Application documentation
- [Security Guide](../SECURITY.md) - Security policies
- [Glossary](GLOSSARY.md) - Technical term definitions

**External Documentation:**
- [Prometheus Troubleshooting](https://prometheus.io/docs/prometheus/latest/troubleshooting/)
- [Grafana Troubleshooting](https://grafana.com/docs/grafana/latest/troubleshooting/)
- [Loki Troubleshooting](https://grafana.com/docs/loki/latest/operations/troubleshooting/)
- [Debian Security](https://www.debian.org/security/)

**Community:**
- GitHub Discussions: https://github.com/calounx/mentat/discussions
- GitHub Issues: https://github.com/calounx/mentat/issues

---

## Common Error Messages

### "Port already in use"

**Error:**
```
bind: address already in use
```

**Solution:**
```bash
# Find what's using the port
sudo netstat -tlnp | grep :9090

# Stop the conflicting service
sudo systemctl stop CONFLICTING_SERVICE

# Or change the port in configuration
```

### "Permission denied"

**Error:**
```
Permission denied (publickey,password)
# or
open /path/to/file: permission denied
```

**Solution:**
```bash
# For SSH
ssh-copy-id user@host

# For files
sudo chown -R USER:GROUP /path/to/directory
sudo chmod 755 /path/to/directory
sudo chmod 644 /path/to/file
```

### "Connection refused"

**Error:**
```
dial tcp: connect: connection refused
```

**Solution:**
```bash
# Check service is running
sudo systemctl status SERVICE_NAME

# Check firewall
sudo ufw status | grep PORT

# Test connectivity
telnet HOST PORT
```

### "No such file or directory"

**Error:**
```
/path/to/file: No such file or directory
```

**Solution:**
```bash
# Verify expected file location
ls -la /path/to/

# Check for typos in path
find / -name "filename" 2>/dev/null

# Reinstall if system file is missing
```

### "Certificate verification failed"

**Error:**
```
x509: certificate has expired or is not yet valid
# or
certificate verify failed
```

**Solution:**
```bash
# Renew SSL certificate
sudo certbot renew --force-renewal
sudo systemctl reload nginx

# Check system time
timedatectl status

# Verify certificate
openssl x509 -in /path/to/cert.pem -text -noout
```

---

**Last Updated:** 2025-12-28
**Maintainers:** Mentat Team
**Version:** 1.0
