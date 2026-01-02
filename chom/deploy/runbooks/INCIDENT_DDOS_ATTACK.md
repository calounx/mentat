# Incident Runbook: DDoS Attack

**Severity:** SEV1 (Critical)
**Impact:** Service unavailable, legitimate users blocked
**Expected Resolution Time:** 15-60 minutes

## Detection
- Alert: `HighRequestRate` (> 1000 req/s)
- Alert: `HighBandwidth` (> 100 Mbps)
- High connection count from single IP/subnet
- Application unresponsive despite healthy infrastructure

## Quick Triage
```bash
# Check connection sources
ssh deploy@landsraad.arewel.com << 'EOF'
docker exec chom-nginx sh -c "netstat -ntu | awk '{print \$5}' | cut -d: -f1 | sort | uniq -c | sort -nr | head -20"
EOF

# Check request rate
ssh deploy@landsraad.arewel.com << 'EOF'
docker logs chom-nginx --tail 1000 | awk '{print $4}' | cut -d: -f1 | uniq -c
EOF

# Check current connections
ssh deploy@landsraad.arewel.com "docker exec chom-nginx sh -c 'ss -s'"
```

## Resolution

### Immediate Mitigation
```bash
# 1. Enable rate limiting in Nginx
ssh deploy@landsraad.arewel.com << 'EOF'
cat > /opt/chom/docker/nginx/rate-limit.conf << 'NGINX'
limit_req_zone $binary_remote_addr zone=one:10m rate=10r/s;
limit_req zone=one burst=20 nodelay;
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 10;
NGINX

docker compose -f /opt/chom/docker-compose.production.yml restart nginx
EOF

# 2. Block top attacking IPs
ssh deploy@landsraad.arewel.com << 'EOF'
ATTACK_IPS=$(docker logs chom-nginx --tail 10000 | awk '{print $1}' | sort | uniq -c | sort -nr | head -5 | awk '$1 > 100 {print $2}')

for IP in $ATTACK_IPS; do
  ufw deny from $IP
done

ufw reload
EOF
```

### Advanced Protection
```bash
# 3. Enable fail2ban for Nginx
ssh deploy@landsraad.arewel.com << 'EOF'
# Install if not present
apt-get install -y fail2ban

# Configure jail
cat > /etc/fail2ban/jail.d/nginx-ddos.conf << 'F2B'
[nginx-ddos]
enabled = true
filter = nginx-ddos
logpath = /var/log/nginx/access.log
maxretry = 100
findtime = 60
bantime = 3600
F2B

systemctl restart fail2ban
EOF

# 4. If severe, enable maintenance mode for non-essential paths
ssh deploy@landsraad.arewel.com << 'EOF'
cat > /opt/chom/docker/nginx/ddos-protection.conf << 'NGINX'
location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
    return 444;  # Drop connection without response
}
NGINX

docker compose -f /opt/chom/docker-compose.production.yml reload nginx
EOF
```

### Contact Upstream
```bash
# If attack overwhelming, contact OVH
# OVH Anti-DDoS: Automatic for most attacks
# Manual intervention: https://www.ovh.com/manager/
# Support: +33 9 72 10 10 07
```

## Verification
```bash
# Check request rate normalized
ssh deploy@landsraad.arewel.com "docker logs chom-nginx --tail 100 | wc -l"

# Check blocked IPs
ssh deploy@landsraad.arewel.com "ufw status | grep DENY | wc -l"

# Test legitimate access
curl -I https://landsraad.arewel.com
# Expected: HTTP/2 200

# Monitor metrics
curl -s http://51.254.139.78:9090/api/v1/query?query=rate(nginx_http_requests_total[5m])
```

## Post-Attack Cleanup
```bash
# 1. Review and unblock legitimate IPs
ssh deploy@landsraad.arewel.com << 'EOF'
ufw status numbered
# Manually review and delete rules: ufw delete [number]
EOF

# 2. Analyze attack pattern
ssh deploy@landsraad.arewel.com << 'EOF'
docker logs chom-nginx --since 1h > /tmp/attack-logs-$(date +%Y%m%d-%H%M%S).log
# Analyze for patterns, vectors, bot signatures
EOF

# 3. Keep rate limiting permanently
# Leave rate limit config in place with adjusted thresholds
```

## Prevention
- OVH Anti-DDoS enabled (default)
- Rate limiting configured
- Fail2ban installed and active
- CDN/WAF (consider Cloudflare)
- Bot detection rules
- Geographic blocking if appropriate

---

**Version:** 1.0 | **Updated:** 2026-01-02
