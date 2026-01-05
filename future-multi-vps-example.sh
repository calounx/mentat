#!/bin/bash
#
# Example: How deploy-chom-automated.sh would look with multiple VPS
#

# Define all application VPS servers
declare -A VPS_HOSTS=(
    [landsraad]="landsraad.arewel.com"
    [vps3]="vps3.arewel.com"
    [vps4]="vps4.arewel.com"
    [vps5]="vps5.arewel.com"
)

# Deploy to all VPS in parallel or sequentially
for vps_name in "${!VPS_HOSTS[@]}"; do
    vps_host="${VPS_HOSTS[$vps_name]}"

    echo "Deploying to $vps_name ($vps_host)..."

    # 1. Copy scripts to VPS
    sudo -u stilgar scp deploy/scripts/* stilgar@${vps_host}:/tmp/chom-deploy/scripts/

    # 2. Run deployment on VPS
    sudo -u stilgar ssh stilgar@${vps_host} "cd /tmp/chom-deploy && sudo bash scripts/deploy-exporters.sh"

    # 3. Retrieve targets back to mentat
    sudo -u stilgar scp stilgar@${vps_host}:/tmp/prometheus_targets/*.yml /tmp/
    sudo mv /tmp/*.yml /etc/observability/prometheus/targets/

    echo "✓ $vps_name deployed"
done

# Prometheus auto-discovers all targets within 30 seconds
