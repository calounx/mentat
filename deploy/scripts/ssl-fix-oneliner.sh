#!/bin/bash
# One-liner SSL fix for landsraad.arewel.com
# Run on the server as root: sudo bash ssl-fix-oneliner.sh

set -euo pipefail

echo "🔧 Fixing SSL certificate for landsraad.arewel.com..."
echo ""

# Expand certificate
echo "📜 Expanding certificate to include both domains..."
certbot certonly --webroot --webroot-path /var/www/html --expand --non-interactive --agree-tos --domains chom.arewel.com,landsraad.arewel.com

# Backup and update nginx config
echo "⚙️  Updating nginx configuration..."
cp /etc/nginx/sites-available/chom "/etc/nginx/sites-available/chom.backup.$(date +%Y%m%d_%H%M%S)"
sed -i 's/server_name chom\.arewel\.com;/server_name chom.arewel.com landsraad.arewel.com;/g' /etc/nginx/sites-available/chom

# Test and reload
echo "🧪 Testing nginx configuration..."
nginx -t && systemctl reload nginx

echo ""
echo "✅ SSL certificate fix complete!"
echo ""
echo "Certificate now includes:"
certbot certificates | grep -A 5 "chom.arewel.com"
echo ""
echo "Test in browser: https://landsraad.arewel.com"
