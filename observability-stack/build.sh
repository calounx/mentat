#!/bin/bash
#===============================================================================
# Observability Stack - Build Script
# Creates a self-contained, deployable package independent of the git repository
#===============================================================================

set -euo pipefail

# Build configuration
VERSION="${VERSION:-$(date +%Y%m%d-%H%M%S)}"
BUILD_DIR="build"
DIST_DIR="dist"
PACKAGE_NAME="observability-stack"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
INCLUDE_DOCS=false
COMPRESS_LEVEL=9

while [[ $# -gt 0 ]]; do
    case $1 in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --include-docs)
            INCLUDE_DOCS=true
            shift
            ;;
        --fast)
            COMPRESS_LEVEL=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --version VERSION    Set package version (default: timestamp)"
            echo "  --include-docs       Include documentation in package"
            echo "  --fast               Fast compression (larger file)"
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_info "Building Observability Stack v${VERSION}"

# Clean previous builds
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}" "$DIST_DIR"

#===============================================================================
# Copy core files
#===============================================================================

log_info "Copying core files..."

# Scripts
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/scripts/lib"
cp -a scripts/*.sh "$BUILD_DIR/${PACKAGE_NAME}/scripts/" 2>/dev/null || true
cp -a scripts/lib/*.sh "$BUILD_DIR/${PACKAGE_NAME}/scripts/lib/"

# Modules
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/modules/_core"
for module in modules/_core/*/; do
    module_name=$(basename "$module")
    mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/modules/_core/${module_name}"
    cp -a "$module"/*.sh "$BUILD_DIR/${PACKAGE_NAME}/modules/_core/${module_name}/" 2>/dev/null || true
    cp -a "$module"/*.yaml "$BUILD_DIR/${PACKAGE_NAME}/modules/_core/${module_name}/" 2>/dev/null || true
    cp -a "$module"/*.json "$BUILD_DIR/${PACKAGE_NAME}/modules/_core/${module_name}/" 2>/dev/null || true
done

# Configuration
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/config"
cp -a config/*.yaml "$BUILD_DIR/${PACKAGE_NAME}/config/"

# Grafana provisioning
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/grafana"
cp -a grafana/* "$BUILD_DIR/${PACKAGE_NAME}/grafana/"

# Loki configuration
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/loki"
cp -a loki/*.yaml "$BUILD_DIR/${PACKAGE_NAME}/loki/"

# Prometheus configuration (if exists)
if [[ -d "prometheus" ]]; then
    mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/prometheus"
    cp -a prometheus/*.yaml "$BUILD_DIR/${PACKAGE_NAME}/prometheus/" 2>/dev/null || true
    cp -a prometheus/*.yml "$BUILD_DIR/${PACKAGE_NAME}/prometheus/" 2>/dev/null || true
fi

# Alertmanager configuration (if exists)
if [[ -d "alertmanager" ]]; then
    mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/alertmanager"
    cp -a alertmanager/*.yaml "$BUILD_DIR/${PACKAGE_NAME}/alertmanager/" 2>/dev/null || true
    cp -a alertmanager/*.yml "$BUILD_DIR/${PACKAGE_NAME}/alertmanager/" 2>/dev/null || true
fi

# Tests (optional, for validation)
mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/tests"
cp -a tests/*.sh "$BUILD_DIR/${PACKAGE_NAME}/tests/" 2>/dev/null || true

#===============================================================================
# Create standalone installer
#===============================================================================

log_info "Creating standalone installer..."

cat > "$BUILD_DIR/${PACKAGE_NAME}/install.sh" << 'INSTALLER_EOF'
#!/bin/bash
#===============================================================================
# Observability Stack - Standalone Installer
# This installer works independently without requiring the git repository
#===============================================================================

set -euo pipefail

# Installer configuration
INSTALL_BASE="/opt/observability-stack"
CONFIG_DIR="/etc/observability-stack"
DATA_DIR="/var/lib/observability-stack"
LOG_DIR="/var/log/observability-stack"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get installer directory (works whether extracted or run from package)
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#===============================================================================
# Parse arguments
#===============================================================================

INSTALL_MODE="full"
FORCE_MODE=false
DRY_RUN=false
COMPONENTS=""

print_usage() {
    cat << EOF
Observability Stack Installer

Usage: $0 [OPTIONS] [COMPONENTS...]

Options:
  --full              Full installation (default)
  --upgrade           Upgrade existing installation
  --components LIST   Install specific components (comma-separated)
  --force             Force reinstall even if already installed
  --dry-run           Show what would be done without making changes
  --uninstall         Remove the observability stack
  -h, --help          Show this help

Components:
  prometheus          Prometheus metrics server
  loki                Loki log aggregation
  promtail            Promtail log collector
  grafana             Grafana visualization
  alertmanager        Alertmanager for alerts
  node_exporter       Node metrics exporter
  nginx_exporter      Nginx metrics exporter
  mysqld_exporter     MySQL metrics exporter
  phpfpm_exporter     PHP-FPM metrics exporter
  fail2ban_exporter   Fail2ban metrics exporter

Examples:
  $0                              # Full installation
  $0 --components prometheus,grafana  # Install specific components
  $0 --upgrade                    # Upgrade existing installation
  $0 --dry-run                    # Preview installation
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            INSTALL_MODE="full"
            shift
            ;;
        --upgrade)
            INSTALL_MODE="upgrade"
            shift
            ;;
        --components)
            COMPONENTS="$2"
            INSTALL_MODE="components"
            shift 2
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --uninstall)
            INSTALL_MODE="uninstall"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

#===============================================================================
# Pre-flight checks
#===============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This installer must be run as root"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    source /etc/os-release

    case "$ID" in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            PKG_MANAGER="yum"
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            fi
            ;;
        *)
            log_warn "Unsupported OS: $ID. Proceeding with caution."
            PKG_MANAGER="apt-get"
            ;;
    esac

    log_info "Detected OS: $PRETTY_NAME (Package manager: $PKG_MANAGER)"
}

check_dependencies() {
    local missing=()

    for cmd in curl wget tar systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Install them with: $PKG_MANAGER install ${missing[*]}"
        exit 1
    fi
}

#===============================================================================
# Installation functions
#===============================================================================

create_directories() {
    log_info "Creating directories..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create: $INSTALL_BASE $CONFIG_DIR $DATA_DIR $LOG_DIR"
        return
    fi

    mkdir -p "$INSTALL_BASE"/{scripts,modules,config}
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"/{prometheus,loki,grafana,backups}
    mkdir -p "$LOG_DIR"
}

copy_files() {
    log_info "Copying files to $INSTALL_BASE..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would copy files from $INSTALLER_DIR to $INSTALL_BASE"
        return
    fi

    # Copy scripts
    cp -a "$INSTALLER_DIR/scripts/"* "$INSTALL_BASE/scripts/"

    # Copy modules
    cp -a "$INSTALLER_DIR/modules/"* "$INSTALL_BASE/modules/"

    # Copy config templates
    cp -a "$INSTALLER_DIR/config/"* "$INSTALL_BASE/config/"

    # Copy Grafana provisioning
    if [[ -d "$INSTALLER_DIR/grafana" ]]; then
        cp -a "$INSTALLER_DIR/grafana" "$INSTALL_BASE/"
    fi

    # Copy Loki config
    if [[ -d "$INSTALLER_DIR/loki" ]]; then
        cp -a "$INSTALLER_DIR/loki" "$INSTALL_BASE/"
    fi

    # Set permissions
    chmod -R 755 "$INSTALL_BASE/scripts"
    chmod -R 755 "$INSTALL_BASE/modules"
    find "$INSTALL_BASE/modules" -name "*.sh" -exec chmod +x {} \;
}

create_symlinks() {
    log_info "Creating management symlinks..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create symlink: /usr/local/bin/obs-ctl"
        return
    fi

    # Create main CLI tool
    cat > /usr/local/bin/obs-ctl << 'EOF'
#!/bin/bash
# Observability Stack CLI
INSTALL_BASE="/opt/observability-stack"
exec "$INSTALL_BASE/scripts/obs-ctl.sh" "$@"
EOF
    chmod +x /usr/local/bin/obs-ctl
}

install_component() {
    local component="$1"
    local module_dir="$INSTALL_BASE/modules/_core/$component"

    if [[ ! -d "$module_dir" ]]; then
        log_warn "Component not found: $component"
        return 1
    fi

    if [[ ! -x "$module_dir/install.sh" ]]; then
        log_warn "No install script for: $component"
        return 1
    fi

    log_info "Installing component: $component"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $module_dir/install.sh"
        return 0
    fi

    # Source common functions
    source "$INSTALL_BASE/scripts/lib/common.sh"

    # Run component installer
    if ! "$module_dir/install.sh"; then
        log_error "Failed to install: $component"
        return 1
    fi

    log_success "Installed: $component"
}

run_setup() {
    log_info "Running main setup..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: $INSTALL_BASE/scripts/setup-observability.sh"
        return 0
    fi

    if [[ -x "$INSTALL_BASE/scripts/setup-observability.sh" ]]; then
        cd "$INSTALL_BASE"
        export BASE_DIR="$INSTALL_BASE"
        ./scripts/setup-observability.sh
    else
        log_error "Setup script not found"
        return 1
    fi
}

#===============================================================================
# Uninstall
#===============================================================================

uninstall() {
    log_warn "This will remove the Observability Stack installation"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would stop services and remove files"
        return 0
    fi

    read -p "Are you sure? This will NOT remove data. [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Uninstall cancelled"
        exit 0
    fi

    # Stop services
    for svc in prometheus alertmanager loki promtail grafana-server \
               node_exporter nginx_exporter mysqld_exporter phpfpm_exporter fail2ban_exporter; do
        systemctl stop "$svc" 2>/dev/null || true
        systemctl disable "$svc" 2>/dev/null || true
    done

    # Remove installation directory
    rm -rf "$INSTALL_BASE"
    rm -f /usr/local/bin/obs-ctl

    log_success "Uninstalled. Data preserved in $DATA_DIR"
    log_info "To remove data: rm -rf $DATA_DIR"
}

#===============================================================================
# Main
#===============================================================================

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         Observability Stack Installer                     ║"
    echo "║         Independent Deployment Package                    ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    check_os
    check_dependencies

    case "$INSTALL_MODE" in
        full)
            log_info "Starting full installation..."
            create_directories
            copy_files
            create_symlinks
            run_setup
            ;;
        upgrade)
            log_info "Starting upgrade..."
            copy_files
            if [[ -x "$INSTALL_BASE/scripts/upgrade-orchestrator.sh" ]]; then
                "$INSTALL_BASE/scripts/upgrade-orchestrator.sh" --all --mode standard
            fi
            ;;
        components)
            log_info "Installing components: $COMPONENTS"
            create_directories
            copy_files
            create_symlinks
            IFS=',' read -ra COMP_ARRAY <<< "$COMPONENTS"
            for comp in "${COMP_ARRAY[@]}"; do
                install_component "$comp"
            done
            ;;
        uninstall)
            uninstall
            ;;
    esac

    if [[ "$DRY_RUN" != "true" && "$INSTALL_MODE" != "uninstall" ]]; then
        echo ""
        log_success "Installation complete!"
        echo ""
        echo "Next steps:"
        echo "  1. Edit configuration: $CONFIG_DIR/"
        echo "  2. Check status: obs-ctl status"
        echo "  3. Access Grafana: https://your-domain:3000"
        echo ""
    fi
}

main "$@"
INSTALLER_EOF

chmod +x "$BUILD_DIR/${PACKAGE_NAME}/install.sh"

#===============================================================================
# Create CLI tool
#===============================================================================

log_info "Creating CLI management tool..."

cat > "$BUILD_DIR/${PACKAGE_NAME}/scripts/obs-ctl.sh" << 'CLI_EOF'
#!/bin/bash
#===============================================================================
# obs-ctl - Observability Stack CLI Management Tool
#===============================================================================

set -euo pipefail

INSTALL_BASE="${INSTALL_BASE:-/opt/observability-stack}"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_usage() {
    cat << EOF
obs-ctl - Observability Stack Management CLI v${VERSION}

Usage: obs-ctl <command> [options]

Commands:
  status              Show status of all services
  start [service]     Start all or specific service
  stop [service]      Stop all or specific service
  restart [service]   Restart all or specific service
  logs [service]      Show logs for service
  upgrade             Run upgrade orchestrator
  health              Run health checks
  backup              Create backup of data
  validate            Validate configuration
  version             Show version information

Options:
  -h, --help          Show this help

Examples:
  obs-ctl status                  # Show all service status
  obs-ctl restart prometheus      # Restart Prometheus
  obs-ctl logs loki -f            # Follow Loki logs
  obs-ctl upgrade --dry-run       # Preview upgrades
EOF
}

cmd_status() {
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                 Observability Stack Status                 ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    local services=(
        "prometheus:9090"
        "alertmanager:9093"
        "loki:3100"
        "promtail:9080"
        "grafana-server:3000"
        "node_exporter:9100"
        "nginx_exporter:9113"
    )

    printf "%-20s %-12s %-10s %s\n" "SERVICE" "STATUS" "PORT" "HEALTH"
    printf "%-20s %-12s %-10s %s\n" "-------" "------" "----" "------"

    for svc_port in "${services[@]}"; do
        local svc="${svc_port%%:*}"
        local port="${svc_port##*:}"
        local status
        local health

        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            status="${GREEN}running${NC}"
            if curl -sf --max-time 2 "http://localhost:$port/-/healthy" &>/dev/null || \
               curl -sf --max-time 2 "http://localhost:$port/ready" &>/dev/null || \
               curl -sf --max-time 2 "http://localhost:$port/metrics" &>/dev/null; then
                health="${GREEN}healthy${NC}"
            else
                health="${YELLOW}unknown${NC}"
            fi
        else
            status="${RED}stopped${NC}"
            health="${RED}N/A${NC}"
        fi

        printf "%-20s %-22b %-10s %b\n" "$svc" "$status" "$port" "$health"
    done
    echo ""
}

cmd_start() {
    local service="${1:-all}"

    if [[ "$service" == "all" ]]; then
        local services=(prometheus alertmanager loki promtail grafana-server node_exporter)
        for svc in "${services[@]}"; do
            echo -e "${BLUE}Starting ${svc}...${NC}"
            systemctl start "$svc" 2>/dev/null || true
        done
    else
        echo -e "${BLUE}Starting ${service}...${NC}"
        systemctl start "$service"
    fi

    echo -e "${GREEN}Done${NC}"
}

cmd_stop() {
    local service="${1:-all}"

    if [[ "$service" == "all" ]]; then
        local services=(node_exporter promtail loki alertmanager prometheus grafana-server)
        for svc in "${services[@]}"; do
            echo -e "${YELLOW}Stopping ${svc}...${NC}"
            systemctl stop "$svc" 2>/dev/null || true
        done
    else
        echo -e "${YELLOW}Stopping ${service}...${NC}"
        systemctl stop "$service"
    fi

    echo -e "${GREEN}Done${NC}"
}

cmd_restart() {
    local service="${1:-all}"
    cmd_stop "$service"
    sleep 2
    cmd_start "$service"
}

cmd_logs() {
    local service="${1:-prometheus}"
    shift || true
    journalctl -u "$service" "$@"
}

cmd_upgrade() {
    if [[ -x "$INSTALL_BASE/scripts/upgrade-orchestrator.sh" ]]; then
        "$INSTALL_BASE/scripts/upgrade-orchestrator.sh" "$@"
    else
        echo -e "${RED}Upgrade orchestrator not found${NC}"
        exit 1
    fi
}

cmd_health() {
    if [[ -x "$INSTALL_BASE/scripts/health-check.sh" ]]; then
        "$INSTALL_BASE/scripts/health-check.sh" "$@"
    else
        # Basic health check
        cmd_status
    fi
}

cmd_backup() {
    local backup_dir="/var/lib/observability-stack/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    echo -e "${BLUE}Creating backup in ${backup_dir}...${NC}"

    # Prometheus snapshot
    if curl -sf -X POST "http://localhost:9090/api/v1/admin/tsdb/snapshot" &>/dev/null; then
        echo -e "${GREEN}Prometheus snapshot created${NC}"
    fi

    # Config backup
    cp -a /etc/prometheus "$backup_dir/" 2>/dev/null || true
    cp -a /etc/loki "$backup_dir/" 2>/dev/null || true
    cp -a /etc/grafana "$backup_dir/" 2>/dev/null || true

    echo -e "${GREEN}Backup complete: ${backup_dir}${NC}"
}

cmd_validate() {
    echo -e "${BLUE}Validating configuration...${NC}"

    local errors=0

    # Prometheus config
    if command -v promtool &>/dev/null; then
        if promtool check config /etc/prometheus/prometheus.yml 2>/dev/null; then
            echo -e "${GREEN}✓ Prometheus config valid${NC}"
        else
            echo -e "${RED}✗ Prometheus config invalid${NC}"
            ((errors++))
        fi
    fi

    # Alertmanager config
    if command -v amtool &>/dev/null; then
        if amtool check-config /etc/alertmanager/alertmanager.yml 2>/dev/null; then
            echo -e "${GREEN}✓ Alertmanager config valid${NC}"
        else
            echo -e "${RED}✗ Alertmanager config invalid${NC}"
            ((errors++))
        fi
    fi

    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}All configurations valid${NC}"
    else
        echo -e "${RED}Found $errors configuration errors${NC}"
        exit 1
    fi
}

cmd_version() {
    echo "obs-ctl version ${VERSION}"
    echo ""
    echo "Component versions:"
    prometheus --version 2>/dev/null | head -1 || echo "prometheus: not installed"
    loki --version 2>/dev/null | head -1 || echo "loki: not installed"
    promtail --version 2>/dev/null | head -1 || echo "promtail: not installed"
    grafana-cli --version 2>/dev/null || echo "grafana: not installed"
}

# Main
case "${1:-}" in
    status)
        cmd_status
        ;;
    start)
        shift
        cmd_start "$@"
        ;;
    stop)
        shift
        cmd_stop "$@"
        ;;
    restart)
        shift
        cmd_restart "$@"
        ;;
    logs)
        shift
        cmd_logs "$@"
        ;;
    upgrade)
        shift
        cmd_upgrade "$@"
        ;;
    health)
        shift
        cmd_health "$@"
        ;;
    backup)
        shift
        cmd_backup "$@"
        ;;
    validate)
        shift
        cmd_validate "$@"
        ;;
    version|--version|-v)
        cmd_version
        ;;
    -h|--help|help|"")
        print_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        print_usage
        exit 1
        ;;
esac
CLI_EOF

chmod +x "$BUILD_DIR/${PACKAGE_NAME}/scripts/obs-ctl.sh"

#===============================================================================
# Create version file
#===============================================================================

cat > "$BUILD_DIR/${PACKAGE_NAME}/VERSION" << EOF
VERSION=${VERSION}
BUILD_DATE=$(date -Iseconds)
BUILD_HOST=$(hostname)
EOF

#===============================================================================
# Include documentation if requested
#===============================================================================

if [[ "$INCLUDE_DOCS" == "true" ]]; then
    log_info "Including documentation..."
    mkdir -p "$BUILD_DIR/${PACKAGE_NAME}/docs"
    cp -a docs/*.md "$BUILD_DIR/${PACKAGE_NAME}/docs/" 2>/dev/null || true
    cp README.md "$BUILD_DIR/${PACKAGE_NAME}/" 2>/dev/null || true
fi

#===============================================================================
# Create README for package
#===============================================================================

cat > "$BUILD_DIR/${PACKAGE_NAME}/README.md" << 'README_EOF'
# Observability Stack - Standalone Package

This is a self-contained deployment package that works independently without requiring the git repository.

## Quick Start

```bash
# Extract the package
tar -xzf observability-stack-VERSION.tar.gz
cd observability-stack

# Run the installer (as root)
sudo ./install.sh

# Check status
obs-ctl status
```

## Installation Options

```bash
# Full installation (default)
sudo ./install.sh

# Install specific components only
sudo ./install.sh --components prometheus,grafana,loki

# Dry run (preview what would be installed)
sudo ./install.sh --dry-run

# Upgrade existing installation
sudo ./install.sh --upgrade
```

## Management Commands

After installation, use the `obs-ctl` command:

```bash
obs-ctl status              # Show service status
obs-ctl start               # Start all services
obs-ctl stop                # Stop all services
obs-ctl restart prometheus  # Restart specific service
obs-ctl logs loki -f        # View logs
obs-ctl upgrade             # Run upgrades
obs-ctl backup              # Create backup
obs-ctl validate            # Validate configuration
```

## Directory Structure

After installation:
- `/opt/observability-stack/` - Installation directory
- `/etc/observability-stack/` - Configuration
- `/var/lib/observability-stack/` - Data storage
- `/var/log/observability-stack/` - Logs

## Uninstall

```bash
sudo ./install.sh --uninstall
```

Note: Uninstall preserves data. To remove data:
```bash
sudo rm -rf /var/lib/observability-stack
```
README_EOF

#===============================================================================
# Create the tarball
#===============================================================================

log_info "Creating distribution package..."

cd "$BUILD_DIR"
tar -czf "../$DIST_DIR/${PACKAGE_NAME}-${VERSION}.tar.gz" \
    --owner=0 --group=0 \
    "${PACKAGE_NAME}"

# Calculate checksum
cd "../$DIST_DIR"
sha256sum "${PACKAGE_NAME}-${VERSION}.tar.gz" > "${PACKAGE_NAME}-${VERSION}.tar.gz.sha256"

#===============================================================================
# Summary
#===============================================================================

PACKAGE_SIZE=$(du -h "${PACKAGE_NAME}-${VERSION}.tar.gz" | cut -f1)

echo ""
log_success "Build complete!"
echo ""
echo "Package created:"
echo "  ${DIST_DIR}/${PACKAGE_NAME}-${VERSION}.tar.gz ($PACKAGE_SIZE)"
echo "  ${DIST_DIR}/${PACKAGE_NAME}-${VERSION}.tar.gz.sha256"
echo ""
echo "To deploy on a server:"
echo "  1. Copy the tarball to the target server"
echo "  2. Extract: tar -xzf ${PACKAGE_NAME}-${VERSION}.tar.gz"
echo "  3. Install: cd ${PACKAGE_NAME} && sudo ./install.sh"
echo ""
