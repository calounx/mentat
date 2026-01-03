#!/usr/bin/env python3
"""
Batch add dependency validation to security scripts
"""

import os
import sys
from pathlib import Path

# Validation header template
VALIDATION_HEADER = '''
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
'''

def main():
    # Get the security directory
    script_path = Path(__file__).resolve()
    deploy_root = script_path.parent.parent
    security_dir = deploy_root / "security"

    if not security_dir.exists():
        print(f"ERROR: Security directory not found: {security_dir}")
        sys.exit(1)

    # Get all .sh files in security directory
    security_scripts = list(security_dir.glob("*.sh"))

    updated_count = 0
    skipped_count = 0

    print(f"Found {len(security_scripts)} security scripts")
    print()

    for script_file in sorted(security_scripts):
        script_name = script_file.name

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

        # Insert validation header
        new_lines = lines[:insert_line] + VALIDATION_HEADER.strip().split('\n') + lines[insert_line:]
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
        print("Security scripts have been updated with dependency validation!")
    else:
        print("No scripts needed updating.")

if __name__ == "__main__":
    main()
