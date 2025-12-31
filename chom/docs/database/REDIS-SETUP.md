# Redis Setup Guide for CHOM Performance Optimizations

## Overview
This guide walks through installing and configuring Redis for the CHOM platform performance optimizations.

---

## Prerequisites
- Ubuntu 20.04+ or Debian 11+
- Sudo access
- PHP 8.2+ with phpredis extension

---

## Installation Steps

### 1. Install Redis Server

```bash
# Update package lists
sudo apt update

# Install Redis server
sudo apt install redis-server -y

# Verify installation
redis-cli --version
```

### 2. Install PHP Redis Extension

```bash
# Install phpredis extension
sudo apt install php8.2-redis -y

# Verify extension is loaded
php -m | grep redis

# Restart PHP-FPM
sudo systemctl restart php8.2-fpm
```

### 3. Configure Redis

Edit Redis configuration:
```bash
sudo nano /etc/redis/redis.conf
```

Recommended settings for production:
```conf
# Bind to localhost only (more secure)
bind 127.0.0.1 ::1

# Enable protected mode
protected-mode yes

# Set max memory limit (adjust based on your server)
maxmemory 256mb

# Eviction policy when max memory is reached
maxmemory-policy allkeys-lru

# Enable persistence (optional, for session/queue data)
save 900 1
save 300 10
save 60 10000

# Log level
loglevel notice

# Log file
logfile /var/log/redis/redis-server.log
```

### 4. Start and Enable Redis

```bash
# Start Redis service
sudo systemctl start redis-server

# Enable Redis to start on boot
sudo systemctl enable redis-server

# Check status
sudo systemctl status redis-server
```

### 5. Test Redis Connection

```bash
# Test basic connection
redis-cli ping
# Should return: PONG

# Test set/get
redis-cli set test "Hello CHOM"
redis-cli get test
# Should return: "Hello CHOM"

# Clean up test
redis-cli del test
```

---

## Security Configuration

### 1. Set Redis Password (Recommended for Production)

```bash
# Generate strong password
openssl rand -base64 32

# Edit Redis config
sudo nano /etc/redis/redis.conf
```

Add/uncomment this line:
```conf
requirepass YOUR_STRONG_PASSWORD_HERE
```

Restart Redis:
```bash
sudo systemctl restart redis-server
```

Update your `.env`:
```env
REDIS_PASSWORD=YOUR_STRONG_PASSWORD_HERE
```

### 2. Configure Firewall

```bash
# Redis should only be accessible locally
# Verify Redis is not exposed
sudo netstat -tulpn | grep 6379

# Should show: 127.0.0.1:6379 (localhost only)
```

### 3. Disable Dangerous Commands (Production)

Edit Redis config:
```bash
sudo nano /etc/redis/redis.conf
```

Add these lines:
```conf
rename-command FLUSHDB ""
rename-command FLUSHALL ""
rename-command KEYS ""
rename-command CONFIG ""
```

Restart Redis:
```bash
sudo systemctl restart redis-server
```

---

## Application Configuration

### 1. Update Laravel Environment

Copy settings from `.env.example` to `.env`:
```env
# Cache Configuration
CACHE_STORE=redis
CACHE_PREFIX=

# Queue Configuration
QUEUE_CONNECTION=redis

# Session Configuration
SESSION_DRIVER=redis

# Redis Connection
REDIS_CLIENT=phpredis
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=6379
REDIS_DB=0
REDIS_CACHE_DB=1
REDIS_QUEUE_DB=2
REDIS_SESSION_DB=3
REDIS_PREFIX=chom
REDIS_MAX_RETRIES=3
REDIS_PERSISTENT=false
```

### 2. Clear Laravel Caches

```bash
cd /path/to/chom

# Clear all caches
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan view:clear

# Optimize for production
php artisan config:cache
php artisan route:cache
php artisan view:cache
```

### 3. Restart Services

```bash
# Restart PHP-FPM
sudo systemctl restart php8.2-fpm

# Restart queue workers
php artisan queue:restart

# Restart web server (if using Nginx)
sudo systemctl restart nginx
```

---

## Verification

### 1. Test Laravel Redis Connection

```bash
php artisan tinker
```

In Tinker:
```php
// Test cache
Cache::store('redis')->put('test', 'Hello from Laravel', 60);
Cache::store('redis')->get('test');
// Should return: "Hello from Laravel"

// Test connection to different databases
Redis::connection('cache')->ping();
Redis::connection('default')->ping();
// Both should return: true or PONG

exit
```

### 2. Monitor Redis Activity

```bash
# Open Redis CLI
redis-cli

# Monitor all commands in real-time
MONITOR

# In another terminal, load a page in your app
# You should see Redis commands scrolling
```

### 3. Check Redis Stats

```bash
redis-cli INFO
```

Key sections to check:
- `connected_clients`: Should show 1-2+ connections
- `used_memory_human`: Current memory usage
- `total_commands_processed`: Should increase with activity
- `keyspace_hits`/`keyspace_misses`: Cache hit rate

---

## Performance Tuning

### 1. Optimize PHP Redis Settings

Edit PHP configuration:
```bash
sudo nano /etc/php/8.2/fpm/php.ini
```

Add/modify:
```ini
; Redis Session Handler
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379?database=3"

; Enable OPcache for better PHP performance
opcache.enable=1
opcache.memory_consumption=256
opcache.max_accelerated_files=20000
```

Restart PHP-FPM:
```bash
sudo systemctl restart php8.2-fpm
```

### 2. Optimize Redis Performance

```bash
sudo nano /etc/redis/redis.conf
```

Performance settings:
```conf
# Disable slow operations
slowlog-log-slower-than 10000
slowlog-max-len 128

# Enable TCP keepalive
tcp-keepalive 300

# Set appropriate number of databases
databases 16

# Disable persistence if not needed (faster, but data loss on restart)
# save ""
# appendonly no
```

### 3. Enable Transparent Huge Pages (THP) Warning Fix

```bash
# Disable THP (Redis recommends this)
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Make permanent (add to /etc/rc.local or systemd)
sudo bash -c 'cat >> /etc/rc.local << EOF
# Disable THP for Redis
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF'
```

---

## Monitoring and Maintenance

### 1. Daily Monitoring Commands

```bash
# Check Redis status
sudo systemctl status redis-server

# Check memory usage
redis-cli INFO memory | grep used_memory_human

# Check connected clients
redis-cli INFO clients

# Check command statistics
redis-cli INFO stats

# Check cache hit rate
redis-cli INFO stats | grep keyspace
```

### 2. View Performance Logs

```bash
# Redis logs
sudo tail -f /var/log/redis/redis-server.log

# Laravel performance logs
tail -f /path/to/chom/storage/logs/performance.log

# Check for slow Redis queries
redis-cli SLOWLOG GET 10
```

### 3. Backup Redis Data (if persistence enabled)

```bash
# Manual backup
redis-cli SAVE
sudo cp /var/lib/redis/dump.rdb /backup/redis-backup-$(date +%Y%m%d).rdb

# Or use BGSAVE for background save (non-blocking)
redis-cli BGSAVE
```

---

## Troubleshooting

### Redis Not Starting

```bash
# Check logs
sudo journalctl -u redis-server -n 50

# Check configuration syntax
redis-server /etc/redis/redis.conf --test-memory 1

# Check file permissions
ls -la /var/lib/redis/
sudo chown redis:redis /var/lib/redis/
```

### Connection Refused

```bash
# Verify Redis is running
sudo systemctl status redis-server

# Check if Redis is listening
sudo netstat -tulpn | grep 6379

# Test connection
redis-cli ping

# Check Laravel can connect
php artisan tinker
Redis::connection()->ping();
```

### Out of Memory Errors

```bash
# Check current memory usage
redis-cli INFO memory

# Check max memory setting
redis-cli CONFIG GET maxmemory

# Increase max memory if needed
sudo nano /etc/redis/redis.conf
# Set: maxmemory 512mb

# Restart Redis
sudo systemctl restart redis-server
```

### Cache Not Working

```bash
# Clear Laravel cache
php artisan cache:clear
php artisan config:clear

# Verify CACHE_STORE in .env
grep CACHE_STORE .env

# Test cache manually
php artisan tinker
Cache::put('test', 'value', 60);
Cache::get('test');
```

---

## Monitoring Tools

### 1. Redis Commander (Web UI)

```bash
# Install globally
sudo npm install -g redis-commander

# Run (access at http://localhost:8081)
redis-commander
```

### 2. RedisInsight (Desktop App)

Download from: https://redis.com/redis-enterprise/redis-insight/

Features:
- Visual data browser
- Performance monitoring
- Memory analysis
- Query profiler

### 3. Custom Monitoring Script

Create `/usr/local/bin/redis-stats.sh`:
```bash
#!/bin/bash
echo "=== Redis Statistics ==="
echo "Memory: $(redis-cli INFO memory | grep used_memory_human)"
echo "Clients: $(redis-cli INFO clients | grep connected_clients)"
echo "Commands: $(redis-cli INFO stats | grep total_commands_processed)"
echo "Hit Rate: $(redis-cli INFO stats | grep keyspace_hits)"
echo ""
echo "=== Cache Keys ==="
redis-cli --scan --pattern "chom*" | head -20
```

Make executable:
```bash
sudo chmod +x /usr/local/bin/redis-stats.sh
```

---

## Production Checklist

- [ ] Redis installed and running
- [ ] phpredis extension installed
- [ ] Redis password set
- [ ] Redis bound to localhost only
- [ ] Dangerous commands disabled
- [ ] Max memory configured
- [ ] Laravel .env updated with Redis settings
- [ ] All caches cleared and recached
- [ ] Queue workers restarted
- [ ] Monitoring tools configured
- [ ] Backup strategy in place
- [ ] Performance logs being captured

---

## Performance Benchmarks

After Redis setup, verify performance improvements:

```bash
# Test dashboard load time (should be <100ms cached)
curl -w "@-" -o /dev/null -s "https://your-domain.com/dashboard" <<'EOF'
time_total:  %{time_total}s\n
EOF

# Check X-Response-Time header
curl -I https://your-domain.com/dashboard | grep X-Response-Time
```

Expected results:
- Dashboard: <100ms (cached)
- API responses: <50ms (cached)
- X-Response-Time header present on all responses

---

## Additional Resources

- Official Redis Documentation: https://redis.io/documentation
- Laravel Redis Documentation: https://laravel.com/docs/redis
- PHP Redis Extension: https://github.com/phpredis/phpredis
- Redis Performance Optimization: https://redis.io/topics/optimization

---

## Support

If you encounter issues:
1. Check Redis logs: `/var/log/redis/redis-server.log`
2. Check Laravel logs: `storage/logs/laravel.log`
3. Check PHP-FPM logs: `/var/log/php8.2-fpm.log`
4. Review performance logs: `storage/logs/performance.log`
