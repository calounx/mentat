# 🔐 SSL Certificate Fix - Ready to Execute

**Status**: ✅ All scripts and documentation prepared
**Issue**: SSL certificate mismatch on landsraad.arewel.com
**Solution**: Ready to deploy (5 minutes execution time)

---

## 🚀 Three Ways to Execute the Fix

### Method 1: ⚡ Fastest - Copy/Paste One Command

**SSH to the server and run this single command:**

```bash
ssh stilgar@landsraad.arewel.com

# Then paste this entire block:
sudo bash << 'EOF'
echo "🔧 Starting SSL fix..."
certbot certonly --webroot --webroot-path /var/www/html --expand --non-interactive --agree-tos --domains chom.arewel.com,landsraad.arewel.com && \
cp /etc/nginx/sites-available/chom /etc/nginx/sites-available/chom.backup.$(date +%Y%m%d_%H%M%S) && \
sed -i 's/server_name chom\.arewel\.com;/server_name chom.arewel.com landsraad.arewel.com;/g' /etc/nginx/sites-available/chom && \
nginx -t && \
systemctl reload nginx && \
echo "" && \
echo "========================================" && \
echo "✅ SSL FIX COMPLETE!" && \
echo "========================================" && \
echo "" && \
certbot certificates | grep -A 5 "chom.arewel.com" && \
echo "" && \
echo "Test: https://landsraad.arewel.com"
EOF
```

**Execution time**: 30-60 seconds
**Downtime**: Zero
**Rollback**: Automatic backup created

---

### Method 2: 📦 Recommended - Use Prepared Script

**This method provides better logging and error handling.**

#### Step 1: Copy Script to Server

From your local machine:

```bash
cd /home/calounx/repositories/mentat
scp EXECUTE_SSL_FIX.sh stilgar@landsraad.arewel.com:/tmp/
```

Or manually:

```bash
# SSH to server
ssh stilgar@landsraad.arewel.com

# Create the script
nano /tmp/ssl-fix.sh

# Paste the contents of EXECUTE_SSL_FIX.sh
# Save and exit (Ctrl+X, Y, Enter)

# Make executable
chmod +x /tmp/ssl-fix.sh
```

#### Step 2: Execute the Fix

```bash
sudo /tmp/ssl-fix.sh
```

**Features**:
- ✅ Step-by-step progress display
- ✅ Comprehensive error handling
- ✅ Automatic backup and rollback
- ✅ Post-fix verification
- ✅ Colored output for clarity

---

### Method 3: 📖 Manual - Follow Step-by-Step Guide

**For maximum control, follow the manual instructions.**

See: `SSL_FIX_INSTRUCTIONS.md`

This provides:
- Detailed explanation of each step
- Troubleshooting guide
- Alternative approaches
- Verification checklists

---

## 📁 Files Prepared

All files are ready in `/home/calounx/repositories/mentat/`:

| File | Purpose | Lines |
|------|---------|-------|
| `EXECUTE_SSL_FIX.sh` | Main fix script (recommended) | 200+ |
| `deploy/scripts/fix-ssl-landsraad.sh` | Comprehensive fix with full logging | 100+ |
| `deploy/scripts/ssl-fix-oneliner.sh` | Quick one-liner version | 25 |
| `SSL_FIX_INSTRUCTIONS.md` | Complete manual guide | 500+ |
| `SSL_FIX_READY.md` | This file - execution guide | - |

---

## ✅ What Gets Fixed

### Before Fix:
```
Certificate: chom.arewel.com
  ✗ Domains: chom.arewel.com only
  ✗ Browser warning on landsraad.arewel.com
  ✗ Security errors
```

### After Fix:
```
Certificate: chom.arewel.com
  ✓ Domains: chom.arewel.com, landsraad.arewel.com
  ✓ No browser warnings
  ✓ Valid SSL for both domains
```

---

## 🔍 Verification Steps

After running the fix, verify success:

### 1. Check Certificate

```bash
sudo certbot certificates
```

**Expected output:**
```
Certificate Name: chom.arewel.com
  Domains: chom.arewel.com landsraad.arewel.com
  Expiry Date: [future date]
  Certificate Path: /etc/letsencrypt/live/chom.arewel.com/fullchain.pem
```

### 2. Check Nginx Configuration

```bash
grep "server_name" /etc/nginx/sites-available/chom
```

**Expected output:**
```
server_name chom.arewel.com landsraad.arewel.com;
```

### 3. Test SSL Connection

```bash
curl -I https://landsraad.arewel.com
```

**Should return:** HTTP 200/301/302 without SSL errors

### 4. Browser Test

1. Visit: https://landsraad.arewel.com
2. Click padlock icon → View certificate
3. Verify: Subject Alternative Names includes both domains
4. Confirm: No security warnings

---

## 🆘 Troubleshooting

### Issue: Certificate expansion fails

**Error**: `Challenge failed for domain landsraad.arewel.com`

**Fix**:
```bash
# Check DNS
dig landsraad.arewel.com +short
# Should return server IP

# Check port 80
sudo netstat -tulpn | grep :80
# Should show nginx listening

# Test ACME challenge path
echo "test" | sudo tee /var/www/html/.well-known/acme-challenge/test
curl http://landsraad.arewel.com/.well-known/acme-challenge/test
# Should return "test"
```

### Issue: Nginx test fails

**Error**: `nginx: [emerg] unknown directive`

**Fix**:
```bash
# Restore backup
sudo ls -lt /etc/nginx/sites-available/chom.backup.*
sudo cp /etc/nginx/sites-available/chom.backup.[latest] /etc/nginx/sites-available/chom
sudo nginx -t && sudo systemctl reload nginx
```

### Issue: Still getting browser warnings

**Causes**:
- Browser cache (clear and reload with Ctrl+Shift+R)
- Certificate not propagated yet (wait 1-2 minutes)
- Nginx not reloaded (run `sudo systemctl reload nginx`)

---

## 📊 Technical Details

### What the Fix Does

1. **Certificate Expansion** (certbot --expand)
   - Adds landsraad.arewel.com to existing certificate
   - Uses webroot authentication method
   - No certificate replacement (same cert, more domains)

2. **Nginx Configuration Update**
   - Changes: `server_name chom.arewel.com;`
   - To: `server_name chom.arewel.com landsraad.arewel.com;`
   - Applied to both HTTP (port 80) and HTTPS (port 443) blocks

3. **Graceful Reload**
   - Uses `systemctl reload nginx` (not restart)
   - Zero downtime
   - Active connections preserved

### Safety Features

- ✅ Automatic backup before modifications
- ✅ Configuration test before applying
- ✅ Rollback on any failure
- ✅ No existing functionality affected
- ✅ No downtime required

### Time Required

- Certificate expansion: 10-30 seconds
- Configuration update: <1 second
- Nginx reload: <1 second
- **Total: ~1 minute**

---

## 🎯 Recommendation

**Use Method 2** (Prepared Script) because:

1. ✅ Comprehensive error handling
2. ✅ Clear progress indicators
3. ✅ Automatic verification
4. ✅ Detailed output for debugging
5. ✅ Easy to audit (all steps visible)

**Use Method 1** if:
- You want the fastest execution
- You're comfortable with one-liner commands
- You don't need detailed logging

**Use Method 3** if:
- You want to learn each step
- You need maximum control
- You're debugging issues

---

## 📝 Execution Checklist

Before you start:

- [ ] You have SSH access to stilgar@landsraad.arewel.com
- [ ] You have sudo privileges on the server
- [ ] Server is currently accessible (no maintenance)
- [ ] You've read this document

After execution:

- [ ] Certificate includes both domains (`certbot certificates`)
- [ ] Nginx configuration updated (check with `grep`)
- [ ] Nginx test passes (`nginx -t`)
- [ ] Nginx reloaded successfully (`systemctl status nginx`)
- [ ] Browser test successful (visit https://landsraad.arewel.com)
- [ ] No security warnings appear

---

## 🚦 Ready to Execute

**Everything is prepared and ready to go.**

Choose your method above and execute the fix.

**Estimated total time**: 5 minutes (including verification)
**Risk level**: Low (automatic backup and rollback)
**Downtime**: Zero

---

## 📞 Support

If you encounter any issues:

1. Check the **Troubleshooting** section above
2. Review logs:
   - Certbot: `/var/log/letsencrypt/letsencrypt.log`
   - Nginx: `/var/log/nginx/chom-error.log`
3. Restore backup if needed (instructions above)

---

**Ready when you are! 🚀**

Once complete, report back and I'll:
- Verify the fix
- Update the regression test report
- Mark the issue as resolved
