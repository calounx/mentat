#!/bin/bash

###############################################################################
# CHOM Deployment History Viewer
# Shows deployment history with timestamps, commits, and status
###############################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# Configuration
DEPLOY_USER="stilgar"
APP_SERVER="landsraad.arewel.com"
RELEASES_DIR="/var/www/chom/releases"
DEPLOY_LOG_DIR="/var/www/chom/.deploy-state"
MAX_DEPLOYMENTS=20

echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║            CHOM Deployment History                            ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Get current release
current_release=$(ssh "$DEPLOY_USER@$APP_SERVER" "readlink -f /var/www/chom/current 2>/dev/null | xargs basename" 2>/dev/null || echo "unknown")
echo -e "${CYAN}Current Release:${NC} ${BOLD}$current_release${NC}"
echo ""

# List all releases
echo -e "${BOLD}${CYAN}━━━ Deployment History ━━━${NC}"
echo ""

# Get releases sorted by date
releases=$(ssh "$DEPLOY_USER@$APP_SERVER" "ls -1t $RELEASES_DIR 2>/dev/null" || echo "")

if [[ -z "$releases" ]]; then
    echo -e "${YELLOW}No deployment history found${NC}"
    exit 0
fi

count=0
while IFS= read -r release; do
    ((count++))

    if [[ "$count" -gt "$MAX_DEPLOYMENTS" ]]; then
        break
    fi

    # Parse release directory name (format: YYYYMMDD_HHMMSS)
    release_date=$(echo "$release" | cut -d'_' -f1)
    release_time=$(echo "$release" | cut -d'_' -f2)

    # Format date and time
    if [[ ${#release_date} -eq 8 ]]; then
        formatted_date="${release_date:0:4}-${release_date:4:2}-${release_date:6:2}"
    else
        formatted_date="$release_date"
    fi

    if [[ ${#release_time} -eq 6 ]]; then
        formatted_time="${release_time:0:2}:${release_time:2:2}:${release_time:4:2}"
    else
        formatted_time="$release_time"
    fi

    # Check if this is the current release
    if [[ "$release" == "$current_release" ]]; then
        marker="${GREEN}→ [CURRENT]${NC}"
    else
        marker="  "
    fi

    # Try to get git commit SHA
    commit_sha=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $RELEASES_DIR/$release && git rev-parse --short HEAD 2>/dev/null" || echo "unknown")

    # Try to get commit message
    commit_msg=$(ssh "$DEPLOY_USER@$APP_SERVER" "cd $RELEASES_DIR/$release && git log -1 --pretty=%B 2>/dev/null | head -1 | cut -c1-60" || echo "")

    # Get release size
    release_size=$(ssh "$DEPLOY_USER@$APP_SERVER" "du -sh $RELEASES_DIR/$release 2>/dev/null | cut -f1" || echo "?")

    # Check for deployment log
    deploy_log="$DEPLOY_LOG_DIR/${release}.log"
    deploy_status="unknown"
    deploy_duration=""

    if ssh "$DEPLOY_USER@$APP_SERVER" "test -f $deploy_log" &>/dev/null; then
        if ssh "$DEPLOY_USER@$APP_SERVER" "grep -q 'SUCCESS' $deploy_log" &>/dev/null; then
            deploy_status="${GREEN}success${NC}"
        elif ssh "$DEPLOY_USER@$APP_SERVER" "grep -q 'FAILED' $deploy_log" &>/dev/null; then
            deploy_status="${RED}failed${NC}"
        fi

        # Try to extract duration
        duration_line=$(ssh "$DEPLOY_USER@$APP_SERVER" "grep 'Duration:' $deploy_log 2>/dev/null" || echo "")
        if [[ -n "$duration_line" ]]; then
            deploy_duration=$(echo "$duration_line" | grep -oP '\d+s' || echo "")
        fi
    fi

    # Print deployment info
    echo -e "${marker} ${BOLD}$release${NC}"
    echo -e "   Date:     $formatted_date $formatted_time"

    if [[ "$commit_sha" != "unknown" ]]; then
        echo -e "   Commit:   ${BLUE}$commit_sha${NC}"
    fi

    if [[ -n "$commit_msg" ]]; then
        echo -e "   Message:  ${DIM}$commit_msg${NC}"
    fi

    echo -e "   Size:     $release_size"

    if [[ "$deploy_status" != "unknown" ]]; then
        if [[ -n "$deploy_duration" ]]; then
            echo -e "   Status:   $deploy_status (${deploy_duration})"
        else
            echo -e "   Status:   $deploy_status"
        fi
    fi

    echo ""

done <<< "$releases"

# Show total number of deployments
total_releases=$(echo "$releases" | wc -l)
echo -e "${DIM}Total deployments: $total_releases${NC}"

if [[ "$total_releases" -gt "$MAX_DEPLOYMENTS" ]]; then
    echo -e "${DIM}Showing most recent $MAX_DEPLOYMENTS deployments${NC}"
fi

echo ""

# Deployment frequency analysis
echo -e "${BOLD}${CYAN}━━━ Deployment Statistics ━━━${NC}"
echo ""

# Count deployments in last 7 days
week_ago=$(date -d "7 days ago" +%Y%m%d)
deployments_this_week=0

while IFS= read -r release; do
    release_date=$(echo "$release" | cut -d'_' -f1)

    if [[ "$release_date" -ge "$week_ago" ]]; then
        ((deployments_this_week++))
    fi
done <<< "$releases"

echo -e "  Deployments (last 7 days):  ${BOLD}$deployments_this_week${NC}"

# Count deployments in last 30 days
month_ago=$(date -d "30 days ago" +%Y%m%d)
deployments_this_month=0

while IFS= read -r release; do
    release_date=$(echo "$release" | cut -d'_' -f1)

    if [[ "$release_date" -ge "$month_ago" ]]; then
        ((deployments_this_month++))
    fi
done <<< "$releases"

echo -e "  Deployments (last 30 days): ${BOLD}$deployments_this_month${NC}"

# Find most frequent deployer (if deployment logs contain user info)
echo ""

# Calculate average deployment frequency
if [[ "$deployments_this_month" -gt 0 ]]; then
    avg_per_week=$(awk "BEGIN {printf \"%.1f\", $deployments_this_month / 4.3}")
    echo -e "  Average frequency:          ${BOLD}${avg_per_week}${NC} deployments/week"
fi

echo ""

# Show rollback options
echo -e "${BOLD}${CYAN}━━━ Rollback Options ━━━${NC}"
echo ""

if [[ "$total_releases" -lt 2 ]]; then
    echo -e "${YELLOW}Only one release available - cannot rollback${NC}"
else
    previous_release=$(echo "$releases" | sed -n '2p')
    echo -e "To rollback to previous release (${BOLD}$previous_release${NC}):"
    echo -e "  ${DIM}ssh $DEPLOY_USER@$APP_SERVER 'sudo /path/to/rollback.sh'${NC}"
fi

echo ""
