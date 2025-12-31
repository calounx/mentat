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
#   ./deploy-enhanced.sh [OPTIONS] [TARGET]
#
# Targets:
#   observability    Deploy only observability stack
#   vpsmanager       Deploy only VPSManager
#   all              Deploy both (default)
#
# Minimal-Interaction 3-Step Workflow (DEFAULT):
#   Step 1: Auto-detect & validate (NO user input - auto-proceeds if green)
#   Step 2: Show deployment plan (NO user input - auto-displays plan)
#   Step 3: Single confirmation (1 user input - "Deploy? [Y/n]")
#   Then: Auto-pilot deployment (no more prompts)
#
# Options:
#   -y, --auto-approve   Skip ALL confirmations (for CI/CD - zero prompts)
#   -i, --interactive    Force legacy interactive mode (3+ prompts)
#   --plan               Dry-run mode - show deployment plan without executing
#   --validate           Run pre-flight checks only
#   --force              Force deployment even if validation fails
#   --no-retry           Disable automatic retry on failures
#   --help               Show this help message
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
INTERACTIVE_MODE=false          # Minimal interaction by default (1-prompt workflow)
AUTO_APPROVE=false              # Require confirmations by default (1 final prompt)
AUTO_RETRY=true                 # Auto-healing enabled by default
DRY_RUN=false                   # Execute by default
VALIDATE_ONLY=false             # Full deployment by default
FORCE_DEPLOY=false              # Respect validation by default
MAX_RETRIES=3                   # Retry failed operations 3 times
RETRY_BACKOFF="exponential"     # exponential or linear
# VERBOSE=false                 # Concise output by default (reserved for future use)
DEBUG=false                     # No debug output by default
AUTO_FIX=true                   # Auto-fix issues by default
RESUME=false                    # Fresh deployment by default
QUIET=false                     # Normal output by default
DEPLOYMENT_TARGET="all"         # Deploy everything by default

# Progress tracking
# TOTAL_STEPS=0  # Reserved for future use
# CURRENT_STEP=0  # Reserved for future use
# declare -a STEP_DESCRIPTIONS  # Reserved for future use

# Error context tracking
# declare -A ERROR_CONTEXT  # Reserved for future use

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
log_debug() { if [[ "${DEBUG:-}" == "1" ]]; then echo -e "${CYAN}[DEBUG]${NC} $1"; fi; }

print_section() {
    echo ""
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "${BOLD}  $1${NC}"
    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_progress() {
    local current
    current=$1
    local total
    total=$2
    local task
    task=$3
    local percent
    percent=$((current * 100 / total))
    local completed
    completed=$((current * 50 / total))
    local remaining
    remaining=$((50 - completed))

    printf "\r%sProgress:%s [" "${BLUE}" "${NC}"
    printf "%${completed}s" | tr ' ' '█'
    printf "%${remaining}s" | tr ' ' '░'
    printf "] ${percent}%% - ${task}${NC}"

    if [[ $current -eq $total ]]; then
        echo ""
    fi
}

#===============================================================================
# Cleanup and Signal Handling
#===============================================================================

# Cleanup state
CLEANUP_NEEDED=false
TEMP_FILES=()
LOCK_FILE=""
CURRENT_OPERATION=""

# Cleanup function called on exit
cleanup() {
    if [[ "$CLEANUP_NEEDED" == "true" ]]; then
        log_warn "Cleaning up..."

        # Clean temporary files
        for file in "${TEMP_FILES[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                log_debug "Removed temp file: $file"
            fi
        done

        # Save state if interrupted during operation
        if [[ -n "${CURRENT_OPERATION:-}" ]] && [[ -f "$STATE_FILE" ]]; then
            update_state "global" "interrupted" 2>/dev/null || true
            log_info "Deployment interrupted. Resume with: $0 --resume"
        fi

        # Release lock file
        if [[ -n "$LOCK_FILE" ]] && [[ -f "$LOCK_FILE" ]]; then
            rm -f "$LOCK_FILE"
            log_debug "Released deployment lock"
        fi
    fi
}

# Set up cleanup trap on normal exit
trap cleanup EXIT

# Handle interrupt signals (Ctrl+C)
handle_sigint() {
    echo ""  # New line after ^C
    log_warn "Received interrupt signal (Ctrl+C)"
    CLEANUP_NEEDED=true
    exit 130
}

# Handle termination signals
handle_sigterm() {
    echo ""
    log_warn "Received termination signal"
    CLEANUP_NEEDED=true
    exit 143
}

trap handle_sigint SIGINT
trap handle_sigterm SIGTERM

#===============================================================================
# Version and Requirements Validation
#===============================================================================

# Script version
readonly SCRIPT_VERSION="4.3.0"
# readonly SCRIPT_NAME="CHOM Auto-Healing Deployment Orchestrator"  # Unused
readonly MIN_BASH_VERSION="4.0"

# Check Bash version
check_bash_version() {
    local major
    major="${BASH_VERSINFO[0]}"
    # local minor="${BASH_VERSINFO[1]}"  # Unused

    if [[ $major -lt 4 ]]; then
        log_error "Bash ${MIN_BASH_VERSION} or higher required (you have ${BASH_VERSION})"
        log_error "This script uses associative arrays and other Bash 4+ features"
        echo ""
        echo "To upgrade Bash:"
        echo "  Ubuntu/Debian: sudo apt-get update && sudo apt-get install bash"
        echo "  RHEL/CentOS:   sudo yum update bash"
        echo "  macOS:         brew install bash"
        exit 1
    fi

    log_debug "Bash version check passed: ${BASH_VERSION}"
}

# Deployment lock management
acquire_lock() {
    LOCK_FILE="${STATE_DIR}/deploy.lock"

    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another deployment is already running (PID: $pid)"
            log_error "If this is incorrect, remove: $LOCK_FILE"
            exit 1
        else
            log_warn "Removing stale lock file (PID $pid not running)"
            rm -f "$LOCK_FILE"
        fi
    fi

    mkdir -p "$STATE_DIR"
    echo $$ > "$LOCK_FILE"
    log_debug "Acquired deployment lock (PID: $$)"
}

release_lock() {
    if [[ -n "$LOCK_FILE" ]] && [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log_debug "Released deployment lock"
    fi
}

#===============================================================================
# Help and Usage
#===============================================================================

show_help() {
    cat << EOF
${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}
${CYAN}║${NC}                  ${BOLD}CHOM Auto-Healing Deployment Orchestrator${NC}                 ${CYAN}║${NC}
${CYAN}║${NC}  Deploys Observability Stack and VPSManager to Debian 13 VPS servers        ${CYAN}║${NC}
${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}

${BOLD}QUICK START${NC}

    ${GREEN}First time?${NC} Just run the deployment script:

    ${CYAN}1.${NC} ${YELLOW}./deploy-enhanced.sh all${NC}             ${BLUE}# Minimal interaction (1 prompt)${NC}

    ${GREEN}For automation (CI/CD):${NC}

    ${YELLOW}./deploy-enhanced.sh --auto-approve all${NC}   ${BLUE}# Zero prompts - fully automated${NC}

    ${GREEN}Already deployed?${NC} Resume or update:

    ${YELLOW}./deploy-enhanced.sh --resume${NC}            ${BLUE}# Continue failed deployment${NC}

${BOLD}COMMON COMMANDS${NC}

    ${YELLOW}./deploy-enhanced.sh all${NC}                          Minimal interaction (1 prompt - default)
    ${YELLOW}./deploy-enhanced.sh -y all${NC}                       Zero prompts (auto-approve everything)
    ${YELLOW}./deploy-enhanced.sh --validate${NC}                   Pre-flight check only (no deployment)
    ${YELLOW}./deploy-enhanced.sh --plan${NC}                       Preview deployment plan (no execution)

${BOLD}TARGETS${NC}
    ${GREEN}all${NC}                 Deploy both stacks (default - recommended)
    ${GREEN}observability${NC}       Deploy only Prometheus, Grafana, Loki, Alertmanager
    ${GREEN}vpsmanager${NC}          Deploy only Laravel app with LEMP stack

${BOLD}ESSENTIAL OPTIONS${NC}
    ${YELLOW}--validate${NC}          Run pre-flight checks (SSH, disk space, OS version)
                        ${GREEN}Recommended before first deployment${NC}

    ${YELLOW}--plan${NC}              Dry-run - show deployment plan without executing
                        ${GREEN}Safe to run anytime${NC}

    ${YELLOW}--resume${NC}            Resume from last checkpoint after failure
                        ${GREEN}Automatically skips completed components${NC}

    ${YELLOW}-y, --auto-approve${NC}  Skip ALL confirmations (zero prompts - for CI/CD)
                        ${BLUE}Default: 1 final confirmation prompt${NC}

    ${YELLOW}-i, --interactive${NC}   Force legacy interactive mode (3+ prompts)
                        ${BLUE}Default: minimal interaction (1 prompt)${NC}

${BOLD}ADVANCED OPTIONS${NC} (for troubleshooting and customization)

    ${YELLOW}--force${NC}             Skip validation and force deployment
                        ${RED}Use with caution - may fail if requirements not met${NC}

    ${YELLOW}--no-retry${NC}          Disable automatic retry (fail fast)
    ${YELLOW}--no-auto-fix${NC}       Disable automatic error correction
    ${YELLOW}--max-retries N${NC}     Set retry attempts (1-10, default: 3)

    ${YELLOW}-v, --verbose${NC}       Show detailed progress logs
    ${YELLOW}-q, --quiet${NC}         Minimal output (errors only)
    ${YELLOW}--debug${NC}             Enable debug logging (very verbose)

${BOLD}HELP${NC}
    ${YELLOW}-h, --help${NC}          Show this help message
    ${YELLOW}--version${NC}           Show version information

${BOLD}WHAT HAPPENS DURING DEPLOYMENT?${NC}

    ${CYAN}Minimal-Interaction 3-Step Workflow${NC} (default behavior):

    ${CYAN}Step 1: Auto-Detect & Validate${NC} ${GREEN}(NO user input)${NC}
       - Auto-loads inventory.yaml configuration
       - Displays IP addresses, SSH users, ports for both VPS
       - Runs 8 validation checks (IP format, ports, SSH, OS, disk, RAM, CPU, sudo)
       - Shows validation summary table with PASS/FAIL/WARN status
       - Auto-proceeds if all checks pass (stops only on critical errors)

    ${CYAN}Step 2: Show Deployment Plan${NC} ${GREEN}(NO user input)${NC}
       - Displays what will be deployed where
       - Shows estimated deployment time (15-25 minutes)
       - Shows post-deployment access URLs
       - Auto-proceeds to final confirmation

    ${CYAN}Step 3: Single Go/No-Go Decision${NC} ${YELLOW}(1 user confirmation)${NC}
       - Shows summary: "2 VPS servers validated ✓"
       - Lists both VPS servers and their components
       - Shows access URLs after deployment
       - Asks: ${YELLOW}"Deploy CHOM Infrastructure? [Y/n]"${NC}
       - Launches auto-pilot deployment on YES

    ${CYAN}Auto-Pilot Deployment${NC} ${GREEN}(NO more prompts - sit back!)${NC}:

    ${CYAN}1. Observability Stack${NC} (5-10 minutes)
       - Installs Prometheus, Grafana, Loki, Alertmanager
       - Configures monitoring and dashboards
       - Sets up log aggregation

    ${CYAN}2. VPSManager Stack${NC} (10-15 minutes)
       - Installs LEMP stack (Nginx, PHP, MariaDB, Redis)
       - Deploys Laravel application
       - Installs monitoring exporters
       - Connects to Observability stack

${BOLD}TROUBLESHOOTING${NC}

    ${YELLOW}Deployment failed?${NC}
        ./deploy-enhanced.sh --resume         ${BLUE}# Resume from where it stopped${NC}

    ${YELLOW}Want to see what went wrong?${NC}
        ./deploy-enhanced.sh --debug --resume ${BLUE}# Resume with verbose logs${NC}

    ${YELLOW}SSH connection issues?${NC}
        ./deploy-enhanced.sh --validate       ${BLUE}# Test connectivity${NC}

    ${YELLOW}Need to start fresh?${NC}
        rm -rf .deploy-state/                 ${BLUE}# Clear deployment state${NC}
        ./deploy-enhanced.sh all              ${BLUE}# Start new deployment${NC}

${BOLD}REQUIREMENTS${NC}

    Before running this script, you need:

    ${CYAN}On Control Machine (where you run this script):${NC}
        - Linux or macOS
        - Bash 4.0+
        - SSH client (auto-checks)

    ${CYAN}On VPS Servers (2 servers):${NC}
        - Debian 13 (fresh install)
        - 20GB+ disk space
        - 2GB+ RAM (recommended)
        - Internet connectivity
        - SSH access with sudo user

    ${CYAN}Configuration File:${NC}
        - Edit ${YELLOW}configs/inventory.yaml${NC} with your VPS IP addresses
        - See DEPLOYMENT-GUIDE.md for detailed setup instructions

${BOLD}FIRST-TIME SETUP CHECKLIST${NC}

    Before your first deployment:

    ${BLUE}1.${NC} Create sudo user on both VPS servers (NOT root!)
        ${YELLOW}See: SUDO-USER-SETUP.md${NC}

    ${BLUE}2.${NC} Edit configs/inventory.yaml with your VPS IPs and usernames
        ${YELLOW}cp configs/inventory.yaml.example configs/inventory.yaml${NC}

    ${BLUE}3.${NC} Run validation to check everything is ready:
        ${YELLOW}./deploy-enhanced.sh --validate${NC}

    ${BLUE}4.${NC} Preview the deployment plan:
        ${YELLOW}./deploy-enhanced.sh --plan${NC}

    ${BLUE}5.${NC} Deploy:
        ${YELLOW}./deploy-enhanced.sh all${NC}

${BOLD}MORE INFORMATION${NC}

    ${YELLOW}Full deployment guide:${NC}     DEPLOYMENT-GUIDE.md
    ${YELLOW}SSH user setup guide:${NC}      SUDO-USER-SETUP.md
    ${YELLOW}Quick reference:${NC}           README-ENHANCED.md
    ${YELLOW}Version:${NC}                   ${SCRIPT_VERSION}

EOF
    exit 0
}

#===============================================================================
# State Management
#===============================================================================

init_state() {
    # Create state directory with restricted permissions
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    if [[ ! -f "$STATE_FILE" ]]; then
        # Create state file
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
        # Secure the state file (only owner can read/write)
        chmod 600 "$STATE_FILE"
        log_debug "State file initialized with secure permissions"
    fi
}

update_state() {
    local target
    target=$1
    local status
    status=$2
    local timestamp
    timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    # Use PID for unique temp file name to prevent conflicts
    local tmp_file
    tmp_file="${STATE_FILE}.tmp.$$"

    # Ensure temp file is cleaned up on function exit
    trap "rm -f '$tmp_file'" RETURN

    # Validate target
    case "$target" in
        global|observability|vpsmanager)
            ;;
        *)
            log_error "Invalid state target: $target"
            return 1
            ;;
    esac

    # Update state with error handling
    if [[ "$target" == "global" ]]; then
        if ! jq ".status = \"$status\" | .updated_at = \"$timestamp\"" "$STATE_FILE" > "$tmp_file" 2>/dev/null; then
            log_error "Failed to update global state"
            return 1
        fi
    else
        if ! jq ".${target}.status = \"$status\" | .${target}.updated_at = \"$timestamp\"" "$STATE_FILE" > "$tmp_file" 2>/dev/null; then
            log_error "Failed to update state for $target"
            return 1
        fi

        # Add completion timestamp if completed
        if [[ "$status" == "completed" ]]; then
            local tmp_file2
            tmp_file2="${tmp_file}.2"
            if ! jq ".${target}.completed_at = \"$timestamp\"" "$tmp_file" > "$tmp_file2" 2>/dev/null; then
                log_error "Failed to set completion timestamp"
                rm -f "$tmp_file2"
                return 1
            fi
            mv "$tmp_file2" "$tmp_file"
        fi
    fi

    # Atomic rename (as atomic as possible on most filesystems)
    if ! mv "$tmp_file" "$STATE_FILE"; then
        log_error "Failed to save state file"
        return 1
    fi

    log_debug "State updated: $target = $status"

    # Add to temp files for cleanup
    TEMP_FILES+=("$tmp_file")
}

get_state() {
    local target
    target=$1
    jq -r ".${target}.status" "$STATE_FILE" 2>/dev/null || echo "pending"
}

show_state() {
    if [[ -f "$STATE_FILE" ]]; then
        echo ""
        echo "${BOLD}Current Deployment State:${NC}"
        echo ""

        local obs_status
        obs_status=$(get_state "observability")
        local vps_status
        vps_status=$(get_state "vpsmanager")

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

    local missing
    missing=()
    local deps
    deps=("ssh" "scp" "yq" "jq")

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
                local still_missing
                still_missing=()
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
    local required_fields
    required_fields=(
        ".observability.ip"
        ".observability.ssh_user"
        ".observability.ssh_port"
        ".vpsmanager.ip"
        ".vpsmanager.ssh_user"
        ".vpsmanager.ssh_port"
    )

    for field in "${required_fields[@]}"; do
        local value
        value=$(yq eval "$field" "$CONFIG_FILE")
        if [[ -z "$value" || "$value" == "null" ]]; then
            log_error "Missing required field: $field"
            exit 1
        fi
    done

    # Validate IP addresses
    local obs_ip
    obs_ip=$(yq eval '.observability.ip' "$CONFIG_FILE")
    local vps_ip
    vps_ip=$(yq eval '.vpsmanager.ip' "$CONFIG_FILE")

    if [[ "$obs_ip" == "0.0.0.0" ]]; then
        log_error "Observability IP is set to 0.0.0.0 (placeholder)"
        log_error "Update inventory.yaml with actual IP address"
        exit 1
    fi

    if [[ "$vps_ip" == "0.0.0.0" ]]; then
        log_error "VPSManager IP is set to 0.0.0.0 (placeholder)"
        log_error "Update inventory.yaml with actual IP address"
        exit 1
    fi

    # Validate IP format (IPv4)
    if ! [[ "$obs_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address format for observability: $obs_ip"
        log_error "Expected format: xxx.xxx.xxx.xxx"
        exit 1
    fi

    if ! [[ "$vps_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address format for vpsmanager: $vps_ip"
        log_error "Expected format: xxx.xxx.xxx.xxx"
        exit 1
    fi

    # Validate IP octets are in range 0-255
    IFS='.' read -r -a obs_octets <<< "$obs_ip"
    for octet in "${obs_octets[@]}"; do
        if [[ $octet -gt 255 || $octet -lt 0 ]]; then
            log_error "Invalid IP octet in observability IP: $octet (must be 0-255)"
            exit 1
        fi
    done

    IFS='.' read -r -a vps_octets <<< "$vps_ip"
    for octet in "${vps_octets[@]}"; do
        if [[ $octet -gt 255 || $octet -lt 0 ]]; then
            log_error "Invalid IP octet in vpsmanager IP: $octet (must be 0-255)"
            exit 1
        fi
    done

    # Validate SSH ports
    local obs_port
    obs_port=$(yq eval '.observability.ssh_port' "$CONFIG_FILE")
    local vps_port
    vps_port=$(yq eval '.vpsmanager.ssh_port' "$CONFIG_FILE")

    if ! [[ "$obs_port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port format for observability: $obs_port (must be numeric)"
        exit 1
    fi

    if ! [[ "$vps_port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port format for vpsmanager: $vps_port (must be numeric)"
        exit 1
    fi

    if [[ $obs_port -lt 1 || $obs_port -gt 65535 ]]; then
        log_error "Invalid SSH port for observability: $obs_port (must be 1-65535)"
        exit 1
    fi

    if [[ $vps_port -lt 1 || $vps_port -gt 65535 ]]; then
        log_error "Invalid SSH port for vpsmanager: $vps_port (must be 1-65535)"
        exit 1
    fi

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

    local key_path
    key_path="${KEYS_DIR}/chom_deploy_key"

    if [[ ! -f "$key_path" ]]; then
        log_info "Generating deployment SSH key..."
        mkdir -p "$KEYS_DIR"
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "chom-deploy"
        chmod 600 "$key_path"
        log_success "SSH key generated at $key_path"

        echo ""
        log_success "SSH key generated at: ${key_path}"
        echo ""
        echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        log_warn "ACTION REQUIRED: Copy SSH key to your VPS servers"
        echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "${BOLD}PREREQUISITE:${NC} Your VPS user MUST have a password set"
        echo ""
        echo "  ${RED}Haven't created a sudo user yet?${NC}"
        echo "  ${YELLOW}→ See SUDO-USER-SETUP.md for step-by-step instructions${NC}"
        echo "  ${YELLOW}→ Quick command: ssh root@YOUR_VPS_IP then run user setup script${NC}"
        echo ""
        echo "${BOLD}What happens when you run ssh-copy-id:${NC}"
        echo ""
        echo "  ${CYAN}Step 1:${NC} First connection - verify host fingerprint"
        echo "          ${BLUE}Prompt:${NC} 'Are you sure you want to continue connecting (yes/no)?'"
        echo "          ${GREEN}Action:${NC} Type ${YELLOW}yes${NC} and press Enter"
        echo ""
        echo "  ${CYAN}Step 2:${NC} Authentication - enter password"
        echo "          ${BLUE}Prompt:${NC} 'password:'"
        echo "          ${GREEN}Action:${NC} Enter the password you set for the user"
        echo "          ${YELLOW}Note:${NC} You won't see characters as you type (normal security)"
        echo ""
        echo "  ${CYAN}Step 3:${NC} Key copied successfully"
        echo "          ${GREEN}Success:${NC} You'll see 'Number of key(s) added: 1'"
        echo ""

        # Get VPS details from inventory
        local obs_ip
        obs_ip=$(get_config '.observability.ip' 2>/dev/null || echo "")
        local obs_user
        obs_user=$(get_config '.observability.ssh_user' 2>/dev/null || echo "")
        local obs_port
        obs_port=$(get_config '.observability.ssh_port' 2>/dev/null || echo "22")

        local vps_ip
        vps_ip=$(get_config '.vpsmanager.ip' 2>/dev/null || echo "")
        local vps_user
        vps_user=$(get_config '.vpsmanager.ssh_user' 2>/dev/null || echo "")
        local vps_port
        vps_port=$(get_config '.vpsmanager.ssh_port' 2>/dev/null || echo "22")

        echo "${BOLD}Copy-paste these commands:${NC}"
        echo ""

        if [[ -n "$obs_ip" && "$obs_ip" != "0.0.0.0" && "$obs_ip" != "null" ]]; then
            echo "  ${YELLOW}# Observability VPS${NC}"
            echo "  ${CYAN}ssh-copy-id -i ${key_path}.pub -p ${obs_port} ${obs_user}@${obs_ip}${NC}"
            echo ""
        fi

        if [[ -n "$vps_ip" && "$vps_ip" != "0.0.0.0" && "$vps_ip" != "null" ]]; then
            echo "  ${YELLOW}# VPSManager VPS${NC}"
            echo "  ${CYAN}ssh-copy-id -i ${key_path}.pub -p ${vps_port} ${vps_user}@${vps_ip}${NC}"
            echo ""
        fi

        echo "${BOLD}Alternative:${NC} Manually copy the key:"
        echo "  ${CYAN}cat ${key_path}.pub${NC}"
        echo "  Then add it to ~/.ssh/authorized_keys on each VPS"
        echo ""
        echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""

        if [[ "$DRY_RUN" != "true" && "$INTERACTIVE_MODE" != "true" ]]; then
            # Non-interactive mode: offer to run ssh-copy-id automatically
            echo ""
            log_info "Attempting to copy SSH keys automatically..."
            log_warn "You will be prompted for passwords..."
            echo ""

            local copied_any
            copied_any=false
            local copy_failed
            copy_failed=false

            if [[ -n "$obs_ip" && "$obs_ip" != "0.0.0.0" && "$obs_ip" != "null" ]]; then
                log_info "Copying key to Observability VPS (${obs_user}@${obs_ip})..."
                echo "${YELLOW}You may be asked to:${NC}"
                echo "  ${YELLOW}1) Accept fingerprint: type 'yes'${NC}"
                echo "  ${YELLOW}2) Enter password for ${obs_user}${NC}"
                echo ""
                if ssh-copy-id -i "${key_path}.pub" -p "${obs_port}" "${obs_user}@${obs_ip}"; then
                    log_success "Key copied to Observability VPS"
                    copied_any=true
                else
                    log_error "Failed to copy key to Observability VPS"
                    copy_failed=true
                fi
                echo ""
            fi

            if [[ -n "$vps_ip" && "$vps_ip" != "0.0.0.0" && "$vps_ip" != "null" ]]; then
                log_info "Copying key to VPSManager VPS (${vps_user}@${vps_ip})..."
                echo "${YELLOW}You may be asked to:${NC}"
                echo "  ${YELLOW}1) Accept fingerprint: type 'yes'${NC}"
                echo "  ${YELLOW}2) Enter password for ${vps_user}${NC}"
                echo ""
                if ssh-copy-id -i "${key_path}.pub" -p "${vps_port}" "${vps_user}@${vps_ip}"; then
                    log_success "Key copied to VPSManager VPS"
                    copied_any=true
                else
                    log_error "Failed to copy key to VPSManager VPS"
                    copy_failed=true
                fi
                echo ""
            fi

            if [[ "$copy_failed" == "true" ]]; then
                log_error "SSH key copy failed for one or more servers"
                echo ""
                echo "Common issues:"
                echo "  1. User doesn't have a password set"
                echo "  2. Wrong username in inventory.yaml"
                echo "  3. VPS not accessible"
                echo "  4. SSH port blocked by firewall"
                echo ""
                echo "Fix the issue and manually run:"
                if [[ -n "$obs_ip" && "$obs_ip" != "0.0.0.0" && "$obs_ip" != "null" ]]; then
                    echo "  ssh-copy-id -i ${key_path}.pub -p ${obs_port} ${obs_user}@${obs_ip}"
                fi
                if [[ -n "$vps_ip" && "$vps_ip" != "0.0.0.0" && "$vps_ip" != "null" ]]; then
                    echo "  ssh-copy-id -i ${key_path}.pub -p ${vps_port} ${vps_user}@${vps_ip}"
                fi
                echo ""
                exit 1
            fi

            if [[ "$copied_any" != "true" ]]; then
                log_warn "No VPS IPs configured in inventory.yaml"
                log_info "SSH validation will verify if keys are installed correctly"
                echo ""
            fi
        elif [[ "$INTERACTIVE_MODE" == "true" ]]; then
            # Legacy interactive mode - prompt for confirmation
            read -p "Press Enter once you've added the key to all VPS servers..."
        else
            # Minimal interaction mode - auto-proceed, validation will catch issues
            log_info "SSH keys ready. Validation will verify connectivity."
            echo ""
        fi
    else
        log_success "SSH key found at $key_path"
    fi
}

test_ssh_connection() {
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3
    local name
    name=$4
    local key_path
    key_path="${KEYS_DIR}/chom_deploy_key"

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
        echo ""
        log_error "Cannot connect to $name via SSH"
        echo ""
        echo "${YELLOW}Connection Details:${NC}"
        echo "  Host: ${CYAN}$host${NC}"
        echo "  Port: ${CYAN}$port${NC}"
        echo "  User: ${CYAN}$user${NC}"
        echo ""
        echo "${BOLD}What to check (in order):${NC}"
        echo ""
        echo "  ${CYAN}1.${NC} Is the VPS running and reachable?"
        echo "     ${YELLOW}→${NC} Test: ${BLUE}ping $host${NC}"
        echo "     ${YELLOW}→${NC} If ping fails, check VPS provider console"
        echo ""
        echo "  ${CYAN}2.${NC} Is the SSH port correct and accessible?"
        echo "     ${YELLOW}→${NC} Test: ${BLUE}nc -zv $host $port${NC}"
        echo "     ${YELLOW}→${NC} If connection refused, check firewall or VPS SSH config"
        echo ""
        echo "  ${CYAN}3.${NC} Is the SSH key properly installed on the VPS?"
        echo "     ${YELLOW}→${NC} Copy key: ${BLUE}ssh-copy-id -i ${key_path}.pub -p ${port} ${user}@${host}${NC}"
        echo "     ${YELLOW}→${NC} Or check: ${BLUE}ssh -i ${key_path} -p ${port} ${user}@${host} 'cat ~/.ssh/authorized_keys'${NC}"
        echo ""
        echo "  ${CYAN}4.${NC} Test manual SSH connection:"
        echo "     ${BLUE}ssh -v -i ${key_path} -p ${port} ${user}@${host}${NC}"
        echo "     ${YELLOW}→${NC} The -v flag shows verbose output for debugging"
        echo ""
        echo "${BOLD}Common fixes:${NC}"
        echo "  - Wrong IP in inventory.yaml: Update ${YELLOW}configs/inventory.yaml${NC}"
        echo "  - Wrong user: Verify username matches the sudo user you created"
        echo "  - VPS firewall: Allow SSH port (usually port 22)"
        echo ""
        return 1
    fi
}

remote_exec() {
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3
    local cmd
    cmd=$4
    local key_path
    key_path="${KEYS_DIR}/chom_deploy_key"

    # Validate inputs to prevent command injection
    if [[ ! "$host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid host format: $host"
        return 1
    fi

    if [[ ! "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid user format: $user"
        return 1
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port format: $port"
        return 1
    fi

    # Execute command with proper quoting to prevent injection
    # Use printf %q for shell-safe escaping
    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        -- "$cmd"
}

remote_copy() {
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3
    local src
    src=$4
    local dest
    dest=$5
    local key_path
    key_path="${KEYS_DIR}/chom_deploy_key"

    # Validate inputs to prevent path injection
    if [[ ! "$host" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        log_error "Invalid host format: $host"
        return 1
    fi

    if [[ ! "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid user format: $user"
        return 1
    fi

    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port format: $port"
        return 1
    fi

    # Validate source file exists
    if [[ ! -f "$src" && ! -d "$src" ]]; then
        log_error "Source path does not exist: $src"
        return 1
    fi

    # Validate destination path format (basic path validation)
    if [[ "$dest" =~ [[:cntrl:]] ]]; then
        log_error "Invalid destination path format: $dest"
        return 1
    fi

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
    local attempt
    attempt=$1
    local base_delay
    base_delay=2

    if [[ "$RETRY_BACKOFF" == "exponential" ]]; then
        # Exponential: 2, 4, 8, 16, 32 seconds (capped at 32)
        local delay
        delay=$((base_delay ** attempt))
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
    local operation_name
    operation_name=$1
    local command_to_retry
    command_to_retry=$2
    local auto_fix_function
    auto_fix_function=${3:-""}

    local attempt
    attempt=1
    local max_attempts
    max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $operation_name"

        # Execute the command
        if eval "$command_to_retry"; then
            if [[ $attempt -gt 1 ]]; then
                log_success "$operation_name succeeded after $attempt attempts"
            fi
            return 0
        fi

        local exit_code
        exit_code=$?

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
        local delay
        delay=$(calculate_backoff $attempt)

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

    local installed_any
    installed_any=false

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
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3

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
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3
    local service
    service=$4

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
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3

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
    local file_path
    file_path=$1

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
    local host
    host=$1
    local user
    user=$2
    local port
    port=$3
    local name
    name=$4

    log_step "Validating $name VPS..."

    # Check OS
    log_info "Checking OS version..."
    local os_check
    os_check=$(remote_exec "$host" "$user" "$port" "cat /etc/os-release | grep -E '^(ID|VERSION_ID)=' || true")

    if echo "$os_check" | grep -q 'ID=debian'; then
        if echo "$os_check" | grep -q 'VERSION_ID="13"'; then
            log_success "OS: Debian 13 (correct)"
        else
            local version
            version=$(echo "$os_check" | grep VERSION_ID | cut -d'"' -f2)
            log_warn "OS: Debian $version (expected 13, may have compatibility issues)"
        fi
    else
        log_error "OS is not Debian"
        return 1
    fi

    # Check disk space
    log_info "Checking disk space..."
    local disk_gb
    disk_gb=$(remote_exec "$host" "$user" "$port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'")

    if [[ $disk_gb -lt 20 ]]; then
        log_error "Insufficient disk space: ${disk_gb}GB (minimum 20GB required)"
        return 1
    else
        log_success "Disk space: ${disk_gb}GB available"
    fi

    # Check RAM
    log_info "Checking RAM..."
    local ram_mb
    ram_mb=$(remote_exec "$host" "$user" "$port" "free -m | awk '/^Mem:/ {print \$2}'")

    if [[ $ram_mb -lt 1024 ]]; then
        log_warn "Low RAM: ${ram_mb}MB (recommended: 2048MB+)"
    else
        log_success "RAM: ${ram_mb}MB"
    fi

    # Check CPU
    log_info "Checking CPU count..."
    local cpu_count
    cpu_count=$(remote_exec "$host" "$user" "$port" "nproc")

    if [[ $cpu_count -lt 1 ]]; then
        log_error "Insufficient CPU: ${cpu_count} vCPUs (minimum 1 required)"
        return 1
    else
        log_success "CPU: ${cpu_count} vCPU(s)"
    fi

    # Check passwordless sudo
    log_info "Validating passwordless sudo..."
    if remote_exec "$host" "$user" "$port" "sudo -n true" &>/dev/null; then
        log_success "Passwordless sudo configured correctly"
    else
        log_error "User $user does not have passwordless sudo access"
        echo ""
        echo "Fix this by running on the VPS as root:"
        echo "  echo \"$user ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/$user"
        echo "  sudo chmod 0440 /etc/sudoers.d/$user"
        echo ""
        echo "Or see: SUDO-USER-SETUP.md for detailed instructions"
        return 1
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
    local existing
    existing=$(remote_exec "$host" "$user" "$port" "systemctl list-units --type=service --all | grep -E '(prometheus|grafana|nginx)' | wc -l" || echo "0")

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
    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local obs_user
    obs_user=$(get_config '.observability.ssh_user')
    local obs_port
    obs_port=$(get_config '.observability.ssh_port')

    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')
    local vps_user
    vps_user=$(get_config '.vpsmanager.ssh_user')
    local vps_port
    vps_port=$(get_config '.vpsmanager.ssh_port')

    # Test SSH connections
    local ssh_failures
    ssh_failures=0

    if ! test_ssh_connection "$obs_ip" "$obs_user" "$obs_port" "Observability"; then
        ((ssh_failures++))
    fi

    if ! test_ssh_connection "$vps_ip" "$vps_user" "$vps_port" "VPSManager"; then
        ((ssh_failures++))
    fi

    if [[ $ssh_failures -gt 0 ]]; then
        echo ""
        log_error "SSH connection failed to $ssh_failures VPS server(s)"
        echo ""
        echo "${BOLD}Next steps to fix this:${NC}"
        echo ""
        echo "  ${CYAN}1.${NC} Make sure you've copied the SSH key to each VPS"
        echo "     ${YELLOW}→${NC} Run the ssh-copy-id commands shown above"
        echo ""
        echo "  ${CYAN}2.${NC} Verify the IP addresses and usernames in inventory.yaml"
        echo "     ${YELLOW}→${NC} Edit: ${BLUE}configs/inventory.yaml${NC}"
        echo ""
        echo "  ${CYAN}3.${NC} Check VPS firewall allows SSH connections"
        echo ""
        echo "  ${CYAN}4.${NC} Review troubleshooting steps in the error messages above"
        echo ""
        echo "Once fixed, run: ${GREEN}./deploy-enhanced.sh --validate${NC}"
        echo ""
        exit 1
    fi

    # Validate remote VPS
    local validation_failures
    validation_failures=0

    if ! validate_remote_vps "$obs_ip" "$obs_user" "$obs_port" "Observability"; then
        ((validation_failures++))
    fi

    echo ""

    if ! validate_remote_vps "$vps_ip" "$vps_user" "$vps_port" "VPSManager"; then
        ((validation_failures++))
    fi

    if [[ $validation_failures -gt 0 ]]; then
        echo ""
        log_error "VPS validation failed for $validation_failures server(s)"
        echo ""
        echo "${BOLD}Review the validation errors above and fix them${NC}"
        echo ""
        echo "${YELLOW}Common issues:${NC}"
        echo "  - Wrong OS version: Requires Debian 13 (fresh install recommended)"
        echo "  - Low disk space: Need 20GB+ free (40GB+ recommended)"
        echo "  - Sudo not configured: User needs passwordless sudo access"
        echo "  - No internet: VPS must be able to reach github.com"
        echo ""
        echo "${BOLD}After fixing, validate again:${NC}"
        echo "  ${GREEN}./deploy-enhanced.sh --validate${NC}"
        echo ""
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

    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local obs_hostname
    obs_hostname=$(get_config '.observability.hostname')
    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')
    local vps_hostname
    vps_hostname=$(get_config '.vpsmanager.hostname')

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
# 3-Step Interactive Deployment Workflow
#===============================================================================

# Step 1: Show inventory review and get confirmation
show_inventory_review() {
    print_section "STEP 1 of 3: Inventory Review & Confirmation"

    echo "${BOLD}Current Inventory Configuration:${NC}"
    echo ""

    # Read inventory file
    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local obs_hostname
    obs_hostname=$(get_config '.observability.hostname')
    local obs_user
    obs_user=$(get_config '.observability.ssh_user')
    local obs_port
    obs_port=$(get_config '.observability.ssh_port')
    local obs_cpu
    obs_cpu=$(get_config '.observability.specs.cpu')
    local obs_ram
    obs_ram=$(get_config '.observability.specs.memory_mb')
    local obs_disk
    obs_disk=$(get_config '.observability.specs.disk_gb')

    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')
    local vps_hostname
    vps_hostname=$(get_config '.vpsmanager.hostname')
    local vps_user
    vps_user=$(get_config '.vpsmanager.ssh_user')
    local vps_port
    vps_port=$(get_config '.vpsmanager.ssh_port')
    local vps_cpu
    vps_cpu=$(get_config '.vpsmanager.specs.cpu')
    local vps_ram
    vps_ram=$(get_config '.vpsmanager.specs.memory_mb')
    local vps_disk
    vps_disk=$(get_config '.vpsmanager.specs.disk_gb')

    # Observability VPS
    echo "${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo "${CYAN}│${NC} ${BOLD}Observability VPS${NC} (Monitoring Stack)                              ${CYAN}│${NC}"
    echo "${CYAN}├─────────────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "IP Address:" "$obs_ip"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "Hostname:" "$obs_hostname"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "SSH User:" "$obs_user"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "SSH Port:" "$obs_port"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "Specs:" "${obs_cpu} vCPU, ${obs_ram}MB RAM, ${obs_disk}GB Disk"
    echo "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # VPSManager VPS
    echo "${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo "${CYAN}│${NC} ${BOLD}VPSManager VPS${NC} (Application Stack)                                ${CYAN}│${NC}"
    echo "${CYAN}├─────────────────────────────────────────────────────────────────────────┤${NC}"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "IP Address:" "$vps_ip"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "Hostname:" "$vps_hostname"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "SSH User:" "$vps_user"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "SSH Port:" "$vps_port"
    printf "${CYAN}│${NC} %-20s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "Specs:" "${vps_cpu} vCPU, ${vps_ram}MB RAM, ${vps_disk}GB Disk"
    echo "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Check for placeholder IPs
    local needs_edit
    needs_edit=false
    if [[ "$obs_ip" == "0.0.0.0" || "$obs_ip" == "null" ]]; then
        log_warn "Observability IP is not configured (placeholder detected)"
        needs_edit=true
    fi

    if [[ "$vps_ip" == "0.0.0.0" || "$vps_ip" == "null" ]]; then
        log_warn "VPSManager IP is not configured (placeholder detected)"
        needs_edit=true
    fi

    if [[ "$needs_edit" == "true" ]]; then
        echo ""
        log_error "Configuration incomplete - placeholder values detected"
        echo ""
        echo "${BOLD}How to fix:${NC}"
        echo "  1. Edit: ${YELLOW}${CONFIG_FILE}${NC}"
        echo "  2. Replace 0.0.0.0 with your actual VPS IP addresses"
        echo "  3. Update hostnames and other settings as needed"
        echo "  4. Run this script again"
        echo ""
        echo "${BLUE}Example:${NC}"
        echo "  nano ${CONFIG_FILE}"
        echo ""
        return 1
    fi

    # Minimal interaction mode - auto-proceed (validation in Step 2 will catch issues)
    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        # Legacy interactive mode - ask for confirmation
        echo ""
        echo "${BOLD}${YELLOW}Is this configuration correct?${NC}"
        echo ""

        if [[ "$AUTO_APPROVE" == "true" ]]; then
            log_info "Auto-approve enabled - skipping confirmation"
            return 0
        fi

        read -p "Continue with this configuration? [Y/n] " -r
        echo ""

        if [[ $REPLY =~ ^[Nn]$ ]]; then
            log_info "Configuration review rejected by user"
            echo ""
            echo "${BOLD}To update your configuration:${NC}"
            echo "  1. Edit: ${YELLOW}${CONFIG_FILE}${NC}"
            echo "  2. Update IP addresses, hostnames, SSH settings"
            echo "  3. Run: ${GREEN}./deploy-enhanced.sh${NC}"
            echo ""
            return 1
        fi

        log_success "Configuration confirmed by user"
    else
        # Minimal interaction: show config, auto-proceed
        echo ""
        log_info "Configuration loaded - proceeding to validation"
    fi
    return 0
}

# Step 2: Validate inventory and show deployment plan
show_validation_summary() {
    print_section "STEP 2 of 3: Validate Inventory & Show Deployment Plan"

    echo "${BOLD}Running validation checks...${NC}"
    echo ""

    # Get VPS details
    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local obs_user
    obs_user=$(get_config '.observability.ssh_user')
    local obs_port
    obs_port=$(get_config '.observability.ssh_port')

    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')
    local vps_user
    vps_user=$(get_config '.vpsmanager.ssh_user')
    local vps_port
    vps_port=$(get_config '.vpsmanager.ssh_port')

    # Track validation results
    local validation_errors
    validation_errors=0
    declare -A validation_results

    # 1. IP Format Validation
    echo "${CYAN}[1/8]${NC} Validating IP addresses..."
    if [[ "$obs_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && \
       [[ "$vps_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        echo "      ${GREEN}✓${NC} IP format validation passed"
        validation_results[ip_format]="pass"
    else
        echo "      ${RED}✗${NC} IP format validation failed"
        validation_results[ip_format]="fail"
        ((validation_errors++))
    fi

    # 2. Port Range Validation
    echo "${CYAN}[2/8]${NC} Validating SSH ports..."
    if [[ $obs_port -ge 1 && $obs_port -le 65535 ]] && \
       [[ $vps_port -ge 1 && $vps_port -le 65535 ]]; then
        echo "      ${GREEN}✓${NC} SSH ports are valid"
        validation_results[ports]="pass"
    else
        echo "      ${RED}✗${NC} Invalid SSH port range"
        validation_results[ports]="fail"
        ((validation_errors++))
    fi

    # 3. SSH Connectivity
    echo "${CYAN}[3/8]${NC} Testing SSH connectivity..."
    local ssh_ok
    ssh_ok=true

    if test_ssh_connection "$obs_ip" "$obs_user" "$obs_port" "Observability" 2>/dev/null; then
        echo "      ${GREEN}✓${NC} Observability VPS: SSH connected"
    else
        echo "      ${RED}✗${NC} Observability VPS: SSH failed"
        ssh_ok=false
        ((validation_errors++))
    fi

    if test_ssh_connection "$vps_ip" "$vps_user" "$vps_port" "VPSManager" 2>/dev/null; then
        echo "      ${GREEN}✓${NC} VPSManager VPS: SSH connected"
    else
        echo "      ${RED}✗${NC} VPSManager VPS: SSH failed"
        ssh_ok=false
        ((validation_errors++))
    fi

    if [[ "$ssh_ok" == "true" ]]; then
        validation_results[ssh]="pass"
    else
        validation_results[ssh]="fail"
    fi

    # Only continue remote checks if SSH works
    if [[ "$ssh_ok" == "true" ]]; then
        # 4. OS Version Check
        echo "${CYAN}[4/8]${NC} Checking OS version..."
        local obs_os
        obs_os=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "cat /etc/os-release | grep -E '^(ID|VERSION_ID)=' | grep -c 'ID=debian'" 2>/dev/null || echo "0")
        local vps_os
        vps_os=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "cat /etc/os-release | grep -E '^(ID|VERSION_ID)=' | grep -c 'ID=debian'" 2>/dev/null || echo "0")

        if [[ "$obs_os" -gt 0 && "$vps_os" -gt 0 ]]; then
            echo "      ${GREEN}✓${NC} Both servers running Debian"
            validation_results[os]="pass"
        else
            echo "      ${YELLOW}⚠${NC} OS check inconclusive or non-Debian detected"
            validation_results[os]="warn"
        fi

        # 5. Disk Space Check
        echo "${CYAN}[5/8]${NC} Checking disk space..."
        local obs_disk
        obs_disk=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'" 2>/dev/null || echo "0")
        local vps_disk
        vps_disk=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "df -BG / | awk 'NR==2 {print \$4}' | tr -d 'G'" 2>/dev/null || echo "0")

        if [[ $obs_disk -ge 20 && $vps_disk -ge 20 ]]; then
            echo "      ${GREEN}✓${NC} Sufficient disk space (Obs: ${obs_disk}GB, VPS: ${vps_disk}GB)"
            validation_results[disk]="pass"
        else
            echo "      ${RED}✗${NC} Insufficient disk space (need 20GB+)"
            validation_results[disk]="fail"
            ((validation_errors++))
        fi

        # 6. RAM Check
        echo "${CYAN}[6/8]${NC} Checking RAM..."
        local obs_ram
        obs_ram=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")
        local vps_ram
        vps_ram=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "free -m | awk '/^Mem:/ {print \$2}'" 2>/dev/null || echo "0")

        if [[ $obs_ram -ge 1024 && $vps_ram -ge 1024 ]]; then
            echo "      ${GREEN}✓${NC} Sufficient RAM (Obs: ${obs_ram}MB, VPS: ${vps_ram}MB)"
            validation_results[ram]="pass"
        else
            echo "      ${YELLOW}⚠${NC} Low RAM detected (recommended: 2048MB+)"
            validation_results[ram]="warn"
        fi

        # 7. CPU Check
        echo "${CYAN}[7/8]${NC} Checking CPU..."
        local obs_cpu
        obs_cpu=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "nproc" 2>/dev/null || echo "0")
        local vps_cpu
        vps_cpu=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "nproc" 2>/dev/null || echo "0")

        if [[ $obs_cpu -ge 1 && $vps_cpu -ge 1 ]]; then
            echo "      ${GREEN}✓${NC} CPU available (Obs: ${obs_cpu} vCPU, VPS: ${vps_cpu} vCPU)"
            validation_results[cpu]="pass"
        else
            echo "      ${RED}✗${NC} CPU check failed"
            validation_results[cpu]="fail"
            ((validation_errors++))
        fi

        # 8. Passwordless Sudo Check
        echo "${CYAN}[8/8]${NC} Checking passwordless sudo..."
        local obs_sudo
        obs_sudo=$(remote_exec "$obs_ip" "$obs_user" "$obs_port" "sudo -n true" &>/dev/null && echo "1" || echo "0")
        local vps_sudo
        vps_sudo=$(remote_exec "$vps_ip" "$vps_user" "$vps_port" "sudo -n true" &>/dev/null && echo "1" || echo "0")

        if [[ "$obs_sudo" == "1" && "$vps_sudo" == "1" ]]; then
            echo "      ${GREEN}✓${NC} Passwordless sudo configured"
            validation_results[sudo]="pass"
        else
            echo "      ${RED}✗${NC} Passwordless sudo not configured"
            validation_results[sudo]="fail"
            ((validation_errors++))
        fi
    else
        echo "${CYAN}[4/8]${NC} ${YELLOW}⚠${NC} Skipping OS check (SSH failed)"
        echo "${CYAN}[5/8]${NC} ${YELLOW}⚠${NC} Skipping disk space check (SSH failed)"
        echo "${CYAN}[6/8]${NC} ${YELLOW}⚠${NC} Skipping RAM check (SSH failed)"
        echo "${CYAN}[7/8]${NC} ${YELLOW}⚠${NC} Skipping CPU check (SSH failed)"
        echo "${CYAN}[8/8]${NC} ${YELLOW}⚠${NC} Skipping sudo check (SSH failed)"
    fi

    echo ""

    # Show validation summary table
    echo "${BOLD}Validation Summary:${NC}"
    echo ""
    echo "┌────────────────────────────┬──────────┐"
    echo "│ Check                      │ Status   │"
    echo "├────────────────────────────┼──────────┤"

    for check in ip_format ports ssh os disk ram cpu sudo; do
        local status
        status="${validation_results[$check]:-skip}"
        local status_icon
        status_icon=""

        case "$status" in
            pass)
                status_icon="${GREEN}✓ PASS${NC}"
                ;;
            fail)
                status_icon="${RED}✗ FAIL${NC}"
                ;;
            warn)
                status_icon="${YELLOW}⚠ WARN${NC}"
                ;;
            *)
                status_icon="${BLUE}- SKIP${NC}"
                ;;
        esac

        local check_name
        check_name=""
        case "$check" in
            ip_format) check_name="IP Address Format" ;;
            ports) check_name="SSH Port Range" ;;
            ssh) check_name="SSH Connectivity" ;;
            os) check_name="Operating System" ;;
            disk) check_name="Disk Space (20GB+)" ;;
            ram) check_name="RAM (2GB+)" ;;
            cpu) check_name="CPU Cores" ;;
            sudo) check_name="Passwordless Sudo" ;;
        esac

        printf "│ %-26s │ %-8s │\n" "$check_name" "$status_icon"
    done

    echo "└────────────────────────────┴──────────┘"
    echo ""

    # Show what will be deployed
    echo "${BOLD}Deployment Components:${NC}"
    echo ""

    echo "${CYAN}Observability VPS${NC} (${obs_ip}):"
    echo "  • Prometheus (Metrics)"
    echo "  • Loki (Logs)"
    echo "  • Grafana (Dashboards)"
    echo "  • Alertmanager (Alerts)"
    echo "  • Nginx (Reverse Proxy)"
    echo ""

    echo "${CYAN}VPSManager VPS${NC} (${vps_ip}):"
    echo "  • Nginx (Web Server)"
    echo "  • PHP-FPM 8.2/8.4"
    echo "  • MariaDB 11.4 (Database)"
    echo "  • Redis (Cache)"
    echo "  • Laravel Application"
    echo "  • Monitoring Exporters"
    echo ""

    # Calculate estimated time
    local obs_time
    obs_time="5-10"
    local vps_time
    vps_time="10-15"
    local total_min
    total_min="15"
    local total_max
    total_max="25"

    echo "${BOLD}Estimated Deployment Time:${NC}"
    echo "  Observability Stack: ${obs_time} minutes"
    echo "  VPSManager:          ${vps_time} minutes"
    echo "  ${BOLD}Total:              ${total_min}-${total_max} minutes${NC}"
    echo ""

    # Return status
    if [[ $validation_errors -gt 0 ]]; then
        log_error "$validation_errors validation check(s) failed"
        echo ""
        echo "${BOLD}Fix the issues above before proceeding${NC}"
        echo ""
        return 1
    fi

    log_success "All validation checks passed"
    return 0
}

# Step 3: Final deployment confirmation
confirm_deployment() {
    print_section "STEP 3 of 3: Final Deployment Confirmation"

    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local obs_hostname
    obs_hostname=$(get_config '.observability.hostname')
    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')
    local vps_hostname
    vps_hostname=$(get_config '.vpsmanager.hostname')

    echo "${BOLD}${YELLOW}Ready to deploy CHOM Infrastructure${NC}"
    echo ""

    echo "${BOLD}What will happen:${NC}"
    echo ""

    echo "  ${CYAN}1. Observability Stack${NC} → ${obs_ip} (${obs_hostname})"
    echo "     • Install Prometheus, Loki, Grafana, Alertmanager"
    echo "     • Configure monitoring and dashboards"
    echo "     • Setup log aggregation"
    echo ""

    echo "  ${CYAN}2. VPSManager Stack${NC} → ${vps_ip} (${vps_hostname})"
    echo "     • Install LEMP stack (Nginx, PHP, MariaDB, Redis)"
    echo "     • Deploy Laravel application"
    echo "     • Install monitoring exporters"
    echo "     • Connect to Observability stack"
    echo ""

    echo "${BOLD}Estimated Time:${NC} 15-25 minutes"
    echo ""

    echo "${BOLD}After Deployment, Access:${NC}"
    echo "  • Grafana:     http://${obs_ip}:3000"
    echo "  • Prometheus:  http://${obs_ip}:9090"
    echo "  • VPSManager:  http://${vps_ip}:8080"
    echo ""

    echo "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [[ "$AUTO_APPROVE" == "true" ]]; then
        log_info "Auto-approve enabled - proceeding with deployment"
        return 0
    fi

    echo "${BOLD}${YELLOW}Proceed with deployment?${NC}"
    echo ""
    read -p "Deploy now? [Y/n] " -r
    echo ""

    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Deployment cancelled by user"
        echo ""
        echo "${BOLD}No changes were made to your servers${NC}"
        echo ""
        echo "You can resume the deployment later by running:"
        echo "  ${GREEN}./deploy-enhanced.sh${NC}"
        echo ""
        return 1
    fi

    log_success "Deployment confirmed - starting now..."
    return 0
}

#===============================================================================
# Deployment Functions
#===============================================================================

deploy_observability() {
    local is_plan
    is_plan=$1

    if [[ "$is_plan" == "true" ]]; then
        return 0
    fi

    log_step "Deploying Observability Stack..."
    update_state "observability" "in_progress"

    local ip
    ip=$(get_config '.observability.ip')
    local user
    user=$(get_config '.observability.ssh_user')
    local port
    port=$(get_config '.observability.ssh_port')
    # local hostname  # Reserved for future use
    # hostname=$(get_config '.observability.hostname')

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
    local is_plan
    is_plan=$1

    if [[ "$is_plan" == "true" ]]; then
        return 0
    fi

    log_step "Deploying VPSManager..."
    update_state "vpsmanager" "in_progress"

    local ip
    ip=$(get_config '.vpsmanager.ip')
    local user
    user=$(get_config '.vpsmanager.ssh_user')
    local port
    port=$(get_config '.vpsmanager.ssh_port')
    # local hostname  # Reserved for future use
    # hostname=$(get_config '.vpsmanager.hostname')
    local obs_ip
    obs_ip=$(get_config '.observability.ip')

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
        log_info "Validating environment and VPS servers..."
        echo ""

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
    log_info "Proceeding to VPSManager deployment..."
    echo ""

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

    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')

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

            --auto-approve|-y)
                AUTO_APPROVE=true
                INTERACTIVE_MODE=false
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
                # VERBOSE=true  # Reserved for future use
                shift
                ;;

            --debug)
                DEBUG=true
                # VERBOSE=true  # Reserved for future use
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
    local target
    target=$1

    print_section "Deploying ${target^}"

    # Check if already deployed
    if [[ "$RESUME" == "true" && $(get_state "$target") == "completed" ]]; then
        log_info "$target already deployed (skipping)"
        return 0
    fi

    # Get VPS details
    local ip
    ip=$(get_config ".${target}.ip")
    local user
    user=$(get_config ".${target}.ssh_user")
    local port
    port=$(get_config ".${target}.ssh_port")

    # Deploy with retry and auto-healing
    retry_with_healing \
        "Deploy $target" \
        "deploy_${target} false" \
        "autofix_service_conflict $ip $user $port $target"
}

error_exit() {
    local error_message
    error_message=$1
    local exit_code
    exit_code=${2:-1}

    log_error "$error_message"

    # Save state
    update_state "global" "failed"

    echo ""
    echo "${YELLOW}Deployment state saved. Resume with: $0 --resume${NC}"
    echo ""

    exit $exit_code
}

show_deployment_summary() {
    local obs_ip
    obs_ip=$(get_config '.observability.ip')
    local vps_ip
    vps_ip=$(get_config '.vpsmanager.ip')

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
    # Check Bash version before anything else
    check_bash_version

    # Acquire deployment lock to prevent parallel runs
    acquire_lock

    # Enable cleanup on exit
    CLEANUP_NEEDED=true

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

    # Pre-flight checks for dependencies and SSH keys
    if [[ "$FORCE_DEPLOY" != "true" ]]; then
        log_step "Checking local dependencies and SSH keys..."

        retry_with_healing \
            "Dependency check" \
            "check_dependencies && validate_inventory && ensure_ssh_key" \
            "autofix_missing_dependencies" \
            || error_exit "Initial setup failed"
    else
        log_warn "Skipping initial checks (--force enabled)"
    fi

    # ========================================================================
    # 3-STEP INTERACTIVE WORKFLOW (default behavior)
    # ========================================================================

    if [[ "$INTERACTIVE_MODE" == "true" ]]; then
        # STEP 1: Inventory Review & Confirmation
        if ! show_inventory_review; then
            exit 1
        fi

        echo ""

        # STEP 2: Validate Inventory & Show Deployment Plan
        if ! show_validation_summary; then
            exit 1
        fi

        echo ""

        # STEP 3: Final Deployment Confirmation
        if ! confirm_deployment; then
            exit 0
        fi

        echo ""
    else
        # Non-interactive mode (--auto-approve or -y flag used)
        log_info "Auto-approve mode: Running validation checks..."

        if [[ "$FORCE_DEPLOY" != "true" ]]; then
            retry_with_healing \
                "Pre-flight checks" \
                "run_preflight_checks" \
                "autofix_missing_dependencies" \
                || error_exit "Pre-flight checks failed"
        fi

        if [[ "$QUIET" != "true" ]]; then
            echo ""
            show_deployment_plan
            echo ""
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
