#!/bin/bash
# ============================================================================
# Security Monitoring Setup Script
# ============================================================================
# Purpose: Configure comprehensive security event monitoring
# Integration: Loki, Grafana, Prometheus, AlertManager
# Features: Log aggregation, alerts, dashboards
# Compliance: PCI DSS 10.6, SOC 2, ISO 27001
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
LOKI_URL="${LOKI_URL:-http://mentat.arewel.com:3100}"
GRAFANA_URL="${GRAFANA_URL:-http://mentat.arewel.com:3000}"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://mentat.arewel.com:9090}"
ALERT_EMAIL="${ALERT_EMAIL:-admin@arewel.com}"
APP_ROOT="${APP_ROOT:-/var/www/chom}"

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

# Install Promtail (Loki agent)
install_promtail() {
    log_info "Installing Promtail..."

    # Download Promtail
    local version="2.9.3"
    local arch="amd64"

    wget -q "https://github.com/grafana/loki/releases/download/v${version}/promtail-linux-${arch}.zip" -O /tmp/promtail.zip

    unzip -q /tmp/promtail.zip -d /tmp/
    mv /tmp/promtail-linux-${arch} /usr/local/bin/promtail
    chmod +x /usr/local/bin/promtail

    rm /tmp/promtail.zip

    log_success "Promtail installed"
}

# Configure Promtail
configure_promtail() {
    log_info "Configuring Promtail..."

    mkdir -p /etc/promtail

    cat > /etc/promtail/config.yml <<EOF
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: ${LOKI_URL}/loki/api/v1/push

scrape_configs:
  # System logs
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: \$(hostname)
          __path__: /var/log/*log

  # Auth logs (SSH, sudo)
  - job_name: auth
    static_configs:
      - targets:
          - localhost
        labels:
          job: auth
          host: \$(hostname)
          __path__: /var/log/auth.log
    pipeline_stages:
      - regex:
          expression: '(?P<timestamp>\w+\s+\d+\s+\d+:\d+:\d+).*sshd.*(?P<action>Failed|Accepted).*for (?P<user>\w+)'
      - labels:
          action:
          user:

  # Fail2Ban logs
  - job_name: fail2ban
    static_configs:
      - targets:
          - localhost
        labels:
          job: fail2ban
          host: \$(hostname)
          __path__: /var/log/fail2ban.log
    pipeline_stages:
      - regex:
          expression: '.*\[(?P<jail>\w+)\].*(?P<action>Ban|Unban) (?P<ip>[\d\.]+)'
      - labels:
          jail:
          action:
          ip:

  # Nginx access logs
  - job_name: nginx_access
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_access
          host: \$(hostname)
          __path__: /var/log/nginx/*access.log
    pipeline_stages:
      - regex:
          expression: '^(?P<ip>\S+).*"(?P<method>\w+)\s(?P<path>\S+)\s\S+"\s(?P<status>\d+)'
      - labels:
          method:
          status:

  # Nginx error logs
  - job_name: nginx_error
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx_error
          host: \$(hostname)
          __path__: /var/log/nginx/*error.log

  # Laravel logs
  - job_name: laravel
    static_configs:
      - targets:
          - localhost
        labels:
          job: laravel
          host: \$(hostname)
          __path__: ${APP_ROOT}/storage/logs/laravel*.log
    pipeline_stages:
      - regex:
          expression: '^\[(?P<timestamp>.*)\]\s(?P<environment>\w+)\.(?P<level>\w+):'
      - labels:
          level:

  # AIDE logs (intrusion detection)
  - job_name: aide
    static_configs:
      - targets:
          - localhost
        labels:
          job: aide
          host: \$(hostname)
          __path__: /var/log/aide/*.log

  # PostgreSQL logs
  - job_name: postgresql
    static_configs:
      - targets:
          - localhost
        labels:
          job: postgresql
          host: \$(hostname)
          __path__: /var/log/postgresql/*.log
EOF

    # Create positions directory
    mkdir -p /var/lib/promtail
    chmod 755 /var/lib/promtail

    log_success "Promtail configured"
}

# Create Promtail systemd service
create_promtail_service() {
    log_info "Creating Promtail systemd service..."

    cat > /etc/systemd/system/promtail.service <<EOF
[Unit]
Description=Promtail Log Aggregator
Documentation=https://grafana.com/docs/loki/
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable promtail
    systemctl start promtail

    log_success "Promtail service created and started"
}

# Configure security event logging
configure_security_logging() {
    log_info "Configuring security event logging..."

    # Configure syslog for security events
    cat >> /etc/rsyslog.d/50-chom-security.conf <<'EOF'
# CHOM Security Event Logging

# SSH authentication
auth,authpriv.*    /var/log/auth.log

# Sudo commands
:programname, isequal, "sudo"    /var/log/sudo.log

# File integrity (AIDE)
:programname, isequal, "aide"    /var/log/aide/aide.log

# Fail2Ban
:programname, isequal, "fail2ban"    /var/log/fail2ban.log
EOF

    # Restart rsyslog
    systemctl restart rsyslog

    log_success "Security logging configured"
}

# Create Laravel logging configuration
configure_laravel_logging() {
    log_info "Configuring Laravel security logging..."

    # Create Laravel logging middleware
    cat > "$APP_ROOT/app/Http/Middleware/SecurityLogger.php" <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class SecurityLogger
{
    public function handle(Request $request, Closure $next)
    {
        // Log authentication attempts
        if ($request->is('login')) {
            Log::channel('security')->info('Login attempt', [
                'ip' => $request->ip(),
                'user_agent' => $request->userAgent(),
            ]);
        }

        // Log failed authentication
        if (auth()->check() === false && $request->is('login')) {
            Log::channel('security')->warning('Failed login attempt', [
                'ip' => $request->ip(),
                'email' => $request->input('email'),
            ]);
        }

        // Log privileged actions
        if (auth()->check() && $request->user()->hasRole('admin')) {
            Log::channel('security')->info('Admin action', [
                'user' => $request->user()->email,
                'ip' => $request->ip(),
                'action' => $request->path(),
            ]);
        }

        return $next($request);
    }
}
EOF

    log_success "Laravel security logging configured"
}

# Create audit log script
create_audit_log_script() {
    log_info "Creating audit log monitoring script..."

    cat > /usr/local/bin/chom-audit-logs <<'EOF'
#!/bin/bash
# CHOM Audit Log Monitoring

case "$1" in
    ssh)
        echo "=== Recent SSH Authentication Events ==="
        grep -i "sshd" /var/log/auth.log | tail -50
        ;;
    sudo)
        echo "=== Recent Sudo Commands ==="
        grep -i "sudo" /var/log/auth.log | tail -50
        ;;
    fail2ban)
        echo "=== Recent Fail2Ban Events ==="
        grep -i "ban" /var/log/fail2ban.log | tail -50
        ;;
    aide)
        echo "=== Recent AIDE Detections ==="
        if [[ -f /var/log/aide/aide.log ]]; then
            tail -100 /var/log/aide/aide.log
        else
            echo "No AIDE logs found"
        fi
        ;;
    laravel)
        echo "=== Recent Laravel Security Events ==="
        if [[ -f $APP_ROOT/storage/logs/laravel.log ]]; then
            grep -i "security\|authentication\|login" $APP_ROOT/storage/logs/laravel.log | tail -50
        else
            echo "No Laravel logs found"
        fi
        ;;
    nginx-errors)
        echo "=== Recent Nginx Errors ==="
        tail -50 /var/log/nginx/error.log
        ;;
    suspicious)
        echo "=== Suspicious Activity ==="
        echo ""
        echo "Failed SSH logins:"
        grep "Failed password" /var/log/auth.log | tail -20
        echo ""
        echo "Banned IPs:"
        fail2ban-client status sshd 2>/dev/null | grep "Banned IP"
        echo ""
        echo "SQL injection attempts:"
        grep -i "union.*select\|concat.*char" /var/log/nginx/access.log | tail -10
        ;;
    *)
        echo "CHOM Audit Log Monitoring"
        echo ""
        echo "Usage: chom-audit-logs <type>"
        echo ""
        echo "Types:"
        echo "  ssh             SSH authentication events"
        echo "  sudo            Sudo command execution"
        echo "  fail2ban        Fail2Ban ban/unban events"
        echo "  aide            File integrity alerts"
        echo "  laravel         Laravel security events"
        echo "  nginx-errors    Nginx error log"
        echo "  suspicious      Suspicious activity summary"
        echo ""
        ;;
esac
EOF

    chmod +x /usr/local/bin/chom-audit-logs

    log_success "Audit log script created"
}

# Create Grafana dashboard
create_grafana_dashboard() {
    log_info "Creating Grafana security dashboard..."

    mkdir -p /var/lib/grafana/dashboards

    cat > /var/lib/grafana/dashboards/chom-security.json <<'EOF'
{
  "dashboard": {
    "title": "CHOM Security Monitoring",
    "panels": [
      {
        "title": "Failed SSH Logins",
        "targets": [
          {
            "expr": "count_over_time({job=\"auth\"} |= \"Failed password\" [1h])"
          }
        ]
      },
      {
        "title": "Fail2Ban Bans",
        "targets": [
          {
            "expr": "count_over_time({job=\"fail2ban\"} |= \"Ban\" [1h])"
          }
        ]
      },
      {
        "title": "Laravel Authentication Failures",
        "targets": [
          {
            "expr": "count_over_time({job=\"laravel\"} |= \"Failed login\" [1h])"
          }
        ]
      },
      {
        "title": "AIDE File Changes",
        "targets": [
          {
            "expr": "count_over_time({job=\"aide\"} [1h])"
          }
        ]
      }
    ]
  }
}
EOF

    log_success "Grafana dashboard created"
}

# Test monitoring
test_monitoring() {
    log_info "Testing security monitoring..."

    # Test Promtail
    if systemctl is-active --quiet promtail; then
        log_success "Promtail is running"
    else
        log_error "Promtail is not running"
        return 1
    fi

    # Test Loki connectivity
    if curl -s "$LOKI_URL/ready" &>/dev/null; then
        log_success "Loki is accessible"
    else
        log_warning "Loki is not accessible at $LOKI_URL"
    fi

    return 0
}

# Display summary
display_summary() {
    echo ""
    log_success "=========================================="
    log_success "Security Monitoring Setup Complete"
    log_success "=========================================="
    echo ""

    log_info "Configuration:"
    echo "  Loki URL: $LOKI_URL"
    echo "  Grafana URL: $GRAFANA_URL"
    echo "  Prometheus URL: $PROMETHEUS_URL"
    echo "  Alert Email: $ALERT_EMAIL"
    echo ""

    log_info "Monitored Events:"
    echo "  ✓ SSH authentication (success/failure)"
    echo "  ✓ Sudo command execution"
    echo "  ✓ Fail2Ban bans/unbans"
    echo "  ✓ Nginx access and errors"
    echo "  ✓ Laravel application events"
    echo "  ✓ PostgreSQL database events"
    echo "  ✓ AIDE file integrity alerts"
    echo "  ✓ System logs"
    echo ""

    log_info "Log Sources:"
    echo "  /var/log/auth.log        - Authentication"
    echo "  /var/log/fail2ban.log    - Intrusion prevention"
    echo "  /var/log/nginx/          - Web server"
    echo "  ${APP_ROOT}/storage/logs/ - Application"
    echo "  /var/log/aide/           - File integrity"
    echo "  /var/log/postgresql/     - Database"
    echo ""

    log_info "Management Commands:"
    echo "  chom-audit-logs ssh              - SSH events"
    echo "  chom-audit-logs fail2ban         - Fail2Ban events"
    echo "  chom-audit-logs suspicious       - Suspicious activity"
    echo "  systemctl status promtail        - Check Promtail"
    echo ""

    log_info "Dashboards:"
    echo "  Grafana Security: $GRAFANA_URL/d/chom-security"
    echo ""

    log_warning "NEXT STEPS:"
    echo "  1. Configure alert rules in Grafana"
    echo "  2. Set up email notifications"
    echo "  3. Review dashboards regularly"
    echo "  4. Test alert delivery"
    echo "  5. Document incident response procedures"
    echo ""
}

# Main execution
main() {
    log_info "Starting security monitoring setup..."
    echo ""

    check_root
    install_promtail
    configure_promtail
    create_promtail_service
    configure_security_logging
    configure_laravel_logging
    create_audit_log_script
    create_grafana_dashboard
    test_monitoring
    display_summary

    log_success "Security monitoring setup complete!"
}

# Run main function
main "$@"
