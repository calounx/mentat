#!/bin/bash
#===============================================================================
# Module Loader Patch - Version Management Integration
# This script shows the changes needed for scripts/lib/module-loader.sh
#
# Usage: Review this file to understand the changes, then manually apply
#        or use as reference for integration.
#===============================================================================

cat << 'EOF'
================================================================================
PATCH FOR: scripts/lib/module-loader.sh
================================================================================

SECTION 1: Add version management initialization (after line 21)
--------------------------------------------------------------------------------

# After this line:
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Add:

#===============================================================================
# VERSION MANAGEMENT INTEGRATION
#===============================================================================

# Source version management library if available
VERSION_MANAGEMENT_AVAILABLE=false
if [[ -f "$LIB_DIR/versions.sh" ]]; then
    if source "$LIB_DIR/versions.sh" 2>/dev/null; then
        VERSION_MANAGEMENT_AVAILABLE=true
        # Optional: Log that version management is loaded
        # echo "[DEBUG] Version management system loaded" >&2
    else
        # Optional: Log warning if loading fails
        # echo "[WARN] Failed to load version management system, using fallback" >&2
        :
    fi
fi

================================================================================

SECTION 2: Update module_version function (around line 151)
--------------------------------------------------------------------------------

# Replace the existing module_version function with this enhanced version:

# Get module version
# Usage: module_version "module_name"
# Returns: version string resolved via version management or manifest fallback
module_version() {
    local module_name="$1"

    # Priority 1: Environment variable override (VERSION_OVERRIDE_<component>)
    local env_var="VERSION_OVERRIDE_${module_name^^}"
    env_var="${env_var//-/_}"  # Replace hyphens with underscores
    if [[ -n "${!env_var:-}" ]]; then
        echo "${!env_var}"
        return 0
    fi

    # Priority 2: MODULE_VERSION environment variable (backward compatibility)
    if [[ -n "${MODULE_VERSION:-}" ]]; then
        echo "$MODULE_VERSION"
        return 0
    fi

    # Priority 3: Version management system
    if [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]]; then
        local resolved_version
        if resolved_version=$(resolve_version "$module_name" 2>/dev/null); then
            echo "$resolved_version"
            return 0
        fi
    fi

    # Priority 4: Module manifest (fallback)
    module_get_nested "$module_name" "module" "version"
}

================================================================================

SECTION 3: Add optional version info command (add after module_info function)
--------------------------------------------------------------------------------

# Show version information for a module
# Usage: show_module_version_info "module_name"
show_module_version_info() {
    local module_name="$1"

    if [[ "$VERSION_MANAGEMENT_AVAILABLE" != "true" ]]; then
        echo "Version management system not available"
        echo "Module version: $(module_version "$module_name")"
        return 1
    fi

    print_version_info "$module_name"
}

================================================================================

SECTION 4: Optional - Add version listing to list_modules function
--------------------------------------------------------------------------------

# In the list_modules function (around line 629), you can optionally show
# version source information by adding an extra column:

# Change this line (around line 629):
printf "%-25s %-10s %-6s %-12s %s\n" "MODULE" "VERSION" "PORT" "CATEGORY" "DESCRIPTION"

# To this:
printf "%-25s %-10s %-8s %-6s %-12s %s\n" "MODULE" "VERSION" "SOURCE" "PORT" "CATEGORY" "DESCRIPTION"

# And in the loop (around line 634), add version source detection:
while IFS= read -r module; do
    local version port category description version_source

    version=$(module_version "$module")
    port=$(module_port "$module")
    category=$(module_category "$module")
    description=$(module_description "$module")

    # Determine version source
    local env_var="VERSION_OVERRIDE_${module^^}"
    env_var="${env_var//-/_}"
    if [[ -n "${!env_var:-}" ]]; then
        version_source="env"
    elif [[ -n "${MODULE_VERSION:-}" ]]; then
        version_source="env"
    elif [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]] && get_latest_version "$module" &>/dev/null; then
        version_source="github"
    elif [[ "$VERSION_MANAGEMENT_AVAILABLE" == "true" ]] && get_config_version "$module" &>/dev/null; then
        version_source="config"
    else
        version_source="manifest"
    fi

    # Truncate description to fit
    description="${description:0:40}"

    printf "%-25s %-10s %-8s %-6s %-12s %s\n" \
        "$module" "$version" "$version_source" "$port" "$category" "$description"
done < <(list_available_modules)

================================================================================

COMPLETE BACKWARD-COMPATIBLE INTEGRATION
================================================================================

The changes above maintain 100% backward compatibility:

1. If versions.sh is not present, the system works exactly as before
2. If versions.sh fails to load, fallback to old behavior
3. Environment variables take highest priority (existing behavior)
4. MODULE_VERSION still works (existing behavior)
5. Module manifest is the ultimate fallback (existing behavior)

TESTING THE CHANGES
================================================================================

After applying the patch, test with:

# 1. Test that existing behavior still works
MODULE_VERSION=1.7.0 ./scripts/setup-monitored-host.sh --dry-run

# 2. Test version management
./scripts/version-manager info node_exporter

# 3. Test environment override
export VERSION_OVERRIDE_NODE_EXPORTER=1.8.0
# Verify it uses 1.8.0

# 4. Test fallback (remove GitHub access)
export VERSION_OFFLINE_MODE=true
# Should still work

# 5. List modules with version source
./scripts/module-manager list

================================================================================
END OF PATCH
================================================================================

MANUAL APPLICATION INSTRUCTIONS:

1. Backup current module-loader.sh:
   cp scripts/lib/module-loader.sh scripts/lib/module-loader.sh.backup

2. Open module-loader.sh in your editor:
   vim scripts/lib/module-loader.sh

3. Apply Section 1 changes (add version management init)
4. Apply Section 2 changes (update module_version function)
5. Optionally apply Section 3 (add version info command)
6. Optionally apply Section 4 (enhance list display)

7. Test the changes:
   ./tests/test-version-management.sh

8. If any issues, restore backup:
   cp scripts/lib/module-loader.sh.backup scripts/lib/module-loader.sh

AUTOMATED APPLICATION:

For automated patching, you can use this script as a reference to create
a sed/awk script, but manual review is recommended to ensure correctness.

EOF
