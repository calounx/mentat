#!/usr/bin/env bash
# Dependency validation utilities for deployment scripts
# Ensures all required files and executables exist before script execution
# Usage: source "${SCRIPT_DIR}/utils/dependency-validation.sh"

# ANSI color codes for error output (before sourcing colors.sh)
readonly _RED='\033[0;31m'
readonly _YELLOW='\033[1;33m'
readonly _CYAN='\033[0;36m'
readonly _NC='\033[0m'

# Print error message in red
_print_error() {
    echo -e "${_RED}ERROR: $*${_NC}" >&2
}

# Print warning message in yellow
_print_warning() {
    echo -e "${_YELLOW}WARNING: $*${_NC}" >&2
}

# Print info message in cyan
_print_info() {
    echo -e "${_CYAN}INFO: $*${_NC}" >&2
}

# Validate that a file exists and is readable
# Args: $1 = file path, $2 = description (optional)
validate_file_exists() {
    local file_path="$1"
    local description="${2:-file}"

    if [[ ! -f "$file_path" ]]; then
        _print_error "Required $description not found: $file_path"
        return 1
    fi

    if [[ ! -r "$file_path" ]]; then
        _print_error "Required $description is not readable: $file_path"
        return 1
    fi

    return 0
}

# Validate that a directory exists
# Args: $1 = directory path, $2 = description (optional)
validate_directory_exists() {
    local dir_path="$1"
    local description="${2:-directory}"

    if [[ ! -d "$dir_path" ]]; then
        _print_error "Required $description not found: $dir_path"
        return 1
    fi

    return 0
}

# Validate that an executable exists and is in PATH
# Args: $1 = executable name, $2 = package hint (optional)
validate_executable_exists() {
    local executable="$1"
    local package_hint="${2:-}"

    if ! command -v "$executable" &> /dev/null; then
        _print_error "Required executable not found: $executable"
        if [[ -n "$package_hint" ]]; then
            _print_info "Install with: sudo apt-get install $package_hint"
        fi
        return 1
    fi

    return 0
}

# Validate script is being run from expected location
# Args: $1 = expected directory pattern (e.g., "*/mentat/deploy")
validate_script_location() {
    local expected_pattern="$1"
    local current_dir="$(pwd)"

    if [[ ! "$current_dir" =~ $expected_pattern ]]; then
        _print_warning "Script may not be running from expected location"
        _print_info "Current directory: $current_dir"
        _print_info "Expected pattern: $expected_pattern"
    fi
}

# Comprehensive dependency validation for deployment scripts
# This should be called at the top of every deployment script
# Args: $1 = script directory, $2 = script type (main|subscript|security)
validate_deployment_dependencies() {
    local script_dir="$1"
    local script_type="${2:-subscript}"
    local script_name="$(basename "${BASH_SOURCE[1]}")"
    local errors=()

    # Determine deploy root based on script type
    local deploy_root
    case "$script_type" in
        main)
            # Script is in deploy/ directory
            deploy_root="$script_dir"
            ;;
        subscript)
            # Script is in deploy/scripts/ directory
            deploy_root="$(cd "${script_dir}/.." && pwd)"
            ;;
        security)
            # Script is in deploy/security/ directory
            deploy_root="$(cd "${script_dir}/.." && pwd)"
            ;;
        *)
            _print_error "Unknown script type: $script_type"
            return 1
            ;;
    esac

    # Validate deploy root structure
    if [[ ! -d "$deploy_root" ]]; then
        errors+=("Deploy root directory not found: $deploy_root")
    fi

    # Validate utils directory
    local utils_dir="${deploy_root}/utils"
    if [[ ! -d "$utils_dir" ]]; then
        errors+=("Utils directory not found: $utils_dir")
    else
        # Validate required utility files
        local required_utils=(
            "${utils_dir}/logging.sh"
            "${utils_dir}/colors.sh"
            "${utils_dir}/notifications.sh"
            "${utils_dir}/idempotence.sh"
        )

        for util_file in "${required_utils[@]}"; do
            if [[ ! -f "$util_file" ]]; then
                errors+=("Required utility file not found: $util_file")
            elif [[ ! -r "$util_file" ]]; then
                errors+=("Required utility file not readable: $util_file")
            fi
        done
    fi

    # If errors found, print comprehensive error message and exit
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        _print_error "Missing required dependencies for ${script_name}"
        echo ""
        _print_info "Script location: ${script_dir}"
        _print_info "Script type: ${script_type}"
        _print_info "Deploy root: ${deploy_root}"
        _print_info "Utils directory: ${utils_dir}"
        echo ""
        _print_error "Missing dependencies:"
        for error in "${errors[@]}"; do
            echo "  - ${error}"
        done
        echo ""
        _print_info "Troubleshooting:"
        echo "  1. Verify you are in the correct repository:"
        echo "     cd /home/calounx/repositories/mentat"
        echo ""
        echo "  2. Run the script from the repository root:"
        echo "     sudo ./deploy/${script_name}"
        echo ""
        echo "  3. Check that all deployment files are present:"
        echo "     ls -la deploy/utils/"
        echo ""
        echo "  4. If files are missing, ensure git repository is complete:"
        echo "     git status"
        echo "     git pull"
        echo ""
        return 1
    fi

    return 0
}

# Validate common system executables needed for deployment
validate_system_executables() {
    local required_executables=(
        "bash:bash"
        "sudo:sudo"
        "systemctl:systemd"
        "awk:gawk"
        "sed:sed"
        "grep:grep"
        "curl:curl"
        "wget:wget"
    )

    local errors=()

    for spec in "${required_executables[@]}"; do
        local executable="${spec%%:*}"
        local package="${spec##*:}"

        if ! command -v "$executable" &> /dev/null; then
            errors+=("Missing executable: $executable (install: sudo apt-get install $package)")
        fi
    done

    if [[ ${#errors[@]} -gt 0 ]]; then
        _print_error "Missing required system executables:"
        for error in "${errors[@]}"; do
            echo "  - ${error}"
        done
        return 1
    fi

    return 0
}

# Validate configuration file exists and is readable
# Args: $1 = config file path, $2 = config type description
validate_config_file() {
    local config_file="$1"
    local config_type="${2:-configuration}"

    if [[ ! -f "$config_file" ]]; then
        _print_error "Required ${config_type} file not found: ${config_file}"
        _print_info "Create the file or ensure it exists before running this script"
        return 1
    fi

    if [[ ! -r "$config_file" ]]; then
        _print_error "Required ${config_type} file is not readable: ${config_file}"
        _print_info "Check file permissions: ls -la ${config_file}"
        return 1
    fi

    return 0
}

# Validate directory is writable
# Args: $1 = directory path, $2 = description
validate_directory_writable() {
    local dir_path="$1"
    local description="${2:-directory}"

    if [[ ! -d "$dir_path" ]]; then
        _print_error "Required ${description} does not exist: ${dir_path}"
        return 1
    fi

    if [[ ! -w "$dir_path" ]]; then
        _print_error "Required ${description} is not writable: ${dir_path}"
        _print_info "Fix with: sudo chmod u+w ${dir_path}"
        return 1
    fi

    return 0
}

# Validate script is run as root or with sudo
validate_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        _print_error "This script must be run as root or with sudo"
        _print_info "Run with: sudo $(basename "${BASH_SOURCE[1]}")"
        return 1
    fi
    return 0
}

# Validate script is NOT run as root (for safety)
validate_not_root() {
    if [[ $EUID -eq 0 ]]; then
        _print_error "This script should NOT be run as root"
        _print_info "Run as regular user: $(basename "${BASH_SOURCE[1]}")"
        return 1
    fi
    return 0
}

# Validate user exists on system
# Args: $1 = username
validate_user_exists() {
    local username="$1"

    if ! id "$username" &> /dev/null; then
        _print_error "Required user does not exist: $username"
        _print_info "Create user with: sudo useradd -m $username"
        return 1
    fi

    return 0
}

# Validate network connectivity to host
# Args: $1 = hostname or IP, $2 = port (optional)
validate_network_connectivity() {
    local host="$1"
    local port="${2:-22}"

    if ! timeout 5 bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null; then
        _print_error "Cannot connect to ${host}:${port}"
        _print_info "Check network connectivity and firewall rules"
        return 1
    fi

    return 0
}

# Validate environment variable is set and non-empty
# Args: $1 = variable name, $2 = description (optional)
validate_env_var() {
    local var_name="$1"
    local description="${2:-environment variable}"

    if [[ -z "${!var_name:-}" ]]; then
        _print_error "Required ${description} not set: ${var_name}"
        _print_info "Set with: export ${var_name}=<value>"
        return 1
    fi

    return 0
}

# Print validation success message
validation_success() {
    local script_name="$(basename "${BASH_SOURCE[1]}")"
    _print_info "Dependency validation passed for ${script_name}"
}

# Quick validation wrapper for simple scripts
# Validates: deployment dependencies, system executables
# Args: $1 = script directory, $2 = script type
quick_validate() {
    local script_dir="$1"
    local script_type="${2:-subscript}"

    validate_deployment_dependencies "$script_dir" "$script_type" || exit 1
    validate_system_executables || exit 1
    validation_success
}
