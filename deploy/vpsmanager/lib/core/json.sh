#!/usr/bin/env bash
# JSON output helpers for vpsmanager
# All output must be valid JSON for VPSManagerBridge parsing

# Escape a string for JSON (defined first as it's used by other functions)
# Usage: escaped=$(json_escape "string with \"quotes\"")
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"  # Escape backslashes first
    str="${str//\"/\\\"}"  # Escape quotes
    str="${str//$'\t'/\\t}" # Escape tabs
    str="${str//$'\n'/\\n}" # Escape newlines
    str="${str//$'\r'/\\r}" # Escape carriage returns
    echo "$str"
}

# Output a success response
# Usage: json_success "message" '{"key": "value"}'
json_success() {
    local message="${1:-Operation completed}"
    local data="${2:-{}}"

    # Escape message for JSON safety
    message=$(json_escape "$message")

    cat <<EOF
{"success":true,"message":"${message}","data":${data}}
EOF
}

# Output an error response
# Usage: json_error "error message" "ERROR_CODE"
json_error() {
    local error="${1:-An error occurred}"
    local code="${2:-UNKNOWN_ERROR}"

    # Escape error message for JSON safety
    error=$(json_escape "$error")

    cat <<EOF
{"success":false,"error":"${error}","code":"${code}"}
EOF
}

# Build a JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2"
json_object() {
    local result="{"
    local first=true

    while [[ $# -ge 2 ]]; do
        local key="$1"
        local value="$2"
        shift 2

        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi

        # Check if value is already JSON (starts with { or [) or is a number/boolean/null
        # Also handle negative numbers and decimals
        if [[ "$value" =~ ^[\{\[] ]] || [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]] || [[ "$value" == "null" ]]; then
            result+="\"${key}\":${value}"
        else
            result+="\"${key}\":\"$(json_escape "$value")\""
        fi
    done

    result+="}"
    echo "$result"
}

# Build a JSON array from values
# Usage: json_array "value1" "value2" "value3"
json_array() {
    local result="["
    local first=true

    for value in "$@"; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi

        # Check if value is already JSON or a number/boolean
        if [[ "$value" =~ ^[\{\[] ]] || [[ "$value" =~ ^-?[0-9]+\.?[0-9]*$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]] || [[ "$value" == "null" ]]; then
            result+="${value}"
        else
            result+="\"$(json_escape "$value")\""
        fi
    done

    result+="]"
    echo "$result"
}
