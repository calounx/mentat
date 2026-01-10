# SSL Certificate Fix for landsraad.arewel.com

**Issue**: SSL certificate is issued for `chom.arewel.com` but site is accessed via `landsraad.arewel.com`
**Impact**: Browser security warnings on landsraad.arewel.com
**Solution**: Expand certificate to include both domains
**Time Required**: 5-10 minutes

---

## Quick Fix (Automated)

I've created an automated script that will fix the SSL certificate issue.

### Step 1: Connect to Server

```bash
ssh stilgar@landsraad.arewel.com
```

### Step 2: Download and Run Fix Script

```bash
# Switch to root
sudo -i

# Download the fix script from your local repository
# (You'll need to scp it first or paste the content)

# Option A: If you have the script on your local machine
# From your local machine, run:
scp /home/calounx/repositories/mentat/deploy/scripts/fix-ssl-landsraad.sh stilgar@landsraad.arewel.com:/tmp/

# Then on the server:
sudo bash /tmp/fix-ssl-landsraad.sh
```

### Step 3: Verify Fix

```bash
# Check certificate includes both domains
sudo certbot certificates

# Test HTTPS access
curl -I https://landsraad.arewel.com

# Verify in browser
# Visit https://landsraad.arewel.com and check certificate
```

---

## Manual Fix (Step by Step)

If you prefer to do it manually or the script fails, follow these steps:

### Step 1: Connect to Server

```bash
ssh stilgar@landsraad.arewel.com
sudo -i
```

### Step 2: Check Current Certificate

```bash
# View current certificates
certbot certificates

# Should show:
#   Certificate Name: chom.arewel.com
#     Domains: chom.arewel.com
```

### Step 3: Expand Certificate to Include Both Domains

```bash
# Expand the certificate to include landsraad.arewel.com
certbot certonly \
    --webroot \
    --webroot-path /var/www/html \
    --expand \
    --non-interactive \
    --agree-tos \
    --domains chom.arewel.com,landsraad.arewel.com
```

**Expected Output**:
```
Saving debug log to /var/log/letsencrypt/letsencrypt.log
Renewing an existing certificate for chom.arewel.com and landsraad.arewel.com

Successfully received certificate.
Certificate is saved at: /etc/letsencrypt/live/chom.arewel.com/fullchain.pem
Key is saved at: /etc/letsencrypt/live/chom.arewel.com/privkey.pem
```

### Step 4: Verify Certificate Expansion

```bash
# Confirm certificate now includes both domains
certbot certificates

# Should now show:
#   Certificate Name: chom.arewel.com
#     Domains: chom.arewel.com landsraad.arewel.com
```

### Step 5: Update Nginx Configuration

```bash
# Backup current configuration
cp /etc/nginx/sites-available/chom /etc/nginx/sites-available/chom.backup.$(date +%Y%m%d_%H%M%S)

# Edit nginx configuration
nano /etc/nginx/sites-available/chom
```

**Find and replace** (two occurrences):

```nginx
# OLD (line ~14 and ~33):
server_name chom.arewel.com;

# NEW:
server_name chom.arewel.com landsraad.arewel.com;
```

**Or use sed to automate**:

```bash
sed -i 's/server_name chom\.arewel\.com;/server_name chom.arewel.com landsraad.arewel.com;/g' /etc/nginx/sites-available/chom
```

### Step 6: Verify Changes

```bash
# Check the nginx configuration was updated correctly
grep "server_name" /etc/nginx/sites-available/chom

# Should show:
#   server_name chom.arewel.com landsraad.arewel.com;
#   (appears twice - once in HTTP block, once in HTTPS block)
```

### Step 7: Test Nginx Configuration

```bash
# Test nginx configuration syntax
nginx -t

# Expected output:
#   nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
#   nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### Step 8: Reload Nginx

```bash
# Reload nginx to apply changes
systemctl reload nginx

# Check nginx status
systemctl status nginx
```

### Step 9: Verify SSL Certificate

```bash
# Test SSL connection for chom.arewel.com
echo "" | openssl s_client -connect chom.arewel.com:443 -servername chom.arewel.com 2>/dev/null | grep -E "subject=|issuer=|CN"

# Test SSL connection for landsraad.arewel.com
echo "" | openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com 2>/dev/null | grep -E "subject=|issuer=|CN"

# Test with curl
curl -I https://chom.arewel.com
curl -I https://landsraad.arewel.com

# Both should return HTTP 200/301/302 without SSL errors
```

---

## Verification Checklist

After completing the fix, verify:

- [ ] Certificate includes both domains (`certbot certificates`)
- [ ] Nginx configuration updated (`grep server_name /etc/nginx/sites-available/chom`)
- [ ] Nginx test passes (`nginx -t`)
- [ ] Nginx reloaded successfully (`systemctl status nginx`)
- [ ] HTTPS works for chom.arewel.com (no warnings)
- [ ] HTTPS works for landsraad.arewel.com (no warnings)
- [ ] Browser shows valid certificate for both domains

---

## Testing in Browser

1. **Visit https://landsraad.arewel.com**
2. **Click the padlock icon** in the address bar
3. **View certificate details**
4. **Verify**:
   - Certificate is valid
   - Issued by Let's Encrypt
   - Subject Alternative Names includes both:
     - chom.arewel.com
     - landsraad.arewel.com
   - No security warnings

---

## Troubleshooting

### Issue: Certificate expansion fails

**Error**: `Challenge failed for domain landsraad.arewel.com`

**Solutions**:

1. **Check DNS**:
   ```bash
   dig landsraad.arewel.com +short
   # Should return the server's IP address
   ```

2. **Check port 80 accessibility**:
   ```bash
   curl -I http://landsraad.arewel.com/.well-known/acme-challenge/test
   # Should NOT be blocked by firewall
   ```

3. **Check nginx is serving .well-known**:
   ```bash
   # Create test file
   mkdir -p /var/www/html/.well-known/acme-challenge/
   echo "test" > /var/www/html/.well-known/acme-challenge/test

   # Test access
   curl http://landsraad.arewel.com/.well-known/acme-challenge/test
   # Should return "test"
   ```

### Issue: Nginx test fails

**Error**: `nginx: [emerg] unknown directive`

**Solutions**:

1. **Check syntax carefully**:
   ```bash
   nginx -t
   # Read the error message carefully
   ```

2. **Restore backup**:
   ```bash
   # Find latest backup
   ls -lt /etc/nginx/sites-available/chom.backup.*

   # Restore
   cp /etc/nginx/sites-available/chom.backup.YYYYMMDD_HHMMSS /etc/nginx/sites-available/chom
   ```

### Issue: Browser still shows warning

**Possible causes**:

1. **Browser cache**: Clear browser cache and reload (Ctrl+Shift+R)
2. **Certificate not updated**: Wait 1-2 minutes for certificate propagation
3. **Nginx not reloaded**: Run `sudo systemctl reload nginx` again
4. **Wrong certificate served**: Check `openssl s_client` output

---

## Alternative Approach: Redirect

If you prefer to redirect landsraad.arewel.com to chom.arewel.com instead:

### Step 1: Get Certificate for landsraad.arewel.com

```bash
sudo certbot certonly \
    --webroot \
    --webroot-path /var/www/html \
    --email admin@arewel.com \
    --agree-tos \
    --no-eff-email \
    --domain landsraad.arewel.com \
    --non-interactive
```

### Step 2: Create Redirect Configuration

```bash
sudo nano /etc/nginx/sites-available/landsraad-redirect
```

**Content**:

```nginx
# Redirect landsraad.arewel.com to chom.arewel.com

# HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name landsraad.arewel.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://chom.arewel.com$request_uri;
    }
}

# HTTPS redirect
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name landsraad.arewel.com;

    ssl_certificate /etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/landsraad.arewel.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    return 301 https://chom.arewel.com$request_uri;
}
```

### Step 3: Enable and Test

```bash
# Enable configuration
sudo ln -s /etc/nginx/sites-available/landsraad-redirect /etc/nginx/sites-enabled/

# Test
sudo nginx -t

# Reload
sudo systemctl reload nginx

# Test redirect
curl -I https://landsraad.arewel.com
# Should show: Location: https://chom.arewel.com/
```

---

## Recommendation

**I recommend the first approach** (expanding the certificate) because:

- ✅ Both domains work equally
- ✅ Single certificate to manage
- ✅ No redirects (faster for users)
- ✅ Preserves URL in browser (better UX)
- ✅ Easier maintenance

The redirect approach is useful if you want to standardize on one domain name.

---

## After Fix Complete

Once the SSL certificate is fixed:

1. **Test in browser**:
   - Visit https://landsraad.arewel.com
   - Verify no security warnings
   - Check certificate details

2. **Update documentation**:
   - Note that both domains are valid
   - Update any hardcoded URLs if needed

3. **Monitor certificate expiration**:
   ```bash
   sudo certbot certificates
   # Note expiration date (auto-renewal is configured)
   ```

4. **Mark as resolved** in regression report

---

## Summary

**What this fix does**:
- Adds `landsraad.arewel.com` to the existing SSL certificate
- Updates nginx to serve both domains
- Eliminates browser security warnings

**Time**: 5-10 minutes
**Risk**: Low (backup created, easy to rollback)
**Downtime**: None (reload, not restart)

---

**Questions or issues? Check the troubleshooting section above or contact DevOps.**
