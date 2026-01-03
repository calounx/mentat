#!/usr/bin/env python3
"""
Batch add dependency validation to remaining deployment scripts
"""

import os
import sys
from pathlib import Path

# Validation header template for subscripts
VALIDATION_HEADER_SINGLE_SOURCE = '''
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
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"
'''

VALIDATION_HEADER_DUAL_SOURCE = '''
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
            "${utils_dir}/notifications.sh"
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
        echo "Run from repository root: sudo ./deploy/scripts/${script_name}" >&2
        exit 1
    fi
}

validate_deployment_dependencies "$SCRIPT_DIR" "$DEPLOY_ROOT"
'''

def main():
    # Get the scripts directory
    script_path = Path(__file__).resolve()
    deploy_root = script_path.parent.parent
    scripts_dir = deploy_root / "scripts"

    # Scripts to update (critical ones)
    target_scripts = {
        "health-check.sh": "single",
        "preflight-check.sh": "single",
        "rollback.sh": "dual",
        "backup-before-deploy.sh": "single",
    }

    updated_count = 0
    skipped_count = 0

    print(f"Updating remaining critical deployment scripts")
    print()

    for script_name, source_type in target_scripts.items():
        script_file = scripts_dir / script_name

        if not script_file.exists():
            print(f"SKIP: {script_name} (not found)")
            skipped_count += 1
            continue

        # Read the file
        try:
            content = script_file.read_text()
        except Exception as e:
            print(f"SKIP: {script_name} (cannot read: {e})")
            skipped_count += 1
            continue

        # Check if already has validation
        if "validate_deployment_dependencies" in content:
            print(f"SKIP: {script_name} (already has validation)")
            skipped_count += 1
            continue

        # Check if has set -euo pipefail
        if "set -euo pipefail" not in content:
            print(f"SKIP: {script_name} (missing 'set -euo pipefail')")
            skipped_count += 1
            continue

        # Find line after "set -euo pipefail"
        lines = content.split('\n')
        insert_line = None

        for i, line in enumerate(lines):
            if line.strip() == "set -euo pipefail":
                insert_line = i + 1
                break

        if insert_line is None:
            print(f"SKIP: {script_name} (cannot find insertion point)")
            skipped_count += 1
            continue

        # Choose the right header based on source type
        if source_type == "dual":
            header = VALIDATION_HEADER_DUAL_SOURCE
        else:
            header = VALIDATION_HEADER_SINGLE_SOURCE

        # Insert validation header
        new_lines = lines[:insert_line] + header.strip().split('\n') + lines[insert_line:]
        new_content = '\n'.join(new_lines)

        # Write back to file
        try:
            script_file.write_text(new_content)
            print(f"UPDATE: {script_name}")
            updated_count += 1
        except Exception as e:
            print(f"ERROR: {script_name} (cannot write: {e})")
            skipped_count += 1

    print()
    print(f"Summary:")
    print(f"  Updated: {updated_count} scripts")
    print(f"  Skipped: {skipped_count} scripts")
    print()

    if updated_count > 0:
        print("Critical deployment scripts have been updated with dependency validation!")
    else:
        print("No scripts needed updating.")

if __name__ == "__main__":
    main()
