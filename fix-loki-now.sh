#!/bin/bash
#
# Quick fix for Loki on current mentat deployment
# Creates missing directories and restarts Loki
#

set -euo pipefail

echo "Fixing Loki directories and permissions..."

# Stop Loki
echo "Stopping Loki..."
sudo systemctl stop loki

# Create all required directories
echo "Creating Loki directories..."
sudo mkdir -p /var/lib/observability/loki/{chunks,rules,compactor,rules-temp}
sudo mkdir -p /etc/observability/loki

# Set correct ownership
echo "Setting ownership..."
sudo chown -R observability:observability /var/lib/observability/loki
sudo chown -R observability:observability /etc/observability/loki

# Restart Loki
echo "Starting Loki..."
sudo systemctl start loki

# Wait and check
sleep 3

if systemctl is-active --quiet loki; then
    echo ""
    echo "✅ Loki is now running!"
    sudo systemctl status loki --no-pager -l | head -20
else
    echo ""
    echo "❌ Loki failed to start. Check logs:"
    sudo journalctl -u loki -n 30 --no-pager
    exit 1
fi

echo ""
echo "Verify Loki is responding:"
curl -s http://localhost:3100/ready && echo " ✅ Loki is ready" || echo " ⚠️  Loki not ready yet"
