#!/bin/bash
#===============================================================================
# Multi-Host Deployment Example
#===============================================================================
# Example script for deploying and checking exporters across multiple hosts
#===============================================================================

set -euo pipefail

SCRIPT_DIR="/home/calounx/repositories/mentat/scripts/observability"

# Define host groups
WEB_HOSTS=("web1.example.com" "web2.example.com" "web3.example.com")
DB_HOSTS=("db1.example.com" "db2.example.com")
CACHE_HOSTS=("cache1.example.com" "cache2.example.com")

echo "=================================="
echo "Multi-Host Exporter Deployment"
echo "=================================="
echo ""

# Check web servers
echo "Checking web servers..."
"${SCRIPT_DIR}/troubleshoot-exporters.sh" \
    --multi-host \
    --remote "$(IFS=','; echo "${WEB_HOSTS[*]}")" \
    --parallel 8 \
    --apply-fix

echo ""

# Check database servers
echo "Checking database servers..."
"${SCRIPT_DIR}/troubleshoot-exporters.sh" \
    --multi-host \
    --remote "$(IFS=','; echo "${DB_HOSTS[*]}")" \
    --parallel 4 \
    --apply-fix

echo ""

# Check cache servers
echo "Checking cache servers..."
"${SCRIPT_DIR}/troubleshoot-exporters.sh" \
    --multi-host \
    --remote "$(IFS=','; echo "${CACHE_HOSTS[*]}")" \
    --parallel 4 \
    --apply-fix

echo ""
echo "Multi-host deployment check complete!"
