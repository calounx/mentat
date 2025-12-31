#!/bin/bash

# Manual Composer Security Audit Script
# Run this script to check for security vulnerabilities in dependencies

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "  COMPOSER SECURITY AUDIT"
echo "========================================="
echo ""

cd "$PROJECT_ROOT"

# Check if composer is installed
if ! command -v composer &> /dev/null; then
    echo -e "${RED}✗ Composer not found${NC}"
    exit 1
fi

# Run composer audit
echo "Running composer audit..."
echo ""

if composer audit --format=json > composer-audit.json 2>&1; then
    echo -e "${GREEN}✓ No vulnerabilities found!${NC}"
    VULN_COUNT=0
else
    # Parse results
    if [ -f composer-audit.json ]; then
        VULN_COUNT=$(jq '.advisories | length' composer-audit.json 2>/dev/null || echo "0")

        if [ "$VULN_COUNT" -gt 0 ]; then
            echo -e "${RED}✗ Found $VULN_COUNT vulnerable package(s)${NC}"
            echo ""
            echo "Vulnerability details:"
            echo ""

            # Display vulnerabilities
            jq -r '.advisories[] | "Package: \(.packageName)\nVersion: \(.affectedVersions)\nCVE: \(.cve // "N/A")\nTitle: \(.title)\nSeverity: \(.severity)\nFix: Update to \(.sources[0].remoteId // "latest")\n---"' composer-audit.json 2>/dev/null || cat composer-audit.json

            echo ""
            echo -e "${YELLOW}Run 'composer update' to fix vulnerabilities${NC}"
        else
            echo -e "${GREEN}✓ No vulnerabilities found!${NC}"
        fi
    fi
fi

# Check for outdated packages
echo ""
echo "Checking for outdated packages..."
echo ""

composer outdated --direct 2>/dev/null || echo "No outdated direct dependencies"

# Cleanup
rm -f composer-audit.json

echo ""
echo "========================================="
echo "  AUDIT COMPLETE"
echo "========================================="

if [ "$VULN_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0
