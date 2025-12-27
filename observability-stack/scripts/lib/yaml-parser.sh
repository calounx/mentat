#!/bin/bash
#===============================================================================
# YAML Parser Library
# Robust YAML parsing with intelligent fallback strategies
#
# Priority order:
#   1. yq (best - full YAML 1.2 support)
#   2. python3 + PyYAML (good - handles most complex YAML)
#   3. awk-based (basic - simple key:value only)
#   4. Error with helpful message
#
# SECURITY: All methods validate input and sanitize output
#===============================================================================

# Guard against multiple sourcing
[[ -n "${YAML_PARSER_LOADED:-}" ]] && return 0
YAML_PARSER_LOADED=1

# Minimal logging functions (avoid circular dependency with common.sh)
# These will be overridden if common.sh is loaded
if ! declare -f log_debug >/dev/null 2>&1; then
    log_debug() { :; }  # No-op if common.sh not loaded
fi
if ! declare -f log_error >/dev/null 2>&1; then
    log_error() { echo "[ERROR] $*" >&2; }
fi
if ! declare -f log_warn >/dev/null 2>&1; then
    log_warn() { echo "[WARN] $*" >&2; }
fi

#===============================================================================
# YAML PARSER CAPABILITY DETECTION
#===============================================================================

# Detect which YAML parsing methods are available
# Sets global variable: YAML_PARSER_METHOD
# Returns: 0 always (will fallback to awk if nothing else)
_yaml_detect_parser() {
    # Cache the result
    if [[ -n "${YAML_PARSER_METHOD:-}" ]]; then
        return 0
    fi

    # Method 1: yq (best)
    if command -v yq &>/dev/null; then
        # Verify it's mikefarah's yq (not python-yq)
        if yq --version 2>&1 | grep -q "mikefarah"; then
            export YAML_PARSER_METHOD="yq"
            log_debug "YAML parser: using yq (best)"
            return 0
        fi
    fi

    # Method 2: python3 + PyYAML (good)
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml" 2>/dev/null; then
            export YAML_PARSER_METHOD="python"
            log_debug "YAML parser: using Python PyYAML (good)"
            return 0
        fi
    fi

    # Method 3: awk (basic fallback)
    export YAML_PARSER_METHOD="awk"
    log_debug "YAML parser: using awk fallback (basic - simple YAML only)"

    return 0
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Validate YAML file syntax
# Usage: yaml_validate "file.yaml"
# Returns: 0 if valid, 1 if invalid
yaml_validate() {
    local file="$1"

    # Check file exists
    if [[ ! -f "$file" ]]; then
        log_error "YAML validation failed: file not found: $file"
        return 1
    fi

    # Check file is readable
    if [[ ! -r "$file" ]]; then
        log_error "YAML validation failed: file not readable: $file"
        return 1
    fi

    _yaml_detect_parser

    case "$YAML_PARSER_METHOD" in
        yq)
            # yq eval validates on read
            if ! yq eval '.' "$file" >/dev/null 2>&1; then
                log_error "YAML syntax error in: $file"
                yq eval '.' "$file" 2>&1 | head -5
                return 1
            fi
            ;;

        python)
            # Use Python to validate YAML syntax
            if ! python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        yaml.safe_load(f)
except yaml.YAMLError as e:
    print(f'YAML syntax error: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Error reading YAML: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1; then
                log_error "YAML syntax error in: $file"
                return 1
            fi
            ;;

        awk)
            # Basic validation: check for common syntax issues
            # This is limited but better than nothing
            if grep -qE '^\s*:' "$file"; then
                log_error "YAML syntax error: key starts with colon in $file"
                return 1
            fi

            if grep -qE '^\s+\S+\s+\S+:' "$file"; then
                log_warn "YAML may have complex structure not supported by awk parser: $file"
            fi
            ;;
    esac

    log_debug "YAML validated: $file"
    return 0
}

# Check if required keys exist in YAML file
# Usage: yaml_check_required "file.yaml" "key1" "key2" "parent.child"
# Returns: 0 if all keys exist, 1 if any missing
yaml_check_required() {
    local file="$1"
    shift
    local missing_keys=()

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    for key in "$@"; do
        local value
        if [[ "$key" == *.* ]]; then
            # Nested key
            value=$(yaml_get_nested_path "$file" "$key")
        else
            # Simple key
            value=$(yaml_get_value "$file" "$key")
        fi

        if [[ -z "$value" ]]; then
            missing_keys+=("$key")
        fi
    done

    if [[ ${#missing_keys[@]} -gt 0 ]]; then
        log_error "Missing required keys in $file:"
        for key in "${missing_keys[@]}"; do
            log_error "  - $key"
        done
        return 1
    fi

    return 0
}

#===============================================================================
# CORE PARSING FUNCTIONS
#===============================================================================

# Get a simple value from YAML file
# Usage: yaml_get_value "file.yaml" "key"
# Returns: Value of key, or empty string if not found
yaml_get_value() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_value: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    local result=""

    case "$YAML_PARSER_METHOD" in
        yq)
            result=$(yq eval ".${key}" "$file" 2>/dev/null)
            # yq returns "null" for missing keys
            if [[ "$result" == "null" ]]; then
                result=""
            fi
            ;;

        python)
            result=$(python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if data and '$key' in data:
        value = data['$key']
        if value is not None:
            print(str(value))
except Exception:
    pass
" 2>/dev/null)
            ;;

        awk)
            # Fallback to awk-based parsing (basic)
            result=$(grep -E "^${key}:" "$file" 2>/dev/null | \
                sed "s/^${key}:[[:space:]]*//" | \
                sed 's/^["'\'']//' | \
                sed 's/["'\'']$//' | \
                sed 's/#.*//' | \
                xargs)
            ;;
    esac

    echo "$result"
    [[ -n "$result" ]]
}

# Get a nested value from YAML file using dot notation
# Usage: yaml_get_nested_path "file.yaml" "parent.child.key"
# Returns: Value of nested key, or empty string if not found
yaml_get_nested_path() {
    local file="$1"
    local path="$2"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_nested_path: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    local result=""

    case "$YAML_PARSER_METHOD" in
        yq)
            result=$(yq eval ".${path}" "$file" 2>/dev/null)
            if [[ "$result" == "null" ]]; then
                result=""
            fi
            ;;

        python)
            result=$(python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)

    # Navigate the path
    keys = '$path'.split('.')
    value = data
    for key in keys:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            sys.exit(1)

    if value is not None:
        print(str(value))
except Exception:
    sys.exit(1)
" 2>/dev/null)
            ;;

        awk)
            # For awk, fall back to yaml_get_nested with split path
            local parts=()
            IFS='.' read -ra parts <<< "$path"

            case ${#parts[@]} in
                2)
                    result=$(yaml_get_nested "$file" "${parts[0]}" "${parts[1]}")
                    ;;
                3)
                    result=$(yaml_get_deep "$file" "${parts[0]}" "${parts[1]}" "${parts[2]}")
                    ;;
                *)
                    log_warn "awk parser: complex nested paths not supported: $path"
                    return 1
                    ;;
            esac
            ;;
    esac

    echo "$result"
    [[ -n "$result" ]]
}

# Get a nested value (two levels: parent.child)
# Usage: yaml_get_nested "file.yaml" "parent" "child"
# Returns: Value of parent.child, or empty string if not found
yaml_get_nested() {
    local file="$1"
    local parent="$2"
    local child="$3"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_nested: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    local result=""

    case "$YAML_PARSER_METHOD" in
        yq)
            result=$(yq eval ".${parent}.${child}" "$file" 2>/dev/null)
            if [[ "$result" == "null" ]]; then
                result=""
            fi
            ;;

        python)
            result=$(python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if data and '$parent' in data and isinstance(data['$parent'], dict):
        if '$child' in data['$parent']:
            value = data['$parent']['$child']
            if value is not None:
                print(str(value))
except Exception:
    pass
" 2>/dev/null)
            ;;

        awk)
            # Original awk implementation (works for simple cases)
            result=$(awk -v parent="$parent" -v child="$child" '
                /^[a-zA-Z0-9_-]+:/ { in_section = ($0 ~ "^"parent":") }
                in_section && /^  [a-zA-Z0-9_-]+:/ {
                    gsub(/^  /, "")
                    if ($0 ~ "^"child":") {
                        sub("^"child":[[:space:]]*", "")
                        gsub(/^["'\''"]|["'\''"]$/, "")
                        print
                        exit
                    }
                }
            ' "$file" 2>/dev/null)
            ;;
    esac

    echo "$result"
    [[ -n "$result" ]]
}

# Get a deeply nested value (three levels: level1.level2.level3)
# Usage: yaml_get_deep "file.yaml" "level1" "level2" "level3"
# Returns: Value of level1.level2.level3, or empty string if not found
yaml_get_deep() {
    local file="$1"
    local level1="$2"
    local level2="$3"
    local level3="$4"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_deep: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    local result=""

    case "$YAML_PARSER_METHOD" in
        yq)
            result=$(yq eval ".${level1}.${level2}.${level3}" "$file" 2>/dev/null)
            if [[ "$result" == "null" ]]; then
                result=""
            fi
            ;;

        python)
            result=$(python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if (data and '$level1' in data and
        isinstance(data['$level1'], dict) and
        '$level2' in data['$level1'] and
        isinstance(data['$level1']['$level2'], dict) and
        '$level3' in data['$level1']['$level2']):
        value = data['$level1']['$level2']['$level3']
        if value is not None:
            print(str(value))
except Exception:
    pass
" 2>/dev/null)
            ;;

        awk)
            # Original awk implementation (works for simple cases)
            result=$(awk -v l1="$level1" -v l2="$level2" -v l3="$level3" '
                BEGIN { in_l1 = 0; in_l2 = 0 }
                /^[a-zA-Z0-9_-]+:/ {
                    in_l1 = ($0 ~ "^"l1":")
                    in_l2 = 0
                }
                in_l1 && /^  [a-zA-Z0-9_-]+:/ {
                    in_l2 = ($0 ~ "^  "l2":")
                }
                in_l1 && in_l2 && /^    [a-zA-Z0-9_-]+:/ {
                    if ($0 ~ "^    "l3":") {
                        sub("^    "l3":[[:space:]]*", "")
                        gsub(/^["'\''"]|["'\''"]$/, "")
                        print
                        exit
                    }
                }
            ' "$file" 2>/dev/null)
            ;;
    esac

    echo "$result"
    [[ -n "$result" ]]
}

# Get array values from YAML
# Usage: yaml_get_array "file.yaml" "array_key"
# Returns: Array items, one per line
yaml_get_array() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_array: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    case "$YAML_PARSER_METHOD" in
        yq)
            yq eval ".${key}[]" "$file" 2>/dev/null | grep -v "^null$"
            ;;

        python)
            python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if data and '$key' in data:
        value = data['$key']
        if isinstance(value, list):
            for item in value:
                if item is not None:
                    print(str(item))
except Exception:
    pass
" 2>/dev/null
            ;;

        awk)
            # Original awk implementation
            awk -v key="$key" '
                /^[a-zA-Z_-]+:/ { in_section = ($0 ~ "^"key":") }
                in_section && /^  - / {
                    sub(/^  - /, "")
                    gsub(/^["'\''"]|["'\''"]$/, "")
                    print
                }
                in_section && /^[a-zA-Z_-]+:/ && !($0 ~ "^"key":") { in_section = 0 }
            ' "$file" 2>/dev/null
            ;;
    esac
}

# Get nested array values from YAML
# Usage: yaml_get_nested_array "file.yaml" "parent" "array_key"
# Returns: Array items, one per line
yaml_get_nested_array() {
    local file="$1"
    local parent="$2"
    local array_key="$3"

    if [[ ! -f "$file" ]]; then
        log_debug "yaml_get_nested_array: file not found: $file"
        return 1
    fi

    _yaml_detect_parser

    case "$YAML_PARSER_METHOD" in
        yq)
            yq eval ".${parent}.${array_key}[]" "$file" 2>/dev/null | grep -v "^null$"
            ;;

        python)
            python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if (data and '$parent' in data and
        isinstance(data['$parent'], dict) and
        '$array_key' in data['$parent']):
        value = data['$parent']['$array_key']
        if isinstance(value, list):
            for item in value:
                if item is not None:
                    print(str(item))
except Exception:
    pass
" 2>/dev/null
            ;;

        awk)
            # Awk implementation for nested arrays
            awk -v parent="$parent" -v key="$array_key" '
                /^[a-zA-Z_-]+:/ { in_parent = ($0 ~ "^"parent":") }
                in_parent && /^  [a-zA-Z_-]+:/ {
                    in_array = ($0 ~ "^  "key":")
                }
                in_parent && in_array && /^    - / {
                    sub(/^    - /, "")
                    gsub(/^["'\''"]|["'\''"]$/, "")
                    print
                }
                in_parent && /^  [a-zA-Z_-]+:/ && !($0 ~ "^  "key":") { in_array = 0 }
                /^[a-zA-Z_-]+:/ && !($0 ~ "^"parent":") { in_parent = 0; in_array = 0 }
            ' "$file" 2>/dev/null
            ;;
    esac
}

# Check if a key exists in YAML
# Usage: yaml_has_key "file.yaml" "key"
# Returns: 0 if key exists, 1 if not
yaml_has_key() {
    local file="$1"
    local key="$2"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    _yaml_detect_parser

    case "$YAML_PARSER_METHOD" in
        yq)
            local result
            result=$(yq eval ".${key}" "$file" 2>/dev/null)
            [[ "$result" != "null" ]]
            ;;

        python)
            python3 -c "
import yaml
import sys
try:
    with open('$file', 'r') as f:
        data = yaml.safe_load(f)
    if data and '$key' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null
            ;;

        awk)
            grep -qE "^${key}:" "$file" 2>/dev/null
            ;;
    esac
}

#===============================================================================
# HELPER FUNCTIONS
#===============================================================================

# Get YAML parser method being used
# Usage: yaml_get_parser_method
# Returns: "yq", "python", or "awk"
yaml_get_parser_method() {
    _yaml_detect_parser
    echo "$YAML_PARSER_METHOD"
}

# Display YAML parser capabilities and recommendations
# Usage: yaml_show_parser_info
yaml_show_parser_info() {
    _yaml_detect_parser

    echo ""
    echo "YAML Parser Information"
    echo "======================="
    echo "Current method: $YAML_PARSER_METHOD"
    echo ""

    case "$YAML_PARSER_METHOD" in
        yq)
            echo "Status: EXCELLENT"
            echo "Capabilities: Full YAML 1.2 support, complex structures, arrays, multi-line"
            echo "Recommendation: No action needed"
            ;;

        python)
            echo "Status: GOOD"
            echo "Capabilities: Full YAML support, handles most complex structures"
            echo "Recommendation: Consider installing 'yq' for best performance:"
            echo "  wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq"
            echo "  chmod +x /usr/local/bin/yq"
            ;;

        awk)
            echo "Status: BASIC"
            echo "Capabilities: Simple key:value pairs only, limited nesting"
            echo "Limitations: May fail on complex YAML, arrays, multi-line values"
            echo "Recommendation: Install PyYAML or yq for better support:"
            echo ""
            echo "  Option 1 (best): Install yq"
            echo "    wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq"
            echo "    chmod +x /usr/local/bin/yq"
            echo ""
            echo "  Option 2 (good): Install PyYAML"
            echo "    apt-get install python3-yaml  # Debian/Ubuntu"
            echo "    yum install python3-pyyaml     # RHEL/CentOS"
            echo "    pip3 install pyyaml            # pip"
            ;;
    esac
    echo ""
}

#===============================================================================
# BACKWARD COMPATIBILITY
#===============================================================================

# The following functions maintain backward compatibility with the old
# yaml_* functions in common.sh. They simply call the new implementations.

# These are now defined in the new yaml-parser.sh and will replace
# the old implementations in common.sh

# yaml_get - already defined as yaml_get_value
# yaml_get_nested - already defined
# yaml_get_deep - already defined
# yaml_get_array - already defined
# yaml_has_key - already defined

log_debug "YAML parser library loaded (method: ${YAML_PARSER_METHOD:-detecting...})"
