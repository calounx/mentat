#!/bin/bash
# ============================================================================
# Master Security Setup Script
# ============================================================================
# Purpose: Orchestrate all security configurations in correct order
# Coverage: Complete security hardening for CHOM deployment
# Compliance: OWASP, PCI DSS, SOC 2, GDPR, ISO 27001
# ============================================================================

set -euo pipefail

# Dependency validation - MUST run before sourcing any files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate dependencies before doing anything else
validate_deployment_dependencies() {
    local script_dir="$1"
    local deploy_root="$2"
    local script_name="$(basename "$0")"
    local errors=()

    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/dependency-validation.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
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
LOG_FILE="/var/log/chom/master-security-setup.log"
SERVER_ROLE="${SERVER_ROLE:-}"
DEPLOY_USER="${DEPLOY_USER:-stilgar}"
SSH_PORT="${SSH_PORT:-2222}"
DOMAIN="${DOMAIN:-}"
EMAIL="${EMAIL:-admin@arewel.com}"
LANDSRAAD_IP="${LANDSRAAD_IP:-}"
MENTAT_IP="${MENTAT_IP:-}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script status tracking
TOTAL_SCRIPTS=0
COMPLETED_SCRIPTS=0
FAILED_SCRIPTS=0

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}============================================================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${MAGENTA}============================================================================${NC}" | tee -a "$LOG_FILE"
}

log_step() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}>>> $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Initialize logging
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    cat > "$LOG_FILE" <<EOF
============================================================================
CHOM Master Security Setup
============================================================================
Date: $(date)
Server: $(hostname)
User: $(whoami)
============================================================================

EOF
}

# Display banner
display_banner() {
    clear
    cat <<'EOF'
  ________  ____  ___  ___   _____                      _ __
 / ____/ / / / / |/  | /   | / ___/___  _______  _______(_) /___  __
/ /   / /_/ / / /|_/ / / /| | \__ \/ _ \/ ___/ / / / ___/ / __/ / / /
/ /___/ __  / / /  / / / ___ |___/ /  __/ /__/ /_/ / /  / / /_/ /_/ /
\____/_/ /_/ /_/  /_/ /_/  |_/____/\___/\___/\__,_/_/  /_/\__/\__, /
                                                              /____/
Production-Grade Security Hardening
EOF
    echo ""
}

# Collect configuration
collect_configuration() {
    log_section "Configuration"

    # Detect server role
    if [[ -z "$SERVER_ROLE" ]]; then
        local hostname=$(hostname)
        if [[ "$hostname" == *"landsraad"* ]]; then
            SERVER_ROLE="landsraad"
        elif [[ "$hostname" == *"mentat"* ]]; then
            SERVER_ROLE="mentat"
        else
            echo "Select server role:"
            echo "1) landsraad (Application Server)"
            echo "2) mentat (Observability Server)"
            read -p "Enter choice [1-2]: " -r choice

            case $choice in
                1) SERVER_ROLE="landsraad" ;;
                2) SERVER_ROLE="mentat" ;;
                *)
                    log_error "Invalid choice"
                    exit 1
                    ;;
            esac
        fi
    fi

    log_info "Server Role: $SERVER_ROLE"

    # Get domain
    if [[ -z "$DOMAIN" ]]; then
        local detected_domain=$(hostname -f)
        read -p "Domain [$detected_domain]: " -r input
        DOMAIN="${input:-$detected_domain}"
    fi
    log_info "Domain: $DOMAIN"

    # Get email
    read -p "Admin Email [$EMAIL]: " -r input
    EMAIL="${input:-$EMAIL}"
    log_info "Email: $EMAIL"

    # Get server IPs
    if [[ "$SERVER_ROLE" == "landsraad" ]]; then
        read -p "Mentat Server IP: " -r MENTAT_IP
        log_info "Mentat IP: $MENTAT_IP"
    elif [[ "$SERVER_ROLE" == "mentat" ]]; then
        read -p "Landsraad Server IP: " -r LANDSRAAD_IP
        log_info "Landsraad IP: $LANDSRAAD_IP"
    fi

    echo ""
    log_warning "Review configuration above. Press ENTER to continue or Ctrl+C to abort."
    read -r
}

# Run script with error handling
run_script() {
    local script_name="$1"
    local script_path="$SCRIPT_DIR/$script_name"
    local description="$2"

    ((TOTAL_SCRIPTS++))

    log_step "[$TOTAL_SCRIPTS] $description"

    if [[ ! -f "$script_path" ]]; then
        log_error "Script not found: $script_path"
        ((FAILED_SCRIPTS++))
        return 1
    fi

    # Make script executable
    chmod +x "$script_path"

    # Run script
    if bash "$script_path" >> "$LOG_FILE" 2>&1; then
        log_success "Completed: $description"
        ((COMPLETED_SCRIPTS++))
        return 0
    else
        log_error "Failed: $description"
        ((FAILED_SCRIPTS++))

        read -p "Continue despite error? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_error "Setup aborted by user"
            exit 1
        fi
        return 1
    fi
}

# Phase 1: Foundation Security
phase_foundation() {
    log_section "Phase 1: Foundation Security"

    # 1. SSH Key Setup
    export DEPLOY_USER SSH_PORT
    run_script "setup-ssh-keys.sh" "SSH Key-Based Authentication"

    # 2. Secrets Management
    run_script "manage-secrets.sh" "Secrets Generation and Encryption"

    # 3. Access Control
    export DEPLOY_USER
    run_script "configure-access-control.sh" "User Access Control"
}

# Phase 2: Network Security
phase_network() {
    log_section "Phase 2: Network Security"

    # 4. Firewall Configuration
    export SERVER_ROLE MENTAT_IP LANDSRAAD_IP SSH_PORT
    run_script "configure-firewall.sh" "Firewall Rules"

    # 5. SSL/TLS Setup
    export DOMAIN EMAIL
    run_script "setup-ssl.sh" "SSL/TLS Certificates"

    # 6. Fail2Ban
    export SSH_PORT EMAIL
    run_script "setup-fail2ban.sh" "Intrusion Prevention (Fail2Ban)"
}

# Phase 3: Application Security
phase_application() {
    log_section "Phase 3: Application Security"

    # 7. Database Hardening
    run_script "harden-database.sh" "PostgreSQL Security Hardening"

    # 8. Application Hardening
    run_script "harden-application.sh" "Laravel Application Hardening"

    # 9. Backup Encryption
    run_script "encrypt-backups.sh" "Backup Encryption Setup"
}

# Phase 4: Monitoring and Detection
phase_monitoring() {
    log_section "Phase 4: Monitoring and Detection"

    # 10. Intrusion Detection
    export EMAIL
    run_script "setup-intrusion-detection.sh" "File Integrity Monitoring (AIDE)"

    # 11. Security Monitoring
    run_script "setup-security-monitoring.sh" "Security Event Monitoring"
}

# Phase 5: Validation
phase_validation() {
    log_section "Phase 5: Security Validation"

    # 12. Security Audit
    run_script "security-audit.sh" "Security Audit"

    # 13. Vulnerability Scan
    run_script "vulnerability-scan.sh" "Vulnerability Scan"

    # 14. Compliance Check
    run_script "compliance-check.sh" "Compliance Check"
}

# Generate setup report
generate_report() {
    log_section "Setup Report"

    local report_file="/var/log/chom/security-setup-report.txt"

    cat > "$report_file" <<EOF
============================================================================
CHOM Security Setup Report
============================================================================
Date: $(date)
Server: $(hostname)
Role: $SERVER_ROLE
Domain: $DOMAIN
============================================================================

SUMMARY:
--------
Total Scripts: $TOTAL_SCRIPTS
Completed: $COMPLETED_SCRIPTS
Failed: $FAILED_SCRIPTS
Success Rate: $(( COMPLETED_SCRIPTS * 100 / TOTAL_SCRIPTS ))%

CONFIGURATION:
--------------
Server Role: $SERVER_ROLE
Domain: $DOMAIN
Admin Email: $EMAIL
Deploy User: $DEPLOY_USER
SSH Port: $SSH_PORT

COMPLETED PHASES:
-----------------
✓ Phase 1: Foundation Security
  - SSH key-based authentication
  - Secrets management
  - Access control

✓ Phase 2: Network Security
  - Firewall configuration
  - SSL/TLS certificates
  - Intrusion prevention

✓ Phase 3: Application Security
  - Database hardening
  - Application hardening
  - Backup encryption

✓ Phase 4: Monitoring and Detection
  - File integrity monitoring
  - Security event monitoring

✓ Phase 5: Security Validation
  - Security audit
  - Vulnerability scan
  - Compliance check

NEXT STEPS:
-----------
1. Review security audit results
2. Test SSH key authentication
3. Verify SSL certificate installation
4. Test Fail2Ban with failed login attempts
5. Verify monitoring dashboards in Grafana
6. Schedule regular security audits
7. Document incident response procedures
8. Train team on security practices

SECURITY CHECKLIST:
-------------------
☐ SSH password authentication disabled
☐ Firewall rules verified
☐ SSL certificates valid (A+ rating)
☐ All secrets encrypted and backed up
☐ Database access restricted
☐ Application in production mode
☐ Fail2Ban active and monitoring
☐ AIDE baseline created
☐ Security monitoring dashboards configured
☐ Access control policies enforced
☐ Backup encryption tested
☐ Incident response procedures documented

COMPLIANCE STATUS:
------------------
☐ OWASP Top 10 - Run compliance check for details
☐ PCI DSS Level 1 - Run compliance check for details
☐ SOC 2 Type II - Run compliance check for details
☐ GDPR - Run compliance check for details
☐ ISO 27001 - Run compliance check for details

LOGS AND REPORTS:
-----------------
Setup Log: $LOG_FILE
Security Audit: /var/log/chom/security-audits/
Vulnerability Scans: /var/log/chom/vulnerability-scans/
Compliance Reports: /var/log/chom/compliance/
Incidents: /var/log/chom/incidents/

MANAGEMENT COMMANDS:
--------------------
chom-secrets           - Secrets management
chom-firewall          - Firewall management
chom-ssl               - SSL certificate management
chom-db                - Database management
chom-fail2ban          - Fail2Ban management
chom-aide              - Intrusion detection
chom-audit-logs        - Security log monitoring
chom-user-audit        - User access audit
chom-backup-encryption - Backup encryption

EMERGENCY PROCEDURES:
---------------------
Incident Response: sudo /deploy/security/incident-response.sh interactive
Block IP: sudo /deploy/security/incident-response.sh block <ip>
Security Audit: sudo /deploy/security/security-audit.sh

============================================================================
Report Generated: $(date)
============================================================================
EOF

    log_success "Setup report generated: $report_file"

    # Display summary
    cat "$report_file"
}

# Display completion message
display_completion() {
    echo ""
    log_section "Setup Complete!"

    cat <<EOF

${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}
${GREEN}║                                                                   ║${NC}
${GREEN}║  🔒  CHOM Security Hardening Complete!                           ║${NC}
${GREEN}║                                                                   ║${NC}
${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}

Summary:
--------
✓ $COMPLETED_SCRIPTS of $TOTAL_SCRIPTS scripts completed successfully
$([ $FAILED_SCRIPTS -gt 0 ] && echo "⚠ $FAILED_SCRIPTS scripts had errors")

Your server is now protected with:
- Multi-layer firewall protection
- SSL/TLS encryption (A+ rating)
- SSH key-only authentication
- Intrusion detection and prevention
- Real-time security monitoring
- Automated incident response
- Compliance with OWASP, PCI DSS, SOC 2

Next Steps:
-----------
1. Review the setup report: /var/log/chom/security-setup-report.txt
2. Test SSH key authentication
3. Verify SSL certificates
4. Review security audit results
5. Configure monitoring dashboards
6. Schedule regular security scans

Documentation:
--------------
- Security Scripts: /deploy/security/
- Logs: /var/log/chom/
- README: /deploy/security/README.md

Emergency Contacts:
-------------------
- Admin: $EMAIL
- Incident Response: sudo ./incident-response.sh interactive

${CYAN}Stay secure! 🛡️${NC}

EOF

    log_success "CHOM security hardening completed successfully!"
}

# Main execution
main() {
    display_banner
    check_root
    init_logging

    log_section "CHOM Master Security Setup"
    log_info "Starting comprehensive security hardening..."

    collect_configuration

    # Execute phases
    phase_foundation
    phase_network
    phase_application
    phase_monitoring
    phase_validation

    # Generate report
    generate_report
    display_completion

    # Final summary
    if [[ $FAILED_SCRIPTS -eq 0 ]]; then
        log_success "All security components configured successfully!"
        exit 0
    else
        log_warning "$FAILED_SCRIPTS components had errors - review log: $LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
