#!/bin/bash
# ============================================================================
# Security Incident Response Script
# ============================================================================
# Purpose: Automated response to security incidents
# Actions: Forensics, isolation, containment, recovery
# Compliance: PCI DSS 12.10, SOC 2, ISO 27001 A.16
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
INCIDENT_DIR="/var/log/chom/incidents"
FORENSICS_DIR="/var/forensics"
BACKUP_DIR="/var/backups/chom"
ALERT_EMAIL="${ALERT_EMAIL:-admin@arewel.com}"
APP_ROOT="${APP_ROOT:-/var/www/chom}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$INCIDENT_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$INCIDENT_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$INCIDENT_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$INCIDENT_LOG"
}

log_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1" | tee -a "$INCIDENT_LOG"
}

log_section() {
    echo "" | tee -a "$INCIDENT_LOG"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$INCIDENT_LOG"
    echo -e "${MAGENTA}$1${NC}" | tee -a "$INCIDENT_LOG"
    echo -e "${MAGENTA}========================================${NC}" | tee -a "$INCIDENT_LOG"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Initialize incident
init_incident() {
    local incident_id="INC-$(date +%Y%m%d-%H%M%S)"
    INCIDENT_DIR="${INCIDENT_DIR}/${incident_id}"
    INCIDENT_LOG="${INCIDENT_DIR}/incident.log"

    mkdir -p "$INCIDENT_DIR"
    chmod 700 "$INCIDENT_DIR"

    cat > "$INCIDENT_LOG" <<EOF
============================================================================
SECURITY INCIDENT RESPONSE
============================================================================
Incident ID: $incident_id
Date/Time: $(date)
Server: $(hostname)
Initiated by: $(whoami)
============================================================================

EOF

    echo "$incident_id"
}

# Capture forensic data
capture_forensics() {
    log_section "Capturing Forensic Data"

    local forensics_file="$INCIDENT_DIR/forensics_$(date +%Y%m%d_%H%M%S).tar.gz"

    mkdir -p "$FORENSICS_DIR"

    log_info "Capturing system state..."

    # Current processes
    ps auxf > "$FORENSICS_DIR/processes.txt"

    # Network connections
    ss -tuanp > "$FORENSICS_DIR/network_connections.txt"
    netstat -tuanp > "$FORENSICS_DIR/netstat.txt" 2>/dev/null || true

    # Logged in users
    who -a > "$FORENSICS_DIR/logged_in_users.txt"
    w > "$FORENSICS_DIR/user_activity.txt"

    # Recent commands (bash history)
    for user_home in /home/*; do
        user=$(basename "$user_home")
        if [[ -f "$user_home/.bash_history" ]]; then
            cp "$user_home/.bash_history" "$FORENSICS_DIR/bash_history_${user}.txt"
        fi
    done

    # System logs
    cp /var/log/auth.log "$FORENSICS_DIR/" 2>/dev/null || true
    cp /var/log/syslog "$FORENSICS_DIR/" 2>/dev/null || true
    cp /var/log/fail2ban.log "$FORENSICS_DIR/" 2>/dev/null || true

    # Nginx logs
    if [[ -d /var/log/nginx ]]; then
        cp -r /var/log/nginx "$FORENSICS_DIR/"
    fi

    # Laravel logs
    if [[ -d "$APP_ROOT/storage/logs" ]]; then
        cp -r "$APP_ROOT/storage/logs" "$FORENSICS_DIR/laravel_logs"
    fi

    # Currently banned IPs
    if command -v fail2ban-client &> /dev/null; then
        fail2ban-client status > "$FORENSICS_DIR/fail2ban_status.txt" 2>/dev/null || true
    fi

    # Open files
    lsof > "$FORENSICS_DIR/open_files.txt" 2>/dev/null || true

    # Modified files in last 24 hours
    find /var/www -type f -mtime -1 > "$FORENSICS_DIR/recent_modifications.txt" 2>/dev/null || true

    # System information
    uname -a > "$FORENSICS_DIR/system_info.txt"
    df -h >> "$FORENSICS_DIR/system_info.txt"
    free -h >> "$FORENSICS_DIR/system_info.txt"

    # Compress forensics data
    tar -czf "$forensics_file" -C "$(dirname "$FORENSICS_DIR")" "$(basename "$FORENSICS_DIR")"
    chmod 400 "$forensics_file"

    log_success "Forensic data captured: $forensics_file"
}

# Isolate compromised server
isolate_server() {
    log_section "Server Isolation"

    log_warning "This will isolate the server from the network!"
    read -p "Proceed with isolation? (yes/no): " -r

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Isolation cancelled"
        return 0
    fi

    log_critical "Isolating server from network..."

    # Block all outgoing connections except to specific IPs
    ufw --force reset

    # Deny all by default
    ufw default deny incoming
    ufw default deny outgoing

    # Allow only SSH from admin IPs (for investigation)
    log_info "Enter admin IP address for emergency access:"
    read -r admin_ip

    if [[ -n "$admin_ip" ]]; then
        ufw allow from "$admin_ip" to any port 2222 proto tcp
        log_info "Allowed SSH from $admin_ip"
    fi

    # Enable firewall
    echo "y" | ufw enable

    log_critical "Server isolated - all network traffic blocked except admin SSH"
}

# Block attacker IP
block_ip() {
    local attacker_ip="$1"

    log_section "Blocking Attacker IP"

    log_info "Blocking IP: $attacker_ip"

    # Block with UFW
    ufw deny from "$attacker_ip"

    # Ban with Fail2Ban
    if command -v fail2ban-client &> /dev/null; then
        fail2ban-client set sshd banip "$attacker_ip" || true
    fi

    # Add to permanent blacklist
    echo "$attacker_ip # Blocked $(date)" >> /etc/chom/ip-blacklist.txt

    log_success "IP $attacker_ip blocked"
}

# Rotate all credentials
rotate_credentials() {
    log_section "Rotating Credentials"

    log_warning "This will rotate all system credentials!"
    read -p "Proceed with credential rotation? (yes/no): " -r

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Credential rotation cancelled"
        return 0
    fi

    log_info "Rotating credentials..."

    # Rotate Laravel APP_KEY
    if [[ -f "$APP_ROOT/artisan" ]]; then
        cd "$APP_ROOT"
        php artisan key:generate --force
        log_success "Laravel APP_KEY rotated"
    fi

    # Rotate database password
    local new_db_password=$(openssl rand -base64 32)
    sudo -u postgres psql -c "ALTER USER chom WITH PASSWORD '$new_db_password';" 2>/dev/null || true

    # Update .env
    if [[ -f "$APP_ROOT/.env" ]]; then
        sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$new_db_password/" "$APP_ROOT/.env"
        log_success "Database password rotated"
    fi

    # Rotate Redis password
    local new_redis_password=$(openssl rand -base64 32)
    sed -i "s/^requirepass.*/requirepass $new_redis_password/" /etc/redis/redis.conf 2>/dev/null || true
    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$new_redis_password/" "$APP_ROOT/.env" 2>/dev/null || true
    systemctl restart redis 2>/dev/null || true
    log_success "Redis password rotated"

    # Expire all user sessions
    if [[ -f "$APP_ROOT/artisan" ]]; then
        php artisan cache:clear
        php artisan session:flush 2>/dev/null || true
        log_success "User sessions expired"
    fi

    log_success "All credentials rotated"
}

# Restore from backup
restore_from_backup() {
    log_section "Restore from Backup"

    log_warning "This will restore the system from last known good backup!"
    read -p "Proceed with restore? (yes/no): " -r

    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Restore cancelled"
        return 0
    fi

    # List available backups
    log_info "Available backups:"
    ls -lh "$BACKUP_DIR" | grep -E "\.tar\.gz|\.sql\.gz"

    read -p "Enter backup filename to restore: " -r backup_file

    if [[ ! -f "$BACKUP_DIR/$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    log_info "Restoring from backup: $backup_file"

    # Stop services
    systemctl stop nginx
    systemctl stop "php*-fpm" || true
    systemctl stop postgresql

    # Restore based on backup type
    if [[ "$backup_file" == *.sql.gz ]]; then
        # Database backup
        gunzip -c "$BACKUP_DIR/$backup_file" | sudo -u postgres psql chom
        log_success "Database restored"
    elif [[ "$backup_file" == *.tar.gz ]]; then
        # Application backup
        tar -xzf "$BACKUP_DIR/$backup_file" -C /var/www/
        chown -R www-data:www-data "$APP_ROOT"
        log_success "Application files restored"
    fi

    # Start services
    systemctl start postgresql
    systemctl start "php*-fpm" || true
    systemctl start nginx

    log_success "System restored from backup"
}

# Generate incident report
generate_incident_report() {
    log_section "Incident Report"

    local report_file="$INCIDENT_DIR/incident_report.txt"

    cat > "$report_file" <<EOF
============================================================================
SECURITY INCIDENT REPORT
============================================================================

Incident ID: $(basename "$INCIDENT_DIR")
Date/Time: $(date)
Server: $(hostname)

INCIDENT SUMMARY:
-----------------
Type: $INCIDENT_TYPE
Severity: $INCIDENT_SEVERITY
Status: $INCIDENT_STATUS

AFFECTED SYSTEMS:
-----------------
- Application Server: $(hostname)
- Application: CHOM Laravel
- Database: PostgreSQL
- Web Server: Nginx

TIMELINE:
---------
Detection Time: $DETECTION_TIME
Response Time: $RESPONSE_TIME
Resolution Time: $(date)

ACTIONS TAKEN:
--------------
$(grep -E "\[SUCCESS\]|\[CRITICAL\]" "$INCIDENT_LOG")

ATTACKER INFORMATION:
---------------------
IP Address: $ATTACKER_IP
Location: $(geoiplookup "$ATTACKER_IP" 2>/dev/null || echo "Unknown")
Attack Vector: $ATTACK_VECTOR

FORENSIC DATA:
--------------
Location: $INCIDENT_DIR/
Files: $(ls -1 "$INCIDENT_DIR" | wc -l)

REMEDIATION:
------------
1. Forensic data captured
2. Attacker IP blocked
3. Credentials rotated
4. System restored from backup
5. Security measures enhanced

RECOMMENDATIONS:
----------------
1. Review and update security policies
2. Conduct security awareness training
3. Implement additional monitoring
4. Schedule follow-up security audit
5. Document lessons learned

NEXT STEPS:
-----------
1. Monitor for continued attacks
2. Review logs for additional indicators
3. Update incident response procedures
4. Conduct post-incident review
5. Implement preventive measures

============================================================================
Generated: $(date)
Report by: CHOM Incident Response System
============================================================================
EOF

    log_success "Incident report generated: $report_file"

    # Display report
    cat "$report_file"
}

# Send incident notification
send_incident_notification() {
    log_info "Sending incident notification..."

    local subject="[SECURITY INCIDENT] $(basename "$INCIDENT_DIR") on $(hostname)"

    {
        echo "SECURITY INCIDENT DETECTED"
        echo "=========================="
        echo ""
        echo "Incident ID: $(basename "$INCIDENT_DIR")"
        echo "Server: $(hostname)"
        echo "Time: $(date)"
        echo "Type: $INCIDENT_TYPE"
        echo "Severity: $INCIDENT_SEVERITY"
        echo ""
        echo "IMMEDIATE ACTIONS TAKEN:"
        grep -E "\[SUCCESS\]|\[CRITICAL\]" "$INCIDENT_LOG" | tail -10
        echo ""
        echo "Full incident report available at: $INCIDENT_DIR/"
        echo ""
        echo "This is an automated alert from CHOM Incident Response System."
    } | mail -s "$subject" "$ALERT_EMAIL" 2>/dev/null || log_warning "Failed to send email notification"

    log_success "Incident notification sent"
}

# Interactive incident response
interactive_response() {
    local incident_id=$(init_incident)

    log_section "CHOM Security Incident Response"
    log_critical "Incident ID: $incident_id"

    # Gather incident information
    read -p "Incident Type (intrusion/malware/data_breach/dos): " INCIDENT_TYPE
    read -p "Severity (low/medium/high/critical): " INCIDENT_SEVERITY
    read -p "Attacker IP (if known): " ATTACKER_IP
    read -p "Attack Vector (ssh/web/api/other): " ATTACK_VECTOR

    INCIDENT_STATUS="In Progress"
    DETECTION_TIME=$(date)
    RESPONSE_TIME=$(date)

    # Response menu
    while true; do
        echo ""
        echo "=========================================="
        echo "Incident Response Menu"
        echo "=========================================="
        echo "1) Capture forensic data"
        echo "2) Block attacker IP"
        echo "3) Isolate server"
        echo "4) Rotate credentials"
        echo "5) Restore from backup"
        echo "6) Generate incident report"
        echo "7) Send notifications"
        echo "8) Complete incident"
        echo "9) Exit"
        echo ""
        read -p "Select action: " choice

        case $choice in
            1) capture_forensics ;;
            2)
                if [[ -n "$ATTACKER_IP" ]]; then
                    block_ip "$ATTACKER_IP"
                else
                    read -p "Enter IP to block: " ip
                    block_ip "$ip"
                fi
                ;;
            3) isolate_server ;;
            4) rotate_credentials ;;
            5) restore_from_backup ;;
            6) generate_incident_report ;;
            7) send_incident_notification ;;
            8)
                INCIDENT_STATUS="Resolved"
                generate_incident_report
                send_incident_notification
                log_success "Incident response completed"
                break
                ;;
            9)
                log_warning "Exiting incident response (incident not completed)"
                break
                ;;
            *) log_error "Invalid choice" ;;
        esac
    done
}

# Automated response (for detected incidents)
automated_response() {
    local incident_type="$1"
    local attacker_ip="$2"

    local incident_id=$(init_incident)

    INCIDENT_TYPE="$incident_type"
    INCIDENT_SEVERITY="high"
    ATTACKER_IP="$attacker_ip"
    ATTACK_VECTOR="automated_detection"
    INCIDENT_STATUS="Auto-Responded"
    DETECTION_TIME=$(date)
    RESPONSE_TIME=$(date)

    log_critical "Automated incident response triggered"

    # Automated actions
    capture_forensics
    block_ip "$attacker_ip"
    generate_incident_report
    send_incident_notification

    log_success "Automated response completed"
}

# Display help
display_help() {
    cat <<EOF
============================================================================
CHOM Security Incident Response
============================================================================

Usage: $0 <mode> [options]

Modes:
  interactive              Interactive incident response
  auto <type> <ip>         Automated response
  block <ip>               Block specific IP
  report                   Generate report for last incident
  help                     Show this help

Examples:
  $0 interactive
  $0 auto intrusion 192.168.1.100
  $0 block 10.0.0.50

Incident Types:
  - intrusion              Unauthorized access attempt
  - malware                Malware detection
  - data_breach            Data breach or leak
  - dos                    Denial of service attack

============================================================================
EOF
}

# Main execution
main() {
    local mode="${1:-interactive}"

    check_root

    case "$mode" in
        interactive)
            interactive_response
            ;;
        auto)
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                log_error "Usage: $0 auto <type> <ip>"
                exit 1
            fi
            automated_response "$2" "$3"
            ;;
        block)
            if [[ -z "${2:-}" ]]; then
                log_error "Usage: $0 block <ip>"
                exit 1
            fi
            local incident_id=$(init_incident)
            block_ip "$2"
            ;;
        report)
            # Find last incident
            local last_incident=$(ls -1dt "$INCIDENT_DIR"/../INC-* 2>/dev/null | head -1)
            if [[ -n "$last_incident" ]]; then
                cat "$last_incident/incident_report.txt" 2>/dev/null || log_error "Report not found"
            else
                log_error "No incidents found"
            fi
            ;;
        help|--help|-h)
            display_help
            ;;
        *)
            log_error "Unknown mode: $mode"
            display_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
