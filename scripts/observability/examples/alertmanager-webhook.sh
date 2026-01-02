#!/bin/bash
#===============================================================================
# Alertmanager Webhook Integration
#===============================================================================
# Example webhook handler for Alertmanager alerts
# Automatically troubleshoots and fixes exporter issues when alerts fire
#
# Configure in Alertmanager:
# receivers:
#   - name: 'exporter-auto-fix'
#     webhook_configs:
#       - url: 'http://localhost:8080/webhook'
#
# This script should be called by a webhook server that parses Alertmanager JSON
#===============================================================================

set -euo pipefail

SCRIPT_DIR="/home/calounx/repositories/mentat/scripts/observability"
LOG_DIR="/var/log/exporter-diagnostics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Parse arguments (would come from webhook server)
ALERT_NAME="${1:-ExporterDown}"
INSTANCE="${2:-localhost:9100}"
SERVICE="${3:-node_exporter}"

# Extract exporter name from service or instance
EXPORTER=$(echo "$SERVICE" | sed 's/_exporter$//')
if [[ "$SERVICE" != *"_exporter" ]]; then
    EXPORTER="${SERVICE}_exporter"
fi

echo "[$(date)] Alert received: ${ALERT_NAME} for ${INSTANCE} (${EXPORTER})" >> "${LOG_DIR}/alerts.log"

# Run targeted troubleshooting
"${SCRIPT_DIR}/troubleshoot-exporters.sh" \
    --exporter "$EXPORTER" \
    --apply-fix \
    --log "${LOG_DIR}/alert-fix-${EXPORTER}-${TIMESTAMP}.log" \
    >> "${LOG_DIR}/alerts.log" 2>&1

# Check if fix was successful
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "[$(date)] Successfully remediated ${EXPORTER}" >> "${LOG_DIR}/alerts.log"
    # Optional: Send success notification
    # notify-send "Exporter Fixed" "${EXPORTER} has been automatically remediated"
else
    echo "[$(date)] Failed to remediate ${EXPORTER}, manual intervention required" >> "${LOG_DIR}/alerts.log"
    # Optional: Escalate to on-call
    # mail -s "URGENT: Failed to auto-fix ${EXPORTER}" oncall@example.com < "${LOG_DIR}/alert-fix-${EXPORTER}-${TIMESTAMP}.log"
fi

exit $EXIT_CODE
