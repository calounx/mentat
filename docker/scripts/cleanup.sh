#!/usr/bin/env bash
# ============================================================================
# Cleanup Script - Remove CHOM Docker Environment
# ============================================================================
# This script removes all containers, volumes, and networks
# WARNING: This will delete all data! Use with caution.
# ============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo -e "${RED}========================================${NC}"
echo -e "${RED}CHOM Docker Environment - CLEANUP${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will remove all containers, volumes, and data!${NC}"
echo -e "${YELLOW}This action cannot be undone.${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo -e "${GREEN}Cleanup cancelled.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}1. Stopping all containers...${NC}"
docker compose down

echo ""
echo -e "${BLUE}2. Removing volumes...${NC}"
docker compose down -v

echo ""
echo -e "${BLUE}3. Removing orphaned containers...${NC}"
docker compose down --remove-orphans

echo ""
echo -e "${BLUE}4. Pruning unused networks...${NC}"
docker network prune -f

echo ""
echo -e "${BLUE}5. Removing dangling images...${NC}"
docker image prune -f

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To start fresh:"
echo "  ./scripts/setup.sh"
