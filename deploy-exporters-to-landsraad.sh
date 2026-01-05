#!/bin/bash
#
# Deploy exporters to landsraad - RUN FROM MENTAT
#

set -euo pipefail

DEPLOY_USER="stilgar"
LANDSRAAD_HOST="landsraad.arewel.com"

# Get the real user who invoked sudo
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Use the real user's chom-deployment directory
SCRIPT_DIR="${REAL_HOME}/chom-deployment"

echo "Deploying exporters to landsraad from mentat..."
echo "Using deployment directory: $SCRIPT_DIR"
echo ""

# Verify the script exists
if [[ ! -f "${SCRIPT_DIR}/deploy/scripts/deploy-exporters.sh" ]]; then
    echo "ERROR: deploy-exporters.sh not found at ${SCRIPT_DIR}/deploy/scripts/deploy-exporters.sh"
    exit 1
fi

# Copy deploy-exporters.sh to landsraad
echo "Copying deploy-exporters.sh to landsraad..."
sudo -u "$DEPLOY_USER" scp "${SCRIPT_DIR}/deploy/scripts/deploy-exporters.sh" \
    "$DEPLOY_USER@$LANDSRAAD_HOST:/tmp/deploy-exporters.sh"

# Make it executable
echo "Making script executable..."
sudo -u "$DEPLOY_USER" ssh "$DEPLOY_USER@$LANDSRAAD_HOST" \
    "chmod +x /tmp/deploy-exporters.sh"

# Run it
echo ""
echo "Running deploy-exporters.sh on landsraad..."
echo ""
sudo -u "$DEPLOY_USER" ssh "$DEPLOY_USER@$LANDSRAAD_HOST" \
    "sudo bash /tmp/deploy-exporters.sh"

echo ""
echo "✅ Exporter deployment complete!"
echo ""
echo "Verifying exporters are running on landsraad..."
sudo -u "$DEPLOY_USER" ssh "$DEPLOY_USER@$LANDSRAAD_HOST" \
    "sudo netstat -tulpn | grep LISTEN | grep -E '9100|9187|9121|9253|9113|9115|9080'"

echo ""
echo "Checking Prometheus targets on mentat..."
sleep 5  # Give Prometheus time to discover new targets
curl -s "http://localhost:9090/prometheus/api/v1/targets" | jq -r '.data.activeTargets[] | select(.labels.host=="landsraad") | "\(.labels.job): \(.health)"' | sort -u

echo ""
echo "Done! Check Grafana dashboards: https://mentat.arewel.com"
