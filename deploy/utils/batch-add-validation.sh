#!/usr/bin/env bash
# Batch add dependency validation to security scripts
# This script adds validation headers to all security scripts that don't have them yet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECURITY_DIR="${DEPLOY_ROOT}/security"

# Security validation header template for scripts that source utilities
get_security_validation_header() {
    cat <<'EOF'

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
EOF
}

# List of security scripts to update (excluding master-security-setup.sh which is already done)
SECURITY_SCRIPTS=(
    "compliance-check.sh"
    "configure-access-control.sh"
    "configure-firewall.sh"
    "create-deployment-user.sh"
    "encrypt-backups.sh"
    "generate-secure-secrets.sh"
    "generate-ssh-keys-secure.sh"
    "harden-application.sh"
    "harden-database.sh"
    "incident-response.sh"
    "manage-secrets.sh"
    "rotate-secrets.sh"
    "security-audit.sh"
    "setup-fail2ban.sh"
    "setup-intrusion-detection.sh"
    "setup-security-monitoring.sh"
    "setup-ssh-keys.sh"
    "setup-ssl.sh"
    "vulnerability-scan.sh"
)

echo "Batch updating security scripts with dependency validation..."
echo ""

updated_count=0
skipped_count=0

for script in "${SECURITY_SCRIPTS[@]}"; do
    script_path="${SECURITY_DIR}/${script}"

    if [[ ! -f "$script_path" ]]; then
        echo "SKIP: $script (not found)"
        ((skipped_count++))
        continue
    fi

    # Check if script already has validation
    if grep -q "validate_deployment_dependencies" "$script_path"; then
        echo "SKIP: $script (already has validation)"
        ((skipped_count++))
        continue
    fi

    # Check if script has set -euo pipefail
    if ! grep -q "set -euo pipefail" "$script_path"; then
        echo "SKIP: $script (missing set -euo pipefail)"
        ((skipped_count++))
        continue
    fi

    echo "UPDATE: $script"

    # Create backup
    cp "$script_path" "${script_path}.bak"

    # Find line number after "set -euo pipefail"
    line_num=$(grep -n "set -euo pipefail" "$script_path" | head -1 | cut -d: -f1)

    if [[ -z "$line_num" ]]; then
        echo "  ERROR: Could not find 'set -euo pipefail' line"
        rm "${script_path}.bak"
        ((skipped_count++))
        continue
    fi

    # Split file at the insertion point
    head -n "$line_num" "$script_path" > "${script_path}.tmp"
    get_security_validation_header >> "${script_path}.tmp"
    tail -n +$((line_num + 1)) "$script_path" >> "${script_path}.tmp"

    # Replace original file
    mv "${script_path}.tmp" "$script_path"
    rm "${script_path}.bak"

    ((updated_count++))
done

echo ""
echo "Summary:"
echo "  Updated: $updated_count scripts"
echo "  Skipped: $skipped_count scripts"
echo ""

if [[ $updated_count -gt 0 ]]; then
    echo "All security scripts have been updated with dependency validation!"
else
    echo "No scripts needed updating."
fi
