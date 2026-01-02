#!/usr/bin/env bash
# ============================================================================
# Backup Script - Backup CHOM Docker Environment Data
# ============================================================================
# This script creates backups of all persistent volumes
# ============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${PROJECT_ROOT}/backups"

cd "$PROJECT_ROOT"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Timestamp for backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/chom_backup_${TIMESTAMP}.tar.gz"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}CHOM Docker Environment - Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${BLUE}Creating backup: ${BACKUP_FILE}${NC}"
echo ""

# Stop containers (optional - comment out to backup while running)
# echo "Stopping containers for consistent backup..."
# docker compose stop

echo "Backing up volumes..."

# Create temporary directory for volume exports
TMP_DIR=$(mktemp -d)

# Backup each volume
VOLUMES=(
    "mysql-data"
    "redis-data"
    "app-storage"
    "prometheus-data"
    "loki-data"
    "grafana-data"
)

for volume in "${VOLUMES[@]}"; do
    volume_name="docker_${volume}"
    echo -n "  - Backing up ${volume}... "

    # Export volume to tar
    docker run --rm \
        -v "${volume_name}:/data" \
        -v "${TMP_DIR}:/backup" \
        debian:12-slim \
        tar czf "/backup/${volume}.tar.gz" -C /data . 2>/dev/null

    echo -e "${GREEN}✓${NC}"
done

# Create final archive
echo ""
echo "Creating final backup archive..."
tar czf "${BACKUP_FILE}" -C "${TMP_DIR}" . 2>/dev/null

# Cleanup
rm -rf "${TMP_DIR}"

# Start containers if stopped
# docker compose start

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Backup saved to: ${BACKUP_FILE}"
echo "Backup size: $(du -h "${BACKUP_FILE}" | cut -f1)"
echo ""
echo "To restore from backup:"
echo "  ./scripts/restore.sh ${BACKUP_FILE}"
