#!/bin/bash
#===============================================================================
# Quick Exporter Health Check
#===============================================================================
# Fast health check wrapper for integration with monitoring systems
# Returns 0 if all exporters are healthy, non-zero otherwise
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run quick scan
"${SCRIPT_DIR}/troubleshoot-exporters.sh" \
    --quick \
    --output text \
    "$@"

exit $?
