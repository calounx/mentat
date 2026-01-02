# Incident Runbook: SSL Certificate Expiration

**Severity:** SEV1 (Critical) - if expired, SEV2 if expiring soon
**Impact:** HTTPS access broken, browser warnings
**Expected Resolution Time:** 10-30 minutes

## Detection
- Alert: `SSLCertificateExpiringSoon` (< 7 days)
- Alert: `SSLCertificateExpired`
- Browser certificate warnings
- Health check fails on HTTPS endpoint

## Quick Check
```bash
# Check certificate expiry
echo | openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com 2>/dev/null | openssl x_509 -noout -dates

# Check certbot status
ssh deploy@landsraad.arewel.com "certbot certificates"
```

## Resolution

### Renew Certificate
```bash
# 1. Stop nginx to free port 80
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml stop nginx
EOF

# 2. Renew certificate
ssh deploy@landsraad.arewel.com << 'EOF'
certbot renew --standalone --force-renewal
EOF

# 3. Copy new cert to Docker volume
ssh deploy@landsraad.arewel.com << 'EOF'
cp /etc/letsencrypt/live/landsraad.arewel.com/fullchain.pem /opt/chom/docker/production/ssl/
cp /etc/letsencrypt/live/landsraad.arewel.com/privkey.pem /opt/chom/docker/production/ssl/
EOF

# 4. Restart nginx
ssh deploy@landsraad.arewel.com << 'EOF'
docker compose -f /opt/chom/docker-compose.production.yml start nginx
EOF
```

### Verification
```bash
# Test HTTPS
curl -I https://landsraad.arewel.com
# Expected: HTTP/2 200

# Verify new expiry date
echo | openssl s_client -connect landsraad.arewel.com:443 -servername landsraad.arewel.com 2>/dev/null | openssl x509 -noout -dates
# Expected: > 80 days

# Test auto-renewal
ssh deploy@landsraad.arewel.com "certbot renew --dry-run"
```

## Prevention
- Auto-renewal cron: weekly
- Expiry monitoring: 30 days notice
- Test renewal: monthly
- Backup certificates

---

**Version:** 1.0 | **Updated:** 2026-01-02
