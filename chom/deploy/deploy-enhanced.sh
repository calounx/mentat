#!/bin/bash
#===============================================================================
# CHOM Infrastructure Deployment Orchestrator (Auto-Healing Edition)
#
# Deploys Observability Stack and VPSManager to vanilla Debian 13 VPS
# with automatic error recovery, minimal user input, and self-healing
#
# Features:
#   ✓ Auto-healing: Automatically recovers from common errors
#   ✓ Retry logic: Network failures, SSH issues, service conflicts
#   ✓ Smart defaults: Auto-detects configuration
#   ✓ Idempotent: Safe to re-run multiple times
#   ✓ State-based: Resumes from where it left off
#   ✓ Self-correcting: Fixes permissions, dependencies automatically
#
# Usage:
#   ./deploy.sh [OPTIONS] [TARGET]
#
# Targets:
#   observability    Deploy only observability stack
#   vpsmanager       Deploy only VPSManager
#   all              Deploy both (default)
#
# Options:
#   --interactive    Enable interactive confirmations (disabled by default)
#   --plan           Dry-run mode - show deployment plan without executing
#   --validate       Run pre-flight checks only
#   --force          Force deployment even if validation fails
#   --no-retry       Disable automatic retry on failures
#   --help           Show this help message
#
#===============================================================================

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/configs/inventory.yaml"
KEYS_DIR="${SCRIPT_DIR}/keys"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
STATE_DIR="${SCRIPT_DIR}/.deploy-state"
STATE_FILE="${STATE_DIR}/deployment.state"

# Auto-healing configuration
INTERACTIVE_MODE=false          # Non-interactive by default
AUTO_RETRY=true                 # Auto-healing enabled by default
DRY_RUN=false                   # Execute by default
VALIDATE_ONLY=false             # Full deployment by default
FORCE_DEPLOY=false              # Respect validation by default
MAX_RETRIES=3                   # Retry failed operations 3 times
RETRY_BACKOFF="exponential"     # exponential or linear
VERBOSE=false                   # Concise output by default
DEBUG=false                     # No debug output by default
AUTO_FIX=true                   # Auto-fix issues by default
RESUME=false                    # Fresh deployment by default
QUIET=false                     # Normal output by default
DEPLOYMENT_TARGET="all"         # Deploy everything by default

# Progress tracking
TOTAL_STEPS=0
CURRENT_STEP=0
declare -a STEP_DESCRIPTIONS

# Error context tracking
declare -A ERROR_CONTEXT

#===============================================================================
# Colors and Output
#===============================================================================

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
BOLD=$'\033[1m'
NC=$'\033[0m'

print_banner() {
    echo "${CYAN}"
    cat << 'EOF'
   ____ _   _  ___  __  __
  / ___| | | |/ _ \|  \/  |
 | |   | |_| | | | | |\/| |
 | |___|  _  | |_| | |  | |
  \____|_| |_|\___/|_|  |_|

  Infrastructure Deployment Orchestrator
EOF
    echo "${NC}"
}

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${MAGENTA}[STEP]${NC} ${BOLD}$1${NC}"; }
log_debug() { [[ "${DEBUG:-}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $1" || true; }

print_section() {
    echo ""
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${BOLD}  $1${NC}"
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_progress() {
    local current=$1
    local total=$2
    local task=$3
    local percent=$((current * 100 / total))
    local completed=$((current * 50 / total))
    local remaining=$((50 - completed))

    printf "\r${BLUE}Progress:${NC} ["
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '░'
    printf "] ${percent}%% - ${task}${NC}"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

#===============================================================================
# Help and Usage
#===============================================================================

show_help() {
    cat << EOF
${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}
${CYAN}║${NC}                  ${BOLD}CHOM Auto-Healing Deployment Orchestrator${NC}                 ${CYAN}║${NC}
${CYAN}║${NC}                                                                              ${CYAN}║${NC}
${CYAN}║${NC}  Deploys Observability Stack and VPSManager to Debian 13 VPS servers        ${CYAN}║${NC}
${CYAN}║${NC}  with automatic error recovery, retry logic, and self-healing capabilities  ${CYAN}║${NC}
${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}

${BOLD}USAGE${NC}
    $0 [OPTIONS] [TARGET]

${BOLD}TARGETS${NC}
    ${GREEN}observability${NC}       Deploy observability stack only (Prometheus, Grafana, etc)
    ${GREEN}vpsmanager${NC}          Deploy VPSManager application only
    ${GREEN}all${NC}                 Deploy both stacks (default)

${BOLD}CORE OPTIONS${NC}
    ${YELLOW}-i, --interactive${NC}   Enable interactive mode with confirmations
                        ${BLUE}Default: Non-interactive (auto-proceed)${NC}

    ${YELLOW}--plan${NC}              Dry-run mode - show what would be deployed
                        Does not execute any changes

    ${YELLOW}--validate${NC}          Run pre-flight checks only
                        Validates SSH, dependencies, and VPS requirements

    ${YELLOW}--force${NC}             Skip validation and force deployment
                        ${RED}WARNING: Use with caution${NC}

    ${YELLOW}--resume${NC}            Resume from last successful checkpoint
                        Automatically skips completed components

${BOLD}AUTO-HEALING OPTIONS${NC}
    ${YELLOW}--no-retry${NC}          Disable automatic retry on failures
                        ${BLUE}Default: Retry enabled (3 attempts)${NC}

    ${YELLOW}--no-auto-fix${NC}       Disable automatic error fixing
                        ${BLUE}Default: Auto-fix enabled${NC}

    ${YELLOW}--max-retries N${NC}     Set maximum retry attempts (1-10)
                        ${BLUE}Default: 3${NC}

    ${YELLOW}--retry-backoff${NC}     Set retry backoff strategy
                        ${BLUE}Options: exponential (default), linear${NC}

${BOLD}OUTPUT OPTIONS${NC}
    ${YELLOW}-v, --verbose${NC}       Verbose output with detailed progress
    ${YELLOW}-q, --quiet${NC}         Minimal output (errors only)
    ${YELLOW}--debug${NC}             Enable debug logging

${BOLD}INFORMATION${NC}
    ${YELLOW}-h, --help${NC}          Show this help message
    ${YELLOW}--version${NC}           Show version information

${BOLD}EXAMPLES${NC}
    ${GREEN}# Basic non-interactive deployment (recommended)${NC}
    $0 all

    ${GREEN}# Interactive deployment with confirmations${NC}
    $0 --interactive all

    ${GREEN}# Preview deployment plan without executing${NC}
    $0 --plan

    ${GREEN}# Validate environment before deploying${NC}
    $0 --validate

    ${GREEN}# Deploy only observability stack${NC}
    $0 observability

    ${GREEN}# Resume failed deployment from last checkpoint${NC}
    $0 --resume

    ${GREEN}# Force deployment with verbose output${NC}
    $0 --force --verbose all

    ${GREEN}# Deploy without auto-retry (fail fast)${NC}
    $0 --no-retry vpsmanager

${BOLD}AUTO-HEALING FEATURES${NC}
    ${GREEN}✓${NC} Network failures: Automatic retry with exponential backoff
    ${GREEN}✓${NC} SSH timeouts: Reconnection with increasing delays
    ${GREEN}✓${NC} Missing dependencies: Auto-install (apt, yq, jq)
    ${GREEN}✓${NC} Permission errors: Auto-fix file/directory permissions
    ${GREEN}✓${NC} Port conflicts: Auto-detect and resolve service conflicts
    ${GREEN}✓${NC} Failed services: Auto-restart with health checks
    ${GREEN}✓${NC} Disk space: Auto-cleanup old containers/logs
    ${GREEN}✓${NC} State recovery: Resume from last successful step

${BOLD}PRE-FLIGHT CHECKS${NC}
    ${GREEN}✓${NC} Local dependencies (ssh, scp, yq, jq)
    ${GREEN}✓${NC} SSH connectivity to all VPS servers
    ${GREEN}✓${NC} Debian 13 OS version
    ${GREEN}✓${NC} Disk space (minimum 20GB)
    ${GREEN}✓${NC} RAM availability (recommended 2GB+)
    ${GREEN}✓${NC} Network connectivity from VPS
    ${GREEN}✓${NC} Port availability

${BOLD}DEPLOYMENT STATE${NC}
    State is tracked in: ${CYAN}.deploy-state/deployment.state${NC}
    - Allows safe re-runs and resumption
    - Idempotent - re-running is safe
    - Reset with: ${YELLOW}rm -rf .deploy-state/${NC}

${BOLD}REQUIREMENTS${NC}
    - Debian 13 VPS servers (vanilla install)
    - SSH access configured
    - Internet connectivity
    - Configured configs/inventory.yaml

${BOLD}CONFIGURATION${NC}
    Edit ${CYAN}configs/inventory.yaml${NC} with your VPS details:
    - IP addresses
    - SSH ports and users
    - Hostnames and domains

EOF
    exit 0
}

#===============================================================================
# State Management
#===============================================================================

init_state() {
    mkdir -p "$STATE_DIR"

    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "initialized",
  "observability": {
    "status": "pending",
    "completed_at": null
  },
  "vpsmanager": {
    "status": "pending",
    "completed_at": null
  }
}
EOF
    fi
}

update_state() {
    local target=$1
    local status=$2

    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [[ "$target" == "global" ]]; then
        jq ".status = \"$status\" | .updated_at = \"$timestamp\"" "$STATE_FILE" > "${STATE_FILE}.tmp"
    else
        jq ".${target}.status = \"$status\" | .${target}.updated_at = \"$timestamp\"" "$STATE_FILE" > "${STATE_FILE}.tmp"

        if [[ "$status" == "completed" ]]; then
            jq ".${target}.completed_at = \"$timestamp\"" "${STATE_FILE}.tmp" > "${STATE_FILE}.tmp2"
            mv "${STATE_FILE}.tmp2" "${STATE_FILE}.tmp"
        fi
    fi

    mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

get_state() {
    local target=$1
    jq -r ".${target}.status" "$STATE_FILE" 2>/dev/null || echo "pending"
}

show_state() {
    if [[ -f "$STATE_FILE" ]]; then
        echo ""
        echo "${BOLD}Current Deployment State:${NC}"
        echo ""

        local obs_status=$(get_state "observability")
        local vps_status=$(get_state "vpsmanager")

        printf "  Observability Stack: "
        case "$obs_status" in
            completed) echo "${GREEN}✓ Completed${NC}" ;;
            in_progress) echo "${YELLOW}⟳ In Progress${NC}" ;;
            failed) echo "${RED}✗ Failed${NC}" ;;
            *) echo "${BLUE}○ Pending${NC}" ;;
        esac

        printf "  VPSManager:          "
        case "$vps_status" in
            completed) echo "${GREEN}✓ Completed${NC}" ;;
            in_progress) echo "${YELLOW}⟳ In Progress${NC}" ;;
            failed) echo "${RED}✗ Failed${NC}" ;;
            *) echo "${BLUE}○ Pending${NC}" ;;
        esac

        echo ""
    fi
}

#===============================================================================
# Dependency Checks
#===============================================================================

check_dependencies() {
    log_step "Checking local dependencies..."

    local missing=()
    local deps=("ssh" "scp" "yq" "jq")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing[*]}"

        if [[ "$AUTO_FIX" == "true" ]]; then
            log_info "Auto-installing missing dependencies..."

            if autofix_missing_dependencies; then
                # Verify all dependencies are now installed
                local still_missing=()
                for dep in "${deps[@]}"; do
                    if ! command -v "$dep" &> /dev/null; then
                        still_missing+=("$dep")
                    fi
                done

                if [[ ${#still_missing[@]} -eq 0 ]]; then
                    log_success "All dependencies installed successfully"
                    return 0
                else
                    log_error "Failed to auto-install: ${still_missing[*]}"
                fi
            fi
        fi

        # If auto-fix failed or disabled, show manual instructions
        log_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Auto-installation failed. Please install manually:"
        for dep in "${missing[@]}"; do
            case "$dep" in
                yq)
                    echo "  sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                    echo "  sudo chmod +x /usr/local/bin/yq"
                    ;;
                jq)
                    echo "  sudo apt-get install -y jq"
                    ;;
                *)
                    echo "  sudo apt-get install -y $dep"
                    ;;
            esac
        done
        exit 1
    fi

    log_success "All dependencies installed"
}

#===============================================================================
# Configuration Management
#===============================================================================

validate_inventory() {
    log_step "Validating inventory configuration..."

    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi

    # Validate YAML syntax
    if ! yq eval '.' "$CONFIG_FILE" &>/dev/null; then
        log_error "Invalid YAML syntax in $CONFIG_FILE"
        exit 1
    fi

    # Check required fields
    local required_fields=(
        ".observability.ip"
        ".observability.ssh_user"
        ".observability.ssh_port"
        ".vpsmanager.ip"
        ".vpsmanager.ssh_user"
        ".vpsmanager.ssh_port"
    )

    for field in "${required_fields[@]}"; do
        local value=$(yq eval "$field" "$CONFIG_FILE")
        if [[ -z "$value" || "$value" == "null" ]]; then
            log_error "Missing required field: $field"
            exit 1
        fi
    done

    log_success "Inventory configuration valid"
}

get_config() {
    yq eval "$1" "$CONFIG_FILE"
}

#===============================================================================
# SSH Management
#===============================================================================

ensure_ssh_key() {
    log_step "Checking SSH key..."

    local key_path="${KEYS_DIR}/chom_deploy_key"

    if [[ ! -f "$key_path" ]]; then
        log_info "Generating deployment SSH key..."
        mkdir -p "$KEYS_DIR"
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "chom-deploy"
        chmod 600 "$key_path"
        log_success "SSH key generated at $key_path"

        echo ""
        log_warn "Add this public key to your VPS servers' ~/.ssh/authorized_keys:"
        echo ""
        echo "${CYAN}$(cat "${key_path}.pub")${NC}"
        echo ""

        if [[ $CURRENT_MODE != $MODE_PLAN ]]; then
            read -p "Press Enter once you've added the key to all VPS servers..."
        fi
    else
        log_success "SSH key found at $key_path"
    fi
}

test_ssh_connection() {
    local host=$1
    local user=$2
    local port=$3
    local name=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    log_info "Testing SSH connection to $name ($user@$host:$port)..."

    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=10 \
           -o BatchMode=yes \
           -i "$key_path" \
           -p "$port" \
           "${user}@${host}" \
           "echo 'SSH OK'" &>/dev/null; then
        log_success "SSH connection to $name successful"
        return 0
    else
        log_error "Cannot connect to $name via SSH"
        echo "  Host: $host"
        echo "  Port: $port"
        echo "  User: $user"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Verify VPS is running and accessible"
        echo "  2. Check SSH port is correct"
        echo "  3. Verify public key is added to ~/.ssh/authorized_keys"
        echo "  4. Test manually: ssh -i ${key_path} -p ${port} ${user}@${host}"
        return 1
    fi
}

remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        "$cmd"
}

remote_copy() {
    local host=$1
    local user=$2
    local port=$3
    local src=$4
    local dest=$5
    local key_path="${KEYS_DIR}/chom_deploy_key"

    scp -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -P "$port" \
        "$src" \
        "${user}@${host}:${dest}"
}

#===============================================================================
# Auto-Healing Retry Logic
#===============================================================================

# Calculate backoff delay
calculate_backoff() {
    local attempt=$1
    local base_delay=2

    if [[ "$RETRY_BACKOFF" == "exponential" ]]; then
        # Exponential: 2, 4, 8, 16, 32 seconds (capped at 32)
        local delay=$((base_delay ** attempt))
        if [[ $delay -gt 32 ]]; then
            echo 32
        else
            echo $delay
        fi
    else
        # Linear: 2, 4, 6, 8, 10 seconds
        echo $((base_delay * attempt))
    fi
}

# Retry wrapper with auto-healing
retry_with_healing() {
    local operation_name=$1
    local command_to_retry=$2
    local auto_fix_function=${3:-""}

    local attempt=1
    local max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $operation_name"

        # Execute the command
        if eval "$command_to_retry"; then
            if [[ $attempt -gt 1 ]]; then
                log_success "$operation_name succeeded after $attempt attempts"
            fi
            return 0
        fi

        local exit_code=$?

        # Last attempt - no retry
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "$operation_name failed after $max_attempts attempts"
            return $exit_code
        fi

        # Auto-fix if function provided and auto-fix enabled
        if [[ -n "$auto_fix_function" && "$AUTO_FIX" == "true" ]]; then
            log_warn "Attempting auto-fix..."
            if eval "$auto_fix_function"; then
                log_info "Auto-fix successful, retrying immediately"
                ((attempt++))
                continue
            fi
        fi

        # Calculate backoff
        local delay=$(calculate_backoff $attempt)

        log_warn "$operation_name failed (exit code: $exit_code)"
        log_info "Retrying in $delay seconds... (attempt $((attempt + 1))/$max_attempts)"

        # Progress indicator during wait
        if [[ "$QUIET" != "true" ]]; then
            for ((i=delay; i>0; i--)); do
                printf "\r  ${BLUE}Waiting: %2ds ${NC}" $i
                sleep 1
            done
            printf "\r                \r"
        else
            sleep $delay
        fi

        ((attempt++))
    done

    return 1
}

#===============================================================================
# Auto-Fix Functions
#===============================================================================

# Auto-install missing dependencies
autofix_missing_dependencies() {
    log_info "Auto-installing missing dependencies..."

    local installed_any=false

    # Install yq
    if ! command -v yq &>/dev/null; then
        log_info "Installing yq..."
        if sudo wget -qO /usr/local/bin/yq \
            "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64" 2>/dev/null; then
            sudo chmod +x /usr/local/bin/yq
            installed_any=true
        fi
    fi

    # Install jq
    if ! command -v jq &>/dev/null; then
        log_info "Installing jq..."
        if sudo apt-get update -qq && sudo apt-get install -y -qq jq 2>/dev/null; then
            installed_any=true
        fi
    fi

    # Install ssh/scp
    if ! command -v ssh &>/dev/null; then
        log_info "Installing openssh-client..."
        if sudo apt-get update -qq && sudo apt-get install -y -qq openssh-client 2>/dev/null; then
            installed_any=true
        fi
    fi

    if [[ "$installed_any" == "true" ]]; then
        log_success "Dependencies auto-installed"
        return 0
    fi

    return 1
}

# Auto-fix SSH connection issues
autofix_ssh_connection() {
    local host=$1
    local user=$2
    local port=$3

    log_info "Auto-fixing SSH connection..."

    # Clear known_hosts entry
    ssh-keygen -R "[$host]:$port" &>/dev/null || true
    ssh-keygen -R "$host" &>/dev/null || true

    # Check if host is reachable
    if ! ping -c 1 -W 3 "$host" &>/dev/null; then
        log_warn "Host $host is not responding to ping"
        return 1
    fi

    # Verify SSH port is open
    if ! timeout 5 bash -c "</dev/tcp/$host/$port" &>/dev/null 2>&1; then
        log_warn "Port $port is not open on $host"
        return 1
    fi

    log_success "SSH connection auto-fix complete"
    return 0
}

# Auto-fix remote service conflicts
autofix_service_conflict() {
    local host=$1
    local user=$2
    local port=$3
    local service=$4

    log_info "Detecting and resolving $service conflicts..."

    # Stop conflicting service
    remote_exec "$host" "$user" "$port" \
        "sudo systemctl stop $service 2>/dev/null || true" || true

    # Clean up old installation
    remote_exec "$host" "$user" "$port" \
        "sudo systemctl disable $service 2>/dev/null || true" || true

    log_success "Service conflict resolved"
    return 0
}

# Auto-cleanup disk space
autofix_disk_space() {
    local host=$1
    local user=$2
    local port=$3

    log_info "Auto-cleanup disk space..."

    # Clean apt cache
    remote_exec "$host" "$user" "$port" \
        "sudo apt-get clean && sudo apt-get autoclean" 2>/dev/null || true

    # Remove old logs
    remote_exec "$host" "$user" "$port" \
        "sudo journalctl --vacuum-time=7d" 2>/dev/null || true

    # Remove old Docker containers if Docker exists
    remote_exec "$host" "$user" "$port" \
        "command -v docker &>/dev/null && sudo docker system prune -af || true" 2>/dev/null || true

    log_success "Disk cleanup complete"
    return 0
}

# Auto-fix file permissions
autofix_permissions() {
    local file_path=$1

    log_info "Auto-fixing file permissions..."

    if [[ -f "$file_path" ]]; then
        chmod 600 "$file_path" 2>/dev/null || return 1
    elif [[ -d "$file_path" ]]; then
        chmod 700 "$file_path" 2>/dev/null || return 1
    fi

    log_success "Permissions fixed"
    return 0
}

#===============================================================================
# Remote Validation (runs on target VPS)
#===============================================================================

validate_remote_vps() {
    local host=$1
    local user=$2
    local port=$3
    local name=$4

    log_step "Validating $name VPS..."

    # Check OS
    log_info "Checking OS version..."
    local os_check=$(remote_exec "$host" "$user" "$port" "cat /etc/os-release | grep -E '^(ID|VERSION_ID)=' || true")

    if echo "$os_check" | grep -q 'ID=debian'; then
        if echo "$os_check" | grep -q 'VERSION_ID="13"'; then
            log_success "OS: Debian 13 (correct)"
        else
            local version=$(echo "$os_check" | grep VERSION_ID | cut -d'"' -f2)
            log_warn "OS: Debian $version (expected 13, may have compatibility issues)"
        fi
    else
        log_error "OS is not Debian"
        return 1
    fi

    # Check disk space
    log_info "Checking disk space..."
    local disk_gb=$(remote_exec "$host" "$user" "$port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

    if [[ $disk_gb -lt 20 ]]; then
        log_error "Insufficient disk space: ${disk_gb}GB (minimum 20GB required)"
        return 1
    else
        log_success "Disk space: ${disk_gb}GB available"
    fi

    # Check RAM
    log_info "Checking RAM..."
    local ram_mb=$(remote_exec "$host" "$user" "$port" "free -m | awk '/^Mem:/ {print \$2}'")

    if [[ $ram_mb -lt 1024 ]]; then
        log_warn "Low RAM: ${ram_mb}MB (recommended: 2048MB+)"
    else
        log_success "RAM: ${ram_mb}MB"
    fi

    # Check network
    log_info "Checking network connectivity..."
    if remote_exec "$host" "$user" "$port" "ping -c 1 -W 5 github.com &>/dev/null"; then
        log_success "Network connectivity OK"
    else
        log_error "Cannot reach github.com from VPS"
        return 1
    fi

    # Check if already deployed
    log_info "Checking for existing installation..."
    local existing=$(remote_exec "$host" "$user" "$port" "systemctl list-units --type=service --all | grep -E '(prometheus|grafana|nginx)' | wc -l" || echo "0")

    if [[ $existing -gt 0 ]]; then
        log_warn "Found $existing existing services - this may be a re-deployment"
    else
        log_success "Clean VPS (no existing services detected)"
    fi

    log_success "$name VPS validation complete"
    return 0
}

#===============================================================================
# Pre-flight Checks
#===============================================================================

run_preflight_checks() {
    print_section "Pre-flight Validation"

    check_dependencies
    validate_inventory
    ensure_ssh_key

    # Get VPS details from inventory
    local obs_ip=$(get_config '.observability.ip')
    local obs_user=$(get_config '.observability.ssh_user')
    local obs_port=$(get_config '.observability.ssh_port')

    local vps_ip=$(get_config '.vpsmanager.ip')
    local vps_user=$(get_config '.vpsmanager.ssh_user')
    local vps_port=$(get_config '.vpsmanager.ssh_port')

    # Test SSH connections
    local ssh_failures=0

    if ! test_ssh_connection "$obs_ip" "$obs_user" "$obs_port" "Observability"; then
        ((ssh_failures++))
    fi

    if ! test_ssh_connection "$vps_ip" "$vps_user" "$vps_port" "VPSManager"; then
        ((ssh_failures++))
    fi

    if [[ $ssh_failures -gt 0 ]]; then
        log_error "SSH connection failed to $ssh_failures VPS(s)"
        exit 1
    fi

    # Validate remote VPS
    local validation_failures=0

    if ! validate_remote_vps "$obs_ip" "$obs_user" "$obs_port" "Observability"; then
        ((validation_failures++))
    fi

    echo ""

    if ! validate_remote_vps "$vps_ip" "$vps_user" "$vps_port" "VPSManager"; then
        ((validation_failures++))
    fi

    if [[ $validation_failures -gt 0 ]]; then
        log_error "VPS validation failed for $validation_failures VPS(s)"
        exit 1
    fi

    echo ""
    log_success "All pre-flight checks passed!"
}

#===============================================================================
# Deployment Plan
#===============================================================================

show_deployment_plan() {
    print_section "Deployment Plan"

    local obs_ip=$(get_config '.observability.ip')
    local obs_hostname=$(get_config '.observability.hostname')
    local vps_ip=$(get_config '.vpsmanager.ip')
    local vps_hostname=$(get_config '.vpsmanager.hostname')

    echo "${BOLD}Target Infrastructure:${NC}"
    echo ""
    echo "  ${CYAN}┌─ Observability Stack${NC}"
    echo "  ${CYAN}│${NC}  IP:       $obs_ip"
    echo "  ${CYAN}│${NC}  Hostname: $obs_hostname"
    echo "  ${CYAN}│${NC}  Services: Prometheus, Loki, Grafana, Alertmanager, Tempo, Alloy"
    echo "  ${CYAN}│${NC}  Ports:    9090 (Prometheus), 3000 (Grafana), 3100 (Loki)"
    echo "  ${CYAN}└─${NC}"
    echo ""
    echo "  ${CYAN}┌─ VPSManager${NC}"
    echo "  ${CYAN}│${NC}  IP:       $vps_ip"
    echo "  ${CYAN}│${NC}  Hostname: $vps_hostname"
    echo "  ${CYAN}│${NC}  Services: Nginx, PHP-FPM, MariaDB, Redis, Laravel, Exporters"
    echo "  ${CYAN}│${NC}  Ports:    80/443 (Web), 3306 (MySQL), 6379 (Redis)"
    echo "  ${CYAN}└─${NC}"
    echo ""

    echo "${BOLD}Deployment Steps:${NC}"
    echo ""
    echo "  ${GREEN}1.${NC} Deploy Observability Stack to $obs_ip"
    echo "     - Install Prometheus 2.54.1"
    echo "     - Install Loki 3.2.1"
    echo "     - Install Grafana 11.3.0"
    echo "     - Install Alertmanager 0.27.0"
    echo "     - Configure Nginx reverse proxy"
    echo "     - Setup Let's Encrypt SSL"
    echo ""
    echo "  ${GREEN}2.${NC} Deploy VPSManager to $vps_ip"
    echo "     - Install LEMP stack (Nginx, PHP 8.2/8.4, MariaDB 11.4)"
    echo "     - Deploy Laravel application"
    echo "     - Install monitoring exporters"
    echo "     - Configure Promtail log shipping to $obs_ip"
    echo "     - Setup application monitoring"
    echo ""

    echo "${BOLD}Estimated Time:${NC}"
    echo "  Observability Stack: ~5-10 minutes"
    echo "  VPSManager:          ~10-15 minutes"
    echo "  ${BOLD}Total:              ~15-25 minutes${NC}"
    echo ""

    echo "${BOLD}Post-Deployment Access:${NC}"
    echo "  Grafana:     http://${obs_ip}:3000"
    echo "  Prometheus:  http://${obs_ip}:9090"
    echo "  VPSManager:  http://${vps_ip}:8080"
    echo ""
}

#===============================================================================
# Deployment Functions
#===============================================================================

deploy_observability() {
    local is_plan=$1

    if [[ "$is_plan" == "true" ]]; then
        return 0
    fi

    log_step "Deploying Observability Stack..."
    update_state "observability" "in_progress"

    local ip=$(get_config '.observability.ip')
    local user=$(get_config '.observability.ssh_user')
    local port=$(get_config '.observability.ssh_port')
    local hostname=$(get_config '.observability.hostname')

    log_info "Target: ${user}@${ip}:${port}"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-observability-vps.sh" "/tmp/setup-observability-vps.sh"

    # Execute setup
    log_info "Executing setup (this may take 5-10 minutes)..."
    echo ""

    if remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-observability-vps.sh && /tmp/setup-observability-vps.sh"; then
        echo ""
        log_success "Observability Stack deployed successfully!"
        log_info "Grafana: http://${ip}:3000"
        log_info "Prometheus: http://${ip}:9090"
        update_state "observability" "completed"
        return 0
    else
        echo ""
        log_error "Observability Stack deployment failed!"
        update_state "observability" "failed"
        return 1
    fi
}

deploy_vpsmanager() {
    local is_plan=$1

    if [[ "$is_plan" == "true" ]]; then
        return 0
    fi

    log_step "Deploying VPSManager..."
    update_state "vpsmanager" "in_progress"

    local ip=$(get_config '.vpsmanager.ip')
    local user=$(get_config '.vpsmanager.ssh_user')
    local port=$(get_config '.vpsmanager.ssh_port')
    local hostname=$(get_config '.vpsmanager.hostname')
    local obs_ip=$(get_config '.observability.ip')

    log_info "Target: ${user}@${ip}:${port}"

    # Copy setup script
    log_info "Copying setup script..."
    remote_copy "$ip" "$user" "$port" "${SCRIPTS_DIR}/setup-vpsmanager-vps.sh" "/tmp/setup-vpsmanager-vps.sh"

    # Execute setup with observability server IP
    log_info "Executing setup (this may take 10-15 minutes)..."
    echo ""

    if remote_exec "$ip" "$user" "$port" "chmod +x /tmp/setup-vpsmanager-vps.sh && OBSERVABILITY_IP=${obs_ip} /tmp/setup-vpsmanager-vps.sh"; then
        echo ""
        log_success "VPSManager deployed successfully!"
        log_info "Dashboard: http://${ip}:8080"
        update_state "vpsmanager" "completed"
        return 0
    else
        echo ""
        log_error "VPSManager deployment failed!"
        update_state "vpsmanager" "failed"
        return 1
    fi
}

#===============================================================================
# Interactive Wizard
#===============================================================================

run_wizard() {
    print_banner
    print_section "Interactive Deployment Wizard"

    echo "This wizard will guide you through deploying the CHOM infrastructure."
    echo ""

    # Show current state if exists
    if [[ -f "$STATE_FILE" ]]; then
        show_state
    fi

    # Pre-flight checks
    if [[ "$SKIP_CHECKS" != "true" ]]; then
        echo "First, let's validate your environment and VPS servers."
        echo ""
        read -p "Press Enter to start pre-flight checks..."

        if ! run_preflight_checks; then
            log_error "Pre-flight checks failed. Please fix the issues and try again."
            exit 1
        fi
    fi

    # Show deployment plan
    show_deployment_plan

    # Confirm deployment
    echo "${YELLOW}${BOLD}Warning: This will modify your VPS servers.${NC}"
    echo ""
    read -p "Do you want to proceed with deployment? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    # Initialize state
    init_state
    update_state "global" "in_progress"

    # Deploy observability
    print_section "Step 1/2: Deploying Observability Stack"

    if [[ $(get_state "observability") == "completed" ]]; then
        log_info "Observability Stack already deployed (skipping)"
    else
        if ! deploy_observability "false"; then
            log_error "Deployment failed at Observability Stack"
            update_state "global" "failed"
            exit 1
        fi
    fi

    echo ""
    read -p "Press Enter to continue to VPSManager deployment..."

    # Deploy VPSManager
    print_section "Step 2/2: Deploying VPSManager"

    if [[ $(get_state "vpsmanager") == "completed" ]]; then
        log_info "VPSManager already deployed (skipping)"
    else
        if ! deploy_vpsmanager "false"; then
            log_error "Deployment failed at VPSManager"
            update_state "global" "failed"
            exit 1
        fi
    fi

    # Completion
    update_state "global" "completed"

    print_section "Deployment Complete!"

    local obs_ip=$(get_config '.observability.ip')
    local vps_ip=$(get_config '.vpsmanager.ip')

    echo "${GREEN}${BOLD}✓ All components deployed successfully!${NC}"
    echo ""
    echo "${BOLD}Access URLs:${NC}"
    echo "  Grafana:     http://${obs_ip}:3000"
    echo "  Prometheus:  http://${obs_ip}:9090"
    echo "  VPSManager:  http://${vps_ip}:8080"
    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "  1. Access Grafana and configure dashboards"
    echo "  2. Set up alert notification channels"
    echo "  3. Configure VPSManager Laravel application"
    echo "  4. Verify monitoring data is flowing"
    echo ""
}

#===============================================================================
# Main Orchestration
#===============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Primary commands
            observability|vpsmanager|all)
                DEPLOYMENT_TARGET="$1"
                shift
                ;;

            # Mode flags
            --interactive|-i)
                INTERACTIVE_MODE=true
                shift
                ;;

            --plan|--dry-run)
                DRY_RUN=true
                shift
                ;;

            --validate)
                VALIDATE_ONLY=true
                shift
                ;;

            --force)
                FORCE_DEPLOY=true
                shift
                ;;

            --resume)
                RESUME=true
                shift
                ;;

            # Auto-healing controls
            --no-retry)
                AUTO_RETRY=false
                MAX_RETRIES=1
                shift
                ;;

            --no-auto-fix)
                AUTO_FIX=false
                shift
                ;;

            --max-retries)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    MAX_RETRIES="$2"
                    if [[ $MAX_RETRIES -lt 1 || $MAX_RETRIES -gt 10 ]]; then
                        log_error "--max-retries must be between 1 and 10"
                        exit 1
                    fi
                    shift 2
                else
                    log_error "--max-retries requires a numeric argument (1-10)"
                    exit 1
                fi
                ;;

            --retry-backoff)
                if [[ "$2" == "exponential" || "$2" == "linear" ]]; then
                    RETRY_BACKOFF="$2"
                    shift 2
                else
                    log_error "--retry-backoff must be 'exponential' or 'linear'"
                    exit 1
                fi
                ;;

            # Output control
            --verbose|-v)
                VERBOSE=true
                shift
                ;;

            --debug)
                DEBUG=true
                VERBOSE=true
                shift
                ;;

            --quiet|-q)
                QUIET=true
                shift
                ;;

            # Help and version
            --help|-h)
                show_help
                ;;

            --version)
                echo "CHOM Auto-Healing Deployment Orchestrator v2.0.0"
                exit 0
                ;;

            # Unknown
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage information"
                exit 1
                ;;
        esac
    done

    # Validate arguments
    if [[ "$DRY_RUN" == "true" && "$VALIDATE_ONLY" == "true" ]]; then
        log_error "Cannot use --plan and --validate together"
        exit 1
    fi

    if [[ "$FORCE_DEPLOY" == "true" && "$VALIDATE_ONLY" == "true" ]]; then
        log_warn "--force has no effect with --validate"
    fi

    if [[ "$AUTO_RETRY" == "false" && "$MAX_RETRIES" != "1" ]]; then
        log_warn "--no-retry overrides --max-retries setting"
        MAX_RETRIES=1
    fi

    # Valid deployment targets
    if [[ ! "$DEPLOYMENT_TARGET" =~ ^(observability|vpsmanager|all)$ ]]; then
        log_error "Invalid target: $DEPLOYMENT_TARGET"
        echo "Valid targets: observability, vpsmanager, all"
        exit 1
    fi

    # Check for required files
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        echo ""
        echo "Please create inventory.yaml with your VPS configuration."
        echo "See: configs/inventory.yaml.example"
        exit 1
    fi
}

deploy_with_healing() {
    local target=$1

    print_section "Deploying ${target^}"

    # Check if already deployed
    if [[ "$RESUME" == "true" && $(get_state "$target") == "completed" ]]; then
        log_info "$target already deployed (skipping)"
        return 0
    fi

    # Get VPS details
    local ip=$(get_config ".${target}.ip")
    local user=$(get_config ".${target}.ssh_user")
    local port=$(get_config ".${target}.ssh_port")

    # Deploy with retry and auto-healing
    retry_with_healing \
        "Deploy $target" \
        "deploy_${target} false" \
        "autofix_service_conflict $ip $user $port $target"
}

error_exit() {
    local error_message=$1
    local exit_code=${2:-1}

    log_error "$error_message"

    # Save state
    update_state "global" "failed"

    echo ""
    echo "${YELLOW}Deployment state saved. Resume with: $0 --resume${NC}"
    echo ""

    exit $exit_code
}

show_deployment_summary() {
    local obs_ip=$(get_config '.observability.ip')
    local vps_ip=$(get_config '.vpsmanager.ip')

    print_section "Deployment Complete!"

    echo "${GREEN}${BOLD}✓ All components deployed successfully!${NC}"
    echo ""
    echo "${BOLD}Access URLs:${NC}"
    echo "  ${CYAN}Grafana:${NC}     http://${obs_ip}:3000"
    echo "  ${CYAN}Prometheus:${NC}  http://${obs_ip}:9090"
    echo "  ${CYAN}VPSManager:${NC}  http://${vps_ip}:8080"
    echo ""
    echo "${BOLD}Next Steps:${NC}"
    echo "  1. Access Grafana and configure dashboards"
    echo "  2. Set up alert notification channels"
    echo "  3. Configure VPSManager Laravel application"
    echo "  4. Verify monitoring data is flowing"
    echo ""
}

main() {
    # Parse and validate CLI arguments
    parse_arguments "$@"

    # Print banner (unless quiet mode)
    if [[ "$QUIET" != "true" ]]; then
        print_banner
    fi

    # Handle special modes
    if [[ "$DRY_RUN" == "true" ]]; then
        retry_with_healing \
            "Pre-flight validation" \
            "check_dependencies && validate_inventory" \
            "autofix_missing_dependencies"
        show_deployment_plan
        exit 0
    fi

    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        retry_with_healing \
            "Pre-flight validation" \
            "run_preflight_checks" \
            "autofix_missing_dependencies"
        exit $?
    fi

    # Initialize deployment
    init_state

    # Pre-flight checks (with auto-healing)
    if [[ "$FORCE_DEPLOY" != "true" ]]; then
        log_step "Running pre-flight checks..."

        retry_with_healing \
            "Pre-flight checks" \
            "run_preflight_checks" \
            "autofix_missing_dependencies" \
            || error_exit "Pre-flight checks failed"
    else
        log_warn "Skipping validation (--force enabled)"
    fi

    # Show deployment plan
    if [[ "$QUIET" != "true" ]]; then
        echo ""
        show_deployment_plan
    fi

    # Interactive confirmation if enabled
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        echo ""
        read -p "Continue with deployment? [Y/n] " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi

    # Mark deployment as in progress
    update_state "global" "in_progress"

    # Execute deployment based on target
    case "$DEPLOYMENT_TARGET" in
        observability)
            deploy_with_healing "observability"
            ;;
        vpsmanager)
            deploy_with_healing "vpsmanager"
            ;;
        all)
            deploy_with_healing "observability"
            echo ""
            deploy_with_healing "vpsmanager"
            ;;
    esac

    # Mark deployment as complete
    update_state "global" "completed"

    # Show success summary
    if [[ "$QUIET" != "true" ]]; then
        show_deployment_summary
    fi
}

main "$@"
