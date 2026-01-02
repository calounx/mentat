#!/bin/bash
#===============================================================================
# Cron Integration Example
#===============================================================================
# Example cron job wrapper for automated exporter monitoring and remediation
#
# Add to crontab:
# */5 * * * * /home/calounx/repositories/mentat/scripts/observability/examples/cron-integration.sh
#===============================================================================

set -euo pipefail

SCRIPT_DIR="/home/calounx/repositories/mentat/scripts/observability"
LOG_DIR="/var/log/exporter-diagnostics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Run quick check
"${SCRIPT_DIR}/quick-check.sh" --log "${LOG_DIR}/quick-check-${TIMESTAMP}.log" > /dev/null 2>&1
EXIT_CODE=$?

# If issues detected, run deep diagnostics and attempt fixes
if [[ $EXIT_CODE -ne 0 ]]; then
    echo "[$(date)] Issues detected, running deep diagnostics..." >> "${LOG_DIR}/remediation.log"

    "${SCRIPT_DIR}/troubleshoot-exporters.sh" \
        --deep \
        --apply-fix \
        --log "${LOG_DIR}/auto-fix-${TIMESTAMP}.log" \
        >> "${LOG_DIR}/remediation.log" 2>&1

    # Optional: Send alert if fixes were applied
    # mail -s "Exporter Auto-Remediation Applied" admin@example.com < "${LOG_DIR}/auto-fix-${TIMESTAMP}.log"
fi

# Cleanup old logs (keep last 7 days)
find "${LOG_DIR}" -name "*.log" -mtime +7 -delete

exit 0
