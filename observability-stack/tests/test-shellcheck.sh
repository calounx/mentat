#!/bin/bash
#===============================================================================
# ShellCheck Integration Test
# Runs shellcheck on all shell scripts to ensure code quality
#===============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
ERRORS=0
WARNINGS=0
SKIPPED=0
CHECKED=0

# ShellCheck severity level (error, warning, info, style)
MIN_SEVERITY="${SHELLCHECK_SEVERITY:-warning}"

# Excluded checks (comma-separated SC codes)
EXCLUDE_CHECKS="${SHELLCHECK_EXCLUDE:-SC2034,SC2086}"

#===============================================================================
# FUNCTIONS
#===============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Check if shellcheck is installed
check_shellcheck() {
    if ! command -v shellcheck &> /dev/null; then
        log_error "shellcheck is not installed"
        echo ""
        echo "Install shellcheck:"
        echo "  Ubuntu/Debian: sudo apt-get install shellcheck"
        echo "  macOS: brew install shellcheck"
        echo "  Other: https://github.com/koalaman/shellcheck#installing"
        exit 1
    fi

    local version
    version=$(shellcheck --version | grep "^version:" | awk '{print $2}')
    log_info "Using shellcheck version: $version"
}

# Run shellcheck on a single file
check_script() {
    local script="$1"
    local relative_path="${script#$STACK_ROOT/}"

    # Skip non-shell files
    if [[ ! -f "$script" ]]; then
        return 0
    fi

    # Check if file is a shell script
    if ! head -n1 "$script" | grep -qE '^#!.*/(bash|sh)'; then
        return 0
    fi

    printf "Checking: %-60s " "$relative_path"

    # Run shellcheck
    local output
    local exit_code=0

    output=$(shellcheck \
        --severity="$MIN_SEVERITY" \
        --exclude="$EXCLUDE_CHECKS" \
        --format=gcc \
        "$script" 2>&1) || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}✓${NC}"
        ((CHECKED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((ERRORS++))
        ((CHECKED++))

        # Show detailed errors
        echo "$output" | while IFS= read -r line; do
            echo "  $line"
        done
        echo ""

        return 1
    fi
}

# Find and check all shell scripts
check_all_scripts() {
    log_info "Scanning for shell scripts in: $STACK_ROOT"
    echo ""

    local scripts=()

    # Find all .sh files
    while IFS= read -r script; do
        scripts+=("$script")
    done < <(find "$STACK_ROOT" -type f -name "*.sh" ! -path "*/\.*" ! -path "*/bats-core/*" 2>/dev/null)

    # Find scripts without .sh extension but with shebang
    while IFS= read -r script; do
        if head -n1 "$script" | grep -qE '^#!.*/(bash|sh)'; then
            scripts+=("$script")
        fi
    done < <(find "$STACK_ROOT/scripts" -type f ! -name "*.sh" ! -path "*/\.*" 2>/dev/null)

    if [[ ${#scripts[@]} -eq 0 ]]; then
        log_warn "No shell scripts found"
        return 0
    fi

    log_info "Found ${#scripts[@]} shell scripts to check"
    echo ""

    # Check each script
    for script in "${scripts[@]}"; do
        check_script "$script"
    done
}

# Generate summary report
show_summary() {
    echo ""
    echo "=========================================="
    echo "ShellCheck Summary"
    echo "=========================================="
    echo ""
    printf "Scripts checked:  %d\n" $CHECKED
    printf "Passed:           %s%d%s\n" "$GREEN" $((CHECKED - ERRORS)) "$NC"
    printf "Failed:           %s%d%s\n" "$RED" $ERRORS "$NC"

    if [[ $SKIPPED -gt 0 ]]; then
        printf "Skipped:          %s%d%s\n" "$YELLOW" $SKIPPED "$NC"
    fi

    echo ""

    if [[ $ERRORS -eq 0 ]]; then
        log_success "All scripts passed shellcheck!"
        echo ""
        return 0
    else
        log_error "$ERRORS script(s) failed shellcheck"
        echo ""
        echo "To fix issues, review the errors above and update the scripts."
        echo "You can also adjust shellcheck rules in this script if needed."
        echo ""
        return 1
    fi
}

# Run specific scripts only (for targeted checking)
check_specific_scripts() {
    local scripts=("$@")

    log_info "Checking ${#scripts[@]} specified script(s)"
    echo ""

    for script in "${scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            log_warn "File not found: $script"
            ((SKIPPED++))
            continue
        fi

        check_script "$script"
    done
}

# Show help
show_help() {
    cat <<EOF
ShellCheck Integration Test

Usage:
  $0 [OPTIONS] [FILES...]

Options:
  -h, --help              Show this help message
  -s, --severity LEVEL    Set minimum severity level (error, warning, info, style)
                          Default: warning
  -e, --exclude CODES     Comma-separated SC codes to exclude
                          Default: SC2034,SC2086
  -v, --verbose           Show verbose output

Examples:
  # Check all scripts
  $0

  # Check specific scripts
  $0 scripts/setup-observability.sh scripts/module-manager.sh

  # Check with different severity
  $0 --severity error

  # Exclude additional checks
  $0 --exclude SC2034,SC2086,SC2155

Environment Variables:
  SHELLCHECK_SEVERITY     Override default severity level
  SHELLCHECK_EXCLUDE      Override default excluded checks

Exit Codes:
  0 - All checks passed
  1 - One or more checks failed

For more information about shellcheck:
  https://github.com/koalaman/shellcheck
EOF
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    local specific_files=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -s|--severity)
                MIN_SEVERITY="$2"
                shift 2
                ;;
            -e|--exclude)
                EXCLUDE_CHECKS="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
            *)
                specific_files+=("$1")
                shift
                ;;
        esac
    done

    # Check for shellcheck
    check_shellcheck

    echo ""
    echo "=========================================="
    echo "ShellCheck Integration Test"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Minimum severity: $MIN_SEVERITY"
    echo "  Excluded checks:  $EXCLUDE_CHECKS"
    echo ""

    # Run checks
    if [[ ${#specific_files[@]} -gt 0 ]]; then
        check_specific_scripts "${specific_files[@]}"
    else
        check_all_scripts
    fi

    # Show summary and exit
    if show_summary; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"
