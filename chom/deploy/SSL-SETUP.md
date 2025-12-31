# SSL/HTTPS Setup Guide

> **Important:** Run this AFTER successful deployment to enable HTTPS

---

## Why HTTPS is Not Enabled by Default

SSL certificates from Let's Encrypt require:
1. Domain DNS must point to the server IP (can't verify until domains are configured)
2. Domain ownership verification via HTTP challenge
3. Interactive email input for certificate notifications

Since these can't be automated in the initial deployment, HTTPS setup is a separate post-deployment step.

---

## Prerequisites

Before running SSL setup:

- ✅ **Deployment completed successfully**
- ✅ **DNS configured:** Your domain(s) must point to server IP
- ✅ **Ports open:** 80 and 443 must be accessible
- ✅ **Email:** You need an email for Let's Encrypt notifications

### Check DNS Resolution

```bash
# Check if domain resolves to your server
dig +short mentat.arewel.com

# Should return your server IP (51.254.139.78)
```

### Check Ports

```bash
# Check firewall
sudo ufw status

# Should show:
# 80/tcp     ALLOW
# 443/tcp    ALLOW
```

---

## Quick SSL Setup

### Option 1: Interactive Script (Recommended)

```bash
# SSH to your observability server
ssh calounx@51.254.139.78

# Run SSL setup
cd /tmp
bash /path/to/setup-ssl.sh
```

**You'll be prompted for:**
- Domain name for Grafana (e.g., `mentat.arewel.com`)
- Email address for Let's Encrypt notifications

### Option 2: Manual Certbot

```bash
# SSH to server
ssh calounx@51.254.139.78

# Stop nginx
sudo systemctl stop nginx

# Get certificate
sudo certbot certonly --standalone \
  --agree-tos \
  --email your-email@example.com \
  -d mentat.arewel.com

# Update nginx config (see below)
# ...

# Start nginx
sudo systemctl start nginx
```

---

## What the Script Does

1. **Validates DNS** - Checks domain points to server
2. **Obtains Certificate** - Uses Let's Encrypt certbot
3. **Updates Nginx** - Configures HTTPS with security headers
4. **HTTP → HTTPS Redirect** - All HTTP traffic redirects to HTTPS
5. **Auto-renewal** - Sets up certbot timer for automatic renewal
6. **Updates Grafana** - Sets correct root_url for HTTPS

---

## Manual Nginx HTTPS Configuration

If you prefer to configure manually, here's the nginx config:

```nginx
# HTTP - Redirect to HTTPS
server {
    listen 80;
    server_name mentat.arewel.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS - Grafana
server {
    listen 443 ssl http2;
    server_name mentat.arewel.com;

    ssl_certificate /etc/letsencrypt/live/mentat.arewel.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mentat.arewel.com/privkey.pem;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

---

## Verification

### Test HTTPS is Working

```bash
# Test from your machine
curl -I https://mentat.arewel.com

# Should return:
# HTTP/2 200
# server: nginx
# strict-transport-security: max-age=31536000; includeSubDomains
```

### Check Certificate

```bash
# On server
sudo certbot certificates

# Shows:
# - Certificate Name
# - Domains
# - Expiry Date
# - Certificate Path
```

### Test Auto-Renewal

```bash
# Dry run (doesn't actually renew)
sudo certbot renew --dry-run

# Should say: "Congratulations, all simulated renewals succeeded"
```

---

## Certificate Renewal

Certificates are valid for 90 days and renew automatically.

### Check Renewal Timer

```bash
# Check timer status
sudo systemctl status certbot.timer

# Should show: active (waiting)
```

### Manual Renewal

```bash
# Force renewal (if within 30 days of expiry)
sudo certbot renew

# Force renewal (even if not close to expiry)
sudo certbot renew --force-renewal
```

### Renewal Hooks

After renewal, nginx needs to reload:

```bash
# Add renewal hook
sudo sh -c 'echo "systemctl reload nginx" > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh'
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

---

## Troubleshooting

### Domain Doesn't Resolve

```bash
# Check DNS
dig +short mentat.arewel.com

# If empty or wrong IP:
# 1. Update DNS A record to point to 51.254.139.78
# 2. Wait for DNS propagation (can take up to 48h, usually minutes)
```

### Certbot Fails

```bash
# Check nginx is stopped
sudo systemctl status nginx

# Check port 80 is not in use
sudo netstat -tlnp | grep :80

# Try with verbose logging
sudo certbot certonly --standalone -d mentat.arewel.com -v
```

### Certificate Already Exists

```bash
# List certificates
sudo certbot certificates

# Delete old certificate
sudo certbot delete --cert-name mentat.arewel.com

# Get new one
sudo certbot certonly --standalone -d mentat.arewel.com
```

### HTTPS Not Working After Setup

```bash
# Check nginx config
sudo nginx -t

# Check certificate files exist
ls -la /etc/letsencrypt/live/mentat.arewel.com/

# Check nginx is running
sudo systemctl status nginx

# Check logs
sudo tail -f /var/log/nginx/error.log
```

---

## Security Best Practices

### Force HTTPS

The script already redirects HTTP → HTTPS, but you can also:

```nginx
# Add to Grafana server block
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

### Disable HTTP Completely (Optional)

```bash
# Only allow HTTPS (after testing HTTPS works!)
sudo ufw delete allow 80/tcp
```

### Monitor Certificate Expiry

```bash
# Check expiry
sudo certbot certificates | grep "Expiry Date"

# Set up monitoring alert (e.g., in Prometheus)
# Alert if certificate expires in < 30 days
```

---

## Multiple Domains

If you have multiple services (Grafana, VPSManager, etc.):

### Option 1: Separate Certificates

```bash
# Get cert for each domain
sudo certbot certonly --standalone -d mentat.arewel.com
sudo certbot certonly --standalone -d landsraad.arewel.com
```

### Option 2: Multi-Domain Certificate

```bash
# Single cert for multiple domains
sudo certbot certonly --standalone \
  -d mentat.arewel.com \
  -d landsraad.arewel.com
```

---

## Quick Reference

```bash
# Get certificate
sudo certbot certonly --standalone -d yourdomain.com

# List certificates
sudo certbot certificates

# Renew (dry run)
sudo certbot renew --dry-run

# Force renew
sudo certbot renew --force-renewal

# Delete certificate
sudo certbot delete --cert-name yourdomain.com

# Check timer
sudo systemctl status certbot.timer

# Test HTTPS
curl -I https://yourdomain.com
```

---

## Summary

1. **Deploy infrastructure** (HTTP only)
2. **Configure DNS** to point to server
3. **Run SSL setup** script or certbot manually
4. **Test HTTPS** works
5. **Verify auto-renewal** is enabled

**Estimated Time:** 5 minutes (once DNS is configured)
