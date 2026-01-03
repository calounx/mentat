# Edge Case Quick Reference Guide

Quick troubleshooting guide for handling edge cases and unusual scenarios during deployment.

---

## Quick Diagnosis

### Is it safe to re-run the deployment?

**YES** - All deployment scripts are idempotent. You can safely re-run:
- `setup-stilgar-user-standalone.sh` - Multiple times, same result
- `deploy-chom-automated.sh` - Use skip flags to avoid repeating phases
- `deploy-application.sh` - Creates new release, atomic swap

### How to resume a failed deployment?

```bash
# Identify which phase failed, then skip completed phases:
sudo ./deploy-chom-automated.sh \
    --skip-user-setup \
    --skip-ssh \
    --skip-secrets \
    # Continue from where it failed
```

---

## Common Edge Cases

### 1. User Already Exists

**Scenario:** Running `setup-stilgar-user-standalone.sh` when user exists

**Behavior:** ✓ Script detects existing user and skips creation

**What gets updated:**
- Sudo configuration (if missing)
- SSH directory permissions (if incorrect)
- Bash profile (if marker not found)

**Safe to run:** YES - Multiple times

---

### 2. Disk Space Low

**Detection:**
```bash
# Check available space
df -h /

# Need at least:
# - 5GB for full deployment
# - 1GB for application deployment only
# - 500MB for git clone
```

**If space is low:**
```bash
# Clean old releases
cd /var/www/chom/releases
ls -lt  # Shows releases by age
sudo rm -rf <old-release-directory>

# Clean Docker images (if using Docker)
docker system prune -a

# Clean package caches
sudo apt-get clean
sudo apt-get autoclean
```

**Prevention:**
Add to deployment script:
```bash
available=$(df / | awk 'NR==2 {print $4}')
required=5242880  # 5GB in KB
if [[ $available -lt $required ]]; then
    echo "ERROR: Insufficient disk space"
    exit 1
fi
```

---

### 3. Concurrent Deployments

**Scenario:** Two deployments running simultaneously

**Risk Level:** Medium
- ✓ Safe: Different users on different servers
- ⚠ Risky: Same application deployment
- ✗ Unsafe: Same database migrations

**Protection:**
```bash
# Add lock file at start of deploy-application.sh
LOCK_FILE="/var/lock/chom-deployment.lock"
exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    echo "Another deployment is running"
    exit 1
fi

# Lock automatically released when script exits
```

**Check for running deployment:**
```bash
# Check for deployment processes
ps aux | grep deploy-chom

# Check lock file
ls -la /var/lock/*deployment*.lock

# Check for recent deployments
journalctl -u deployment -n 50
```

---

### 4. Network Timeout During Git Clone

**Scenario:** Network interruption during repository clone

**Symptoms:**
```
fatal: early EOF
fatal: index-pack failed
error: RPC failed; result=18, HTTP code = 200
```

**Recovery:**
```bash
# The deployment will fail and rollback automatically
# Re-run the deployment - it will clone again

# If partial clone exists, clean it:
cd /var/www/chom/releases
sudo rm -rf $(ls -t | head -1)  # Remove latest (failed) release

# Then re-run deployment
sudo ./deploy-application.sh --branch main
```

**Prevention:**
```bash
# Use shallow clone with timeout
timeout 300 git clone --depth 1 --branch main $REPO_URL

# Or with retry:
for i in {1..3}; do
    if git clone --depth 1 --branch main $REPO_URL; then
        break
    fi
    echo "Clone attempt $i failed, retrying..."
    sleep 5
done
```

---

### 5. Database Migration Fails

**Scenario:** Migration fails midway

**Automatic Behavior:**
- ✓ Deployment rolls back to previous release
- ✓ Previous migrations remain applied
- ✓ Application continues on old version

**Manual Recovery:**
```bash
# Check migration status
cd /var/www/chom/current
php artisan migrate:status

# If migration is stuck:
# 1. Check database locks
mysql -u root -p -e "SHOW PROCESSLIST;"

# 2. Roll back last migration
php artisan migrate:rollback --step=1

# 3. Fix the issue in code

# 4. Re-deploy
sudo ./deploy-application.sh --branch main
```

**Prevention:**
```bash
# Test migrations in staging first
php artisan migrate --pretend

# Use database transactions in migrations
public function up()
{
    Schema::table('users', function (Blueprint $table) {
        // Will rollback if fails
    });
}
```

---

### 6. SSH Keys Lost or Overwritten

**Scenario:** authorized_keys gets deleted

**Symptoms:**
- Can't SSH into server
- Password prompt appears

**Prevention:** ✓ Already handled!
- Script preserves existing authorized_keys
- Never truncates or overwrites

**Recovery (if somehow lost):**
```bash
# From console/KVM access:
sudo su - stilgar
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "YOUR_PUBLIC_KEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Or from another server:
ssh-copy-id stilgar@target-server
```

---

### 7. Sudoers File Corruption

**Scenario:** Invalid syntax in /etc/sudoers.d/*

**Symptoms:**
```
sudo: parse error in /etc/sudoers.d/stilgar-nopasswd near line 1
sudo: no valid sudoers sources found, quitting
```

**Prevention:** ✓ Already handled!
- Script uses `visudo -c` to validate
- Invalid file automatically removed

**Manual Recovery:**
```bash
# From root console/KVM:
rm /etc/sudoers.d/stilgar-nopasswd

# Recreate properly:
echo "stilgar ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/stilgar-nopasswd
chmod 440 /etc/sudoers.d/stilgar-nopasswd

# Validate:
visudo -c
```

---

### 8. Special Characters in Environment Variables

**Scenario:** Password contains $, `, ", ', etc.

**Problem:**
```bash
PASSWORD='p@$$w0rd'  # $ will be interpreted
PASSWORD="pass'word" # Quote mismatch
```

**Solution:**
```bash
# Use single quotes for literal strings
PASSWORD='p@$$w0rd!`"'  # All chars literal

# Or escape special chars in double quotes
PASSWORD="p@\$\$w0rd"

# Best: Generate base64-encoded passwords
PASSWORD=$(openssl rand -base64 32)
```

**In Scripts:**
```bash
# Always quote variable expansion
mysql -u root -p"${PASSWORD}"  # Not: -p$PASSWORD

# Use printf for complex strings
printf "PASSWORD=%s\n" "$PASSWORD" >> .env
```

---

### 9. Deployment Hangs or Times Out

**Scenario:** Deployment seems stuck

**Common Causes:**
1. Waiting for input (password prompt)
2. Composer waiting for GitHub rate limit
3. NPM install hanging
4. Database connection timeout

**Diagnosis:**
```bash
# Check running processes
ps auxf | grep deploy

# Check what script is waiting for
lsof -p <PID>

# Check network connections
netstat -tulpn | grep <PID>

# Check system resources
htop
df -h
free -h
```

**Recovery:**
```bash
# Kill gracefully
kill -TERM <PID>

# Wait 10 seconds, then force
sleep 10
kill -9 <PID>

# Clean up lock files
rm -f /var/lock/*deployment*.lock

# Clean up temp files
rm -rf /tmp/chom-deploy-*

# Re-run deployment
```

---

### 10. Permission Denied Errors

**Scenario:** Script can't write to directory

**Common Locations:**
- `/var/www/chom` - Needs www-data or deploy user ownership
- `/home/stilgar` - Needs stilgar ownership
- `/etc/sudoers.d` - Needs root ownership

**Fix Ownership:**
```bash
# Application directory
sudo chown -R stilgar:www-data /var/www/chom
sudo chmod -R 755 /var/www/chom

# Storage directory
sudo chmod -R 775 /var/www/chom/shared/storage

# User home
sudo chown -R stilgar:stilgar /home/stilgar
sudo chmod 750 /home/stilgar
```

**Check Permissions:**
```bash
# List with details
ls -la /var/www/chom

# Check specific directory
stat /var/www/chom/shared

# Find files with wrong permissions
find /var/www/chom -not -user stilgar
```

---

### 11. Symlink Points to Wrong Release

**Scenario:** Current symlink broken or pointing to failed release

**Symptoms:**
- 404 errors
- Old version running
- "File not found" errors

**Check:**
```bash
ls -la /var/www/chom/current
# Should show: current -> releases/20260103_181049

# Verify target exists
ls -la /var/www/chom/releases/
```

**Fix:**
```bash
# List releases
cd /var/www/chom/releases
ls -lt  # Sorted by date

# Point to last known good release
cd /var/www/chom
sudo rm current
sudo ln -s releases/20260103_180000 current

# Reload services
sudo systemctl reload php8.2-fpm
sudo systemctl reload nginx
```

---

### 12. Out of Memory During Composer Install

**Scenario:** Composer killed by OOM

**Symptoms:**
```
Killed
PHP Fatal error: Allowed memory size exhausted
```

**Temporary Fix:**
```bash
# Increase PHP memory limit for this command only
php -d memory_limit=2G /usr/bin/composer install
```

**Permanent Fix:**
```bash
# Edit php.ini
sudo nano /etc/php/8.2/cli/php.ini

# Change:
memory_limit = 2G

# Or add swap space
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make permanent
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

---

### 13. Git Credentials Required

**Scenario:** Private repository, needs authentication

**Setup GitHub Token:**
```bash
# Generate token at: https://github.com/settings/tokens
# Needs 'repo' scope

# Option 1: Use in URL
REPO_URL="https://TOKEN@github.com/user/repo.git"

# Option 2: Git credential helper
git config --global credential.helper store
echo "https://TOKEN@github.com" > ~/.git-credentials

# Option 3: SSH keys (preferred)
ssh-keygen -t ed25519 -C "deploy@chom"
cat ~/.ssh/id_ed25519.pub
# Add to GitHub: Settings > SSH Keys
REPO_URL="git@github.com:user/repo.git"
```

---

### 14. Services Won't Reload

**Scenario:** systemctl reload fails

**Symptoms:**
```
Job for php8.2-fpm.service failed because the control process exited with error code.
```

**Diagnosis:**
```bash
# Check service status
systemctl status php8.2-fpm

# Check logs
journalctl -u php8.2-fpm -n 50

# Test config
php-fpm8.2 -t

# For nginx:
nginx -t
```

**Common Fixes:**
```bash
# Restart instead of reload
sudo systemctl restart php8.2-fpm

# If still fails, check config:
sudo nano /etc/php/8.2/fpm/pool.d/www.conf

# Check socket/port:
# listen = /run/php/php8.2-fpm.sock
# Should match nginx config

# Verify socket exists:
ls -la /run/php/
```

---

### 15. Rollback Needed

**Scenario:** Need to rollback to previous version

**Automatic Rollback:**
- Health check failure automatically triggers rollback
- Migration failure triggers rollback

**Manual Rollback:**
```bash
# Using rollback script
cd /var/www/chom
sudo ./deploy/scripts/rollback.sh

# Or manually:
cd /var/www/chom/releases
ls -lt  # List by date

# Point to previous release
cd ..
sudo rm current
sudo ln -s releases/20260103_170000 current

# Reload services
sudo systemctl reload php8.2-fpm nginx

# Restart queue workers
sudo supervisorctl restart chom-worker:*
```

---

## Testing Edge Cases

### Test Idempotency
```bash
# Run script 3 times
for i in {1..3}; do
    sudo ./setup-stilgar-user-standalone.sh testuser
    id testuser
done

# Verify UID doesn't change
```

### Test Disk Full
```bash
# Create small filesystem for testing
dd if=/dev/zero of=/tmp/test.img bs=1M count=100
mkfs.ext4 /tmp/test.img
mkdir /tmp/testmount
mount -o loop /tmp/test.img /tmp/testmount

# Fill it
dd if=/dev/zero of=/tmp/testmount/fill bs=1M count=95

# Try to write (should fail)
dd if=/dev/zero of=/tmp/testmount/fail bs=1M count=10

# Cleanup
umount /tmp/testmount
rm /tmp/test.img
```

### Test Concurrent Execution
```bash
# Run two deployments simultaneously
sudo ./deploy-application.sh --branch main &
sudo ./deploy-application.sh --branch main &

# Should see error from second one
```

---

## Monitoring Edge Cases

### Set Up Alerts

```bash
# Disk space alert
df / | awk 'NR==2 {if ($5+0 > 80) print "ALERT: Disk "  $5 " full"}'

# Memory alert
free | awk 'NR==2 {if ($7 < 524288) print "ALERT: Low memory"}'

# Deployment failures
journalctl -u deployment --since "1 hour ago" | grep -i error
```

---

## Best Practices

1. **Always test in staging first**
2. **Use --dry-run to preview changes**
3. **Keep at least 5GB free disk space**
4. **Monitor deployment logs in real-time**
5. **Have rollback plan ready**
6. **Test rollback procedure regularly**
7. **Document any custom changes**
8. **Keep deployment scripts in version control**
9. **Use deployment locks for production**
10. **Validate before cutting over**

---

## Emergency Contacts

When things go wrong:

1. **Check logs first:** `/var/log/chom/deployment.log`
2. **Check this guide** for common scenarios
3. **Check main documentation:** `README.md`
4. **Check runbooks:** `deploy/runbooks/`
5. **Rollback if uncertain**

---

**Last Updated:** 2026-01-03
**Version:** 1.0
