#!/bin/bash
#===============================================================================
# Observability Stack Installer
# Sets up CLI command and bash completion
#
# Usage:
#   sudo ./install.sh
#   sudo ./install.sh --uninstall
#===============================================================================

set -euo pipefail

# Colors
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
BLUE=$'\033[0;34m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_WRAPPER="$SCRIPT_DIR/observability"
SYMLINK_PATH="/usr/local/bin/obs"
COMPLETION_SOURCE="$SCRIPT_DIR/etc/bash_completion.d/observability"
COMPLETION_DEST="/etc/bash_completion.d/obs"

#===============================================================================
# FUNCTIONS
#===============================================================================

log_info() {
    echo "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1" >&2
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This installer must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

install_cli() {
    log_info "Installing observability CLI..."

    # Make CLI executable
    if [[ ! -f "$CLI_WRAPPER" ]]; then
        log_error "CLI wrapper not found: $CLI_WRAPPER"
        exit 1
    fi

    chmod +x "$CLI_WRAPPER"

    # Create symlink
    if [[ -L "$SYMLINK_PATH" ]]; then
        log_info "Removing existing symlink..."
        rm -f "$SYMLINK_PATH"
    elif [[ -f "$SYMLINK_PATH" ]]; then
        log_warn "File exists at $SYMLINK_PATH (not a symlink)"
        read -p "Overwrite? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Installation aborted"
            exit 1
        fi
        rm -f "$SYMLINK_PATH"
    fi

    ln -s "$CLI_WRAPPER" "$SYMLINK_PATH"
    log_success "Created symlink: $SYMLINK_PATH -> $CLI_WRAPPER"

    # Verify command is available
    if command -v obs &>/dev/null; then
        log_success "Command 'obs' is now available"
    else
        log_warn "Command 'obs' not in PATH. You may need to log out and back in."
    fi
}

install_completion() {
    log_info "Installing bash completion..."

    if [[ ! -f "$COMPLETION_SOURCE" ]]; then
        log_warn "Bash completion script not found: $COMPLETION_SOURCE"
        return
    fi

    # Create bash completion directory if it doesn't exist
    mkdir -p /etc/bash_completion.d

    # Copy completion file
    cp "$COMPLETION_SOURCE" "$COMPLETION_DEST"
    chmod 644 "$COMPLETION_DEST"

    log_success "Installed bash completion: $COMPLETION_DEST"
    log_info "Reload your shell or run: source $COMPLETION_DEST"
}

uninstall() {
    log_info "Uninstalling observability CLI..."

    # Remove symlink
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH"
        log_success "Removed symlink: $SYMLINK_PATH"
    else
        log_info "Symlink not found: $SYMLINK_PATH"
    fi

    # Remove completion
    if [[ -f "$COMPLETION_DEST" ]]; then
        rm -f "$COMPLETION_DEST"
        log_success "Removed bash completion: $COMPLETION_DEST"
    else
        log_info "Bash completion not found: $COMPLETION_DEST"
    fi

    log_success "Uninstallation complete"
}

show_post_install() {
    echo ""
    echo "=========================================="
    echo "${GREEN}Installation Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "The 'obs' command is now available."
    echo ""
    echo "Quick start:"
    echo "  obs help                    # Show all commands"
    echo "  obs preflight --observability-vps"
    echo "  obs config validate"
    echo "  obs setup --observability"
    echo ""
    echo "Documentation:"
    echo "  Quick start: $SCRIPT_DIR/QUICK_START.md"
    echo "  Full docs:   $SCRIPT_DIR/README.md"
    echo ""
    echo "To enable bash completion in current shell:"
    echo "  source $COMPLETION_DEST"
    echo ""
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    local mode="install"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall)
                mode="uninstall"
                shift
                ;;
            --help|-h)
                cat << 'EOF'
Observability Stack Installer

Usage:
  sudo ./install.sh                 Install the CLI
  sudo ./install.sh --uninstall     Uninstall the CLI
  ./install.sh --help               Show this help

This script will:
  - Make the observability CLI executable
  - Create symlink: /usr/local/bin/obs -> observability
  - Install bash completion to /etc/bash_completion.d/obs

After installation, you can use 'obs' instead of './observability'
EOF
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run './install.sh --help' for usage"
                exit 1
                ;;
        esac
    done

    echo ""
    echo "=========================================="
    echo "Observability Stack Installer"
    echo "=========================================="
    echo ""

    check_root

    if [[ "$mode" == "uninstall" ]]; then
        uninstall
    else
        install_cli
        install_completion
        show_post_install
    fi
}

main "$@"
