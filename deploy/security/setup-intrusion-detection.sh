#!/bin/bash
# ============================================================================
# Intrusion Detection Setup Script (AIDE)
# ============================================================================
# Purpose: Configure Advanced Intrusion Detection Environment
# Features: File integrity monitoring, baseline creation, automated checks
# Compliance: PCI DSS 11.5, SOC 2, ISO 27001
# ============================================================================

set -euo pipefail
# Dependency validation - MUST run before doing anything else
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local security_dir="${deploy_root}/security"
    if [[ ! -d "$security_dir" ]]; then
        errors+=("Security directory not found: $security_dir")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "" >&2
        echo "ERROR: Missing required dependencies for ${script_name}" >&2
        echo "" >&2
        echo "Script location: ${script_dir}" >&2
        echo "Deploy root: ${deploy_root}" >&2
        echo "" >&2
        echo "Missing dependencies:" >&2
        for error in "${errors[@]}"; do
            echo "  - ${error}" >&2
        done
        echo "" >&2
        echo "Run from repository root: sudo ./deploy/security/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"

# Configuration
AIDE_CONF="/etc/aide/aide.conf"
AIDE_DB="/var/lib/aide/aide.db"
AIDE_DB_NEW="/var/lib/aide/aide.db.new"
AIDE_LOG="/var/log/aide/aide.log"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@arewel.com}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Install AIDE
install_aide() {
    log_info "Installing AIDE..."

    apt-get update -qq
    apt-get install -y aide aide-common

    log_success "AIDE installed"
}

# Configure AIDE
configure_aide() {
    log_info "Configuring AIDE..."

    # Backup original configuration
    if [[ -f "$AIDE_CONF" ]]; then
        cp "$AIDE_CONF" "${AIDE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # Create custom AIDE configuration
    cat > "$AIDE_CONF" <<'EOF'
# ============================================================================
# CHOM AIDE Configuration
# Advanced Intrusion Detection Environment
# ============================================================================

# Database location
database=file:/var/lib/aide/aide.db
database_out=file:/var/lib/aide/aide.db.new
database_new=file:/var/lib/aide/aide.db.new

# Report settings
report_url=file:/var/log/aide/aide.log
report_url=stdout
gzip_dbout=yes

# Rule definitions
# p:  permissions
# i:  inode
# n:  number of links
# u:  user
# g:  group
# s:  size
# m:  mtime
# a:  atime
# c:  ctime
# S:  check for growing size
# md5: md5 checksum
# sha256: sha256 checksum

# Custom rules
Binlib = p+i+n+u+g+s+b+m+c+md5+sha256
ConfFiles = p+i+n+u+g+s+b+m+c+md5+sha256
Logs = p+i+n+u+g+S
Databases = p+i+n+u+g+s+m+c+md5+sha256
StaticDir = p+i+n+u+g
DataDir = p+i+n+u+g+s+m+c+md5+sha256

# ============================================================================
# Directories to Monitor
# ============================================================================

# System binaries and libraries
/bin Binlib
/sbin Binlib
/usr/bin Binlib
/usr/sbin Binlib
/lib Binlib
/lib64 Binlib
/usr/lib Binlib
/usr/lib64 Binlib

# Boot files
/boot Binlib

# System configuration
/etc ConfFiles

# SSH configuration (critical)
!/etc/ssh/ssh_host_.*_key$
/etc/ssh ConfFiles

# Nginx configuration
/etc/nginx ConfFiles

# PHP configuration
/etc/php ConfFiles

# PostgreSQL configuration
/etc/postgresql ConfFiles

# Systemd services
/etc/systemd ConfFiles

# Cron jobs
/etc/cron.d ConfFiles
/etc/cron.daily ConfFiles
/etc/cron.hourly ConfFiles
/etc/cron.monthly ConfFiles
/etc/cron.weekly ConfFiles
/var/spool/cron/crontabs ConfFiles

# Application directory
/var/www/chom/app DataDir
/var/www/chom/config ConfFiles
/var/www/chom/database DataDir
/var/www/chom/routes ConfFiles
/var/www/chom/.env ConfFiles

# Security configurations
/etc/fail2ban ConfFiles
/etc/aide ConfFiles

# Exclude patterns
!/var/www/chom/storage
!/var/www/chom/bootstrap/cache
!/var/log
!/tmp
!/var/tmp
!/proc
!/sys
!/dev
!/run
!/var/run
!/var/cache
!/var/lib/aide/aide.db
!/var/lib/aide/aide.db.new
!/\.git$
!/node_modules

EOF

    log_success "AIDE configuration created"
}

# Initialize AIDE database
initialize_database() {
    log_info "Initializing AIDE database (this may take several minutes)..."

    # Create log directory
    mkdir -p "$(dirname "$AIDE_LOG")"
    chmod 750 "$(dirname "$AIDE_LOG")"

    # Initialize database
    aideinit

    # Move new database to active
    if [[ -f "$AIDE_DB_NEW" ]]; then
        mv "$AIDE_DB_NEW" "$AIDE_DB"
        log_success "AIDE database initialized"
    else
        log_error "Failed to initialize AIDE database"
        return 1
    fi
}

# Create daily check script
create_daily_check() {
    log_info "Creating daily AIDE check script..."

    cat > /usr/local/bin/aide-check <<'EOF'
#!/bin/bash
# AIDE Daily Integrity Check

AIDE_LOG="/var/log/aide/aide_check_$(date +%Y%m%d).log"
ADMIN_EMAIL="@ADMIN_EMAIL@"

# Run AIDE check
aide --check > "$AIDE_LOG" 2>&1
AIDE_STATUS=$?

# Parse results
if [[ $AIDE_STATUS -eq 0 ]]; then
    # No changes detected
    exit 0
elif [[ $AIDE_STATUS -eq 1 ]]; then
    # Changes detected - send alert
    {
        echo "SECURITY ALERT: File System Changes Detected"
        echo "=============================================="
        echo ""
        echo "Server: $(hostname)"
        echo "Date: $(date)"
        echo ""
        echo "AIDE has detected unauthorized file system changes."
        echo "This may indicate a security breach or system compromise."
        echo ""
        echo "Details:"
        echo "--------"
        cat "$AIDE_LOG"
    } | mail -s "[SECURITY ALERT] AIDE detected changes on $(hostname)" "$ADMIN_EMAIL"

    exit 1
else
    # Error occurred
    echo "AIDE check failed with status $AIDE_STATUS" | mail -s "[ERROR] AIDE check failed on $(hostname)" "$ADMIN_EMAIL"
    exit 2
fi
EOF

    # Replace email placeholder
    sed -i "s/@ADMIN_EMAIL@/$ADMIN_EMAIL/" /usr/local/bin/aide-check

    chmod +x /usr/local/bin/aide-check

    log_success "Daily check script created"
}

# Setup automated checks
setup_automated_checks() {
    log_info "Setting up automated AIDE checks..."

    # Create systemd timer for daily checks
    cat > /etc/systemd/system/aide-check.service <<EOF
[Unit]
Description=AIDE Integrity Check
Documentation=man:aide(1)

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aide-check
StandardOutput=journal
StandardError=journal
Nice=19
IOSchedulingClass=idle
EOF

    cat > /etc/systemd/system/aide-check.timer <<EOF
[Unit]
Description=Daily AIDE Integrity Check
Documentation=man:aide(1)

[Timer]
OnCalendar=daily
RandomizedDelaySec=30m
Persistent=true

[Install]
WantedBy=timers.target
EOF

    # Enable timer
    systemctl daemon-reload
    systemctl enable aide-check.timer
    systemctl start aide-check.timer

    log_success "Automated checks configured"
}

# Create management helper
create_aide_helper() {
    log_info "Creating AIDE management helper..."

    cat > /usr/local/bin/chom-aide <<'EOF'
#!/bin/bash
# CHOM AIDE Management Helper

AIDE_DB="/var/lib/aide/aide.db"
AIDE_DB_NEW="/var/lib/aide/aide.db.new"
AIDE_LOG="/var/log/aide/aide.log"

case "$1" in
    check)
        echo "Running AIDE integrity check..."
        aide --check
        ;;
    update)
        echo "Updating AIDE database..."
        aide --update
        if [[ -f "$AIDE_DB_NEW" ]]; then
            mv "$AIDE_DB_NEW" "$AIDE_DB"
            echo "Database updated successfully"
        fi
        ;;
    init)
        echo "Initializing AIDE database..."
        aideinit
        if [[ -f "$AIDE_DB_NEW" ]]; then
            mv "$AIDE_DB_NEW" "$AIDE_DB"
            echo "Database initialized successfully"
        fi
        ;;
    compare)
        echo "Comparing current state with database..."
        aide --compare
        ;;
    logs)
        echo "Recent AIDE logs:"
        tail -100 "$AIDE_LOG"
        ;;
    status)
        echo "AIDE Status:"
        echo "------------"
        if [[ -f "$AIDE_DB" ]]; then
            echo "Database: $(ls -lh "$AIDE_DB" | awk '{print $9, $5, $6, $7, $8}')"
        else
            echo "Database: Not initialized"
        fi
        echo ""
        systemctl status aide-check.timer --no-pager
        ;;
    schedule)
        echo "AIDE Check Schedule:"
        systemctl list-timers aide-check.timer --no-pager
        ;;
    run-now)
        echo "Running immediate AIDE check..."
        systemctl start aide-check.service
        journalctl -u aide-check.service -n 50 --no-pager
        ;;
    *)
        echo "CHOM AIDE Management"
        echo ""
        echo "Usage: chom-aide <command>"
        echo ""
        echo "Commands:"
        echo "  check       Run integrity check"
        echo "  update      Update AIDE database with current state"
        echo "  init        Initialize/reinitialize database"
        echo "  compare     Compare current state with database"
        echo "  logs        Show recent logs"
        echo "  status      Show AIDE status"
        echo "  schedule    Show check schedule"
        echo "  run-now     Run immediate check via systemd"
        echo ""
        ;;
esac
EOF

    chmod +x /usr/local/bin/chom-aide

    log_success "AIDE helper created: /usr/local/bin/chom-aide"
}

# Create exclusion rules helper
create_exclusion_helper() {
    log_info "Creating exclusion rules documentation..."

    cat > /etc/aide/README-exclusions.txt <<'EOF'
AIDE Exclusion Rules
====================

To exclude directories or files from AIDE monitoring:

1. Edit /etc/aide/aide.conf
2. Add exclusion rules with ! prefix

Examples:
---------

# Exclude specific directory
!/var/log

# Exclude pattern
!.*\.log$

# Exclude specific file
!/var/www/chom/.env

Common Exclusions:
------------------
- Log directories (/var/log)
- Temporary directories (/tmp, /var/tmp)
- Cache directories (/var/cache)
- Dynamic content (/var/www/*/storage)
- Database files that change frequently

After modifying exclusions:
---------------------------
1. Update the AIDE database: chom-aide update
2. Test the configuration: aide --config-check

EOF

    chmod 644 /etc/aide/README-exclusions.txt

    log_success "Exclusion documentation created"
}

# Test AIDE configuration
test_aide_config() {
    log_info "Testing AIDE configuration..."

    if aide --config-check; then
        log_success "AIDE configuration is valid"
    else
        log_error "AIDE configuration has errors"
        return 1
    fi

    return 0
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "AIDE Intrusion Detection Setup Complete"
    log_success "=========================================="
    echo ""

    log_info "Configuration:"
    echo "  Config File: $AIDE_CONF"
    echo "  Database: $AIDE_DB"
    echo "  Log File: $AIDE_LOG"
    echo "  Admin Email: $ADMIN_EMAIL"
    echo ""

    log_info "Monitored Directories:"
    echo "  ✓ System binaries (/bin, /sbin, /usr/bin, /usr/sbin)"
    echo "  ✓ System libraries (/lib, /usr/lib)"
    echo "  ✓ Boot files (/boot)"
    echo "  ✓ System configuration (/etc)"
    echo "  ✓ SSH configuration (/etc/ssh)"
    echo "  ✓ Web server config (/etc/nginx)"
    echo "  ✓ PHP configuration (/etc/php)"
    echo "  ✓ Database config (/etc/postgresql)"
    echo "  ✓ Application code (/var/www/chom)"
    echo "  ✓ Security configs (/etc/fail2ban, /etc/aide)"
    echo ""

    log_info "Features Enabled:"
    echo "  ✓ File integrity monitoring"
    echo "  ✓ Automated daily checks"
    echo "  ✓ Email alerts on changes"
    echo "  ✓ Checksum verification (MD5, SHA256)"
    echo "  ✓ Permission monitoring"
    echo "  ✓ Ownership tracking"
    echo ""

    log_info "Schedule:"
    systemctl list-timers aide-check.timer --no-pager | grep aide-check
    echo ""

    log_info "Management Commands:"
    echo "  chom-aide check       - Run integrity check"
    echo "  chom-aide update      - Update database with current state"
    echo "  chom-aide status      - Show AIDE status"
    echo "  chom-aide logs        - View recent logs"
    echo "  chom-aide run-now     - Run immediate check"
    echo ""

    log_warning "IMPORTANT:"
    echo "  1. Baseline database created with current system state"
    echo "  2. Daily checks will detect any file modifications"
    echo "  3. Alerts sent to: $ADMIN_EMAIL"
    echo "  4. Update database after authorized changes: chom-aide update"
    echo "  5. Review alerts promptly - may indicate compromise"
    echo ""
}

# Main execution
main() {
    log_info "Starting AIDE intrusion detection setup..."
    echo ""

    check_root
    install_aide
    configure_aide
    test_aide_config
    initialize_database
    create_daily_check
    setup_automated_checks
    create_aide_helper
    create_exclusion_helper
    display_summary

    log_success "AIDE setup complete!"
}

# Run main function
main "$@"
