#!/usr/bin/env bash
# Terminal color utilities for deployment scripts
# Usage: source "$(dirname "$0")/../utils/colors.sh"

# Color codes
export COLOR_RESET='\033[0m'
export COLOR_RED='\033[0;31m'
export COLOR_GREEN='\033[0;32m'
export COLOR_YELLOW='\033[0;33m'
export COLOR_BLUE='\033[0;34m'
export COLOR_PURPLE='\033[0;35m'
export COLOR_CYAN='\033[0;36m'
export COLOR_WHITE='\033[0;37m'

# Bold colors
export COLOR_BOLD_RED='\033[1;31m'
export COLOR_BOLD_GREEN='\033[1;32m'
export COLOR_BOLD_YELLOW='\033[1;33m'
export COLOR_BOLD_BLUE='\033[1;34m'
export COLOR_BOLD_PURPLE='\033[1;35m'
export COLOR_BOLD_CYAN='\033[1;36m'
export COLOR_BOLD_WHITE='\033[1;37m'

# Background colors
export COLOR_BG_RED='\033[0;41m'
export COLOR_BG_GREEN='\033[0;42m'
export COLOR_BG_YELLOW='\033[0;43m'
export COLOR_BG_BLUE='\033[0;44m'

# Print colored text (to stderr so it doesn't interfere with captured output)
print_color() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${COLOR_RESET}" >&2
}

# Print success message
print_success() {
    print_color "$COLOR_GREEN" "✓ $1"
}

# Print error message
print_error() {
    print_color "$COLOR_RED" "✗ $1"
}

# Print warning message
print_warning() {
    print_color "$COLOR_YELLOW" "⚠ $1"
}

# Print info message
print_info() {
    print_color "$COLOR_BLUE" "ℹ $1"
}

# Print header
print_header() {
    echo "" >&2
    print_color "$COLOR_BOLD_CYAN" "═══════════════════════════════════════════════════════════════"
    print_color "$COLOR_BOLD_CYAN" "  $1"
    print_color "$COLOR_BOLD_CYAN" "═══════════════════════════════════════════════════════════════"
    echo "" >&2
}

# Print section
print_section() {
    echo "" >&2
    print_color "$COLOR_BOLD_BLUE" "▶ $1"
    echo "" >&2
}

# Print step
print_step() {
    print_color "$COLOR_CYAN" "  → $1"
}

# Print progress
print_progress() {
    print_color "$COLOR_PURPLE" "  ⋯ $1"
}

# Export functions
export -f print_color
export -f print_success
export -f print_error
export -f print_warning
export -f print_info
export -f print_header
export -f print_section
export -f print_step
export -f print_progress
