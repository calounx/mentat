# 🚨 URGENT: Deploy Health Endpoint Fix Now

**Priority**: P2 HIGH
**Status**: Ready for Deployment
**Time Required**: 5 minutes

---

## Quick Deployment (Copy & Paste)

### Step 1: SSH to Production Server
```bash
ssh stilgar@landsraad.arewel.com
```

### Step 2: Deploy Fix (Run these commands in sequence)
```bash
# Navigate to application directory
cd /var/www/chom

# Pull latest changes
git pull origin main

# Clear all caches
php artisan route:clear && php artisan cache:clear && php artisan config:clear

# Verify route is registered
php artisan route:list --path=health
```

### Step 3: Test Endpoint
```bash
# Test from production server
curl https://chom.arewel.com/health

# Expected output:
# {"status":"healthy","timestamp":"2026-01-09T...","checks":{"database":true}}
```

### Step 4: Verify Monitoring (Wait 1-2 minutes)
```bash
# From your local machine or mentat server
curl -s https://chom.arewel.com/health

# Check Prometheus (optional)
# Navigate to: https://mentat.arewel.com/prometheus
# Query: probe_success{instance="https://chom.arewel.com/health"}
# Expected: Value = 1
```

---

## What This Fix Does

✅ Adds `/health` endpoint at root level
✅ Returns 200 OK when database is healthy
✅ Returns 503 when database is down
✅ No breaking changes
✅ No authentication required (for monitoring)

---

## Current Status

**Before Deployment:**
- ❌ https://chom.arewel.com/health returns 404
- ❌ Blackbox monitoring shows probe_success=0
- ❌ Unable to monitor application health

**After Deployment:**
- ✅ https://chom.arewel.com/health returns 200
- ✅ Blackbox monitoring shows probe_success=1
- ✅ Application health monitored correctly

---

## Rollback (If Needed)

```bash
cd /var/www/chom
git checkout HEAD~1 routes/web.php
php artisan route:clear && php artisan cache:clear
```

---

## Commits Deployed

1. `1581d1e` - fix: Add /health endpoint for blackbox monitoring
2. `91fc924` - docs: Add health endpoint deployment documentation

---

## Support

**Logs to check if issues occur:**
```bash
tail -f /var/www/chom/storage/logs/laravel.log
```

**Full Documentation:**
- Deployment Guide: `HEALTH-ENDPOINT-FIX-DEPLOYMENT.md`
- Implementation Report: `HEALTH-ENDPOINT-IMPLEMENTATION-REPORT.md`

---

**Deploy immediately to fix monitoring gaps!**
