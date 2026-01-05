#!/bin/bash
#
# Fix Loki permission issues on mentat
#

set -euo pipefail

echo "Fixing Loki configuration and permissions..."

# Stop Loki service
echo "Stopping Loki service..."
sudo systemctl stop loki

# Fix Loki config - ensure correct paths
echo "Updating Loki configuration..."
sudo tee /etc/observability/loki/loki-config.yml > /dev/null <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /var/lib/observability/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/observability/loki/chunks
      rules_directory: /var/lib/observability/loki/rules
  replication_factor: 1
  ring:
    instance_addr: 127.0.0.1
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  retention_period: 720h
  allow_structured_metadata: true
  ingestion_rate_mb: 10
  ingestion_burst_size_mb: 20

compactor:
  working_directory: /var/lib/observability/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: filesystem

ruler:
  storage:
    type: local
    local:
      directory: /var/lib/observability/loki/rules
EOF

# Ensure all directories exist with correct permissions
echo "Creating Loki directories..."
sudo mkdir -p /var/lib/observability/loki/{chunks,rules,compactor}
sudo mkdir -p /etc/observability/loki

# Set correct ownership
echo "Setting ownership..."
sudo chown -R observability:observability /var/lib/observability/loki
sudo chown -R observability:observability /etc/observability/loki

# Restart Loki
echo "Starting Loki service..."
sudo systemctl start loki

# Wait and check status
sleep 3
if systemctl is-active --quiet loki; then
    echo "✅ Loki is running!"
    sudo systemctl status loki --no-pager -l
else
    echo "❌ Loki failed to start. Checking logs..."
    sudo journalctl -u loki -n 50 --no-pager
    exit 1
fi

# Verify Loki is listening on port 3100
echo ""
echo "Checking if Loki is listening on port 3100..."
if netstat -tulpn 2>/dev/null | grep -q ":3100"; then
    echo "✅ Loki is listening on port 3100"
else
    echo "⚠️  Loki is not listening on port 3100 yet - may need more time"
fi
