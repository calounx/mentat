#!/bin/bash
#
# Dashboard Validation Script
# Validates Grafana dashboard JSON files for common issues
#
# Usage: ./validate-dashboards.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS=(
    "sre-golden-signals.json"
    "devops-deployment.json"
    "infrastructure-health.json"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Grafana Dashboard Validation"
echo "=========================================="
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Install with: sudo apt-get install jq${NC}"
    echo "Skipping JSON validation..."
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

total_issues=0

# Validate each dashboard
for dashboard in "${DASHBOARDS[@]}"; do
    filepath="$SCRIPT_DIR/$dashboard"

    echo "Validating: $dashboard"
    echo "----------------------------------------"

    # Check if file exists
    if [ ! -f "$filepath" ]; then
        echo -e "${RED}✗ File not found: $filepath${NC}"
        ((total_issues++))
        continue
    fi

    echo -e "${GREEN}✓ File exists${NC}"

    # Check if file is not empty
    if [ ! -s "$filepath" ]; then
        echo -e "${RED}✗ File is empty${NC}"
        ((total_issues++))
        continue
    fi

    echo -e "${GREEN}✓ File is not empty${NC}"

    if [ "$JQ_AVAILABLE" = true ]; then
        # Validate JSON syntax
        if jq empty "$filepath" 2>/dev/null; then
            echo -e "${GREEN}✓ Valid JSON syntax${NC}"
        else
            echo -e "${RED}✗ Invalid JSON syntax${NC}"
            jq empty "$filepath" 2>&1 | head -n 5
            ((total_issues++))
            continue
        fi

        # Check required fields
        if jq -e '.title' "$filepath" > /dev/null 2>&1; then
            title=$(jq -r '.title' "$filepath")
            echo -e "${GREEN}✓ Has title: $title${NC}"
        else
            echo -e "${RED}✗ Missing title field${NC}"
            ((total_issues++))
        fi

        if jq -e '.uid' "$filepath" > /dev/null 2>&1; then
            uid=$(jq -r '.uid' "$filepath")
            echo -e "${GREEN}✓ Has UID: $uid${NC}"
        else
            echo -e "${YELLOW}⚠ Missing UID (will be auto-generated)${NC}"
        fi

        # Count panels
        panel_count=$(jq '[.panels[]? | select(.type != "row")] | length' "$filepath")
        row_count=$(jq '[.panels[]? | select(.type == "row")] | length' "$filepath")
        echo -e "${GREEN}✓ Contains $panel_count panels in $row_count rows${NC}"

        # Check for templating variables
        variable_count=$(jq '.templating.list | length' "$filepath")
        if [ "$variable_count" -gt 0 ]; then
            echo -e "${GREEN}✓ Has $variable_count template variables${NC}"
        else
            echo -e "${YELLOW}⚠ No template variables defined${NC}"
        fi

        # Check for annotations
        annotation_count=$(jq '.annotations.list | length' "$filepath")
        echo -e "${GREEN}✓ Has $annotation_count annotation sources${NC}"

        # Validate panel queries
        invalid_queries=0
        panels_with_targets=$(jq -r '.panels[]? | select(.targets) | .title' "$filepath" 2>/dev/null)
        while IFS= read -r panel_title; do
            if [ -n "$panel_title" ]; then
                # Check if panel has at least one target with expr
                has_expr=$(jq --arg title "$panel_title" '.panels[]? | select(.title == $title) | .targets[]? | select(.expr) | .expr' "$filepath" 2>/dev/null)
                if [ -z "$has_expr" ]; then
                    echo -e "${YELLOW}⚠ Panel '$panel_title' has no Prometheus query${NC}"
                    ((invalid_queries++))
                fi
            fi
        done <<< "$panels_with_targets"

        if [ $invalid_queries -eq 0 ]; then
            echo -e "${GREEN}✓ All panels have valid queries${NC}"
        else
            echo -e "${YELLOW}⚠ $invalid_queries panels may need query review${NC}"
        fi

        # Check time ranges
        time_from=$(jq -r '.time.from' "$filepath")
        time_to=$(jq -r '.time.to' "$filepath")
        echo -e "${GREEN}✓ Default time range: $time_from to $time_to${NC}"

        # Check refresh settings
        refresh=$(jq -r '.refresh // "not set"' "$filepath")
        echo -e "${GREEN}✓ Refresh interval: $refresh${NC}"

        # Check tags
        tags=$(jq -r '.tags | join(", ")' "$filepath")
        if [ -n "$tags" ] && [ "$tags" != "null" ]; then
            echo -e "${GREEN}✓ Tags: $tags${NC}"
        else
            echo -e "${YELLOW}⚠ No tags defined${NC}"
        fi

    else
        # Basic validation without jq
        if grep -q '"title"' "$filepath"; then
            echo -e "${GREEN}✓ Appears to have title field${NC}"
        else
            echo -e "${RED}✗ May be missing title field${NC}"
            ((total_issues++))
        fi

        if grep -q '"panels"' "$filepath"; then
            echo -e "${GREEN}✓ Appears to have panels${NC}"
        else
            echo -e "${RED}✗ May be missing panels${NC}"
            ((total_issues++))
        fi
    fi

    # Check file size
    filesize=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)
    if [ "$filesize" -gt 10240 ]; then  # > 10KB
        echo -e "${GREEN}✓ File size: $(numfmt --to=iec-i --suffix=B $filesize)${NC}"
    else
        echo -e "${YELLOW}⚠ File size seems small: $(numfmt --to=iec-i --suffix=B $filesize)${NC}"
    fi

    echo ""
done

# Summary
echo "=========================================="
echo "  Validation Summary"
echo "=========================================="
echo ""

if [ $total_issues -eq 0 ]; then
    echo -e "${GREEN}✓ All dashboards passed validation!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Import dashboards to Grafana"
    echo "  2. Configure Prometheus data source"
    echo "  3. Verify panels display data"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Found $total_issues critical issues${NC}"
    echo ""
    echo "Please fix the issues above before importing."
    echo ""
    exit 1
fi
