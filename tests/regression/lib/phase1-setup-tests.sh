#!/bin/bash
# ============================================================================
# Phase 1: Environment Setup Tests
# ============================================================================
# Tests for Docker Compose validation, container startup, and network config
# ============================================================================

set -euo pipefail

# Source test utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-utils.sh"

# ============================================================================
# Test Functions
# ============================================================================

test_docker_compose_syntax() {
    local compose_file="$1"
    local test_name="Docker Compose Syntax: $(basename "${compose_file}")"

    start_test "${test_name}"

    if ! docker_compose_file_exists "${compose_file}"; then
        log_error "Compose file not found: ${compose_file}"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    if docker_compose_validate "${compose_file}"; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Compose file validation failed"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_port_conflicts() {
    local compose_file="$1"
    local test_name="Port Conflict Check: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Extract all port mappings
    local ports
    ports=$(docker compose -f "${compose_file}" config | grep -E '^\s+- "[0-9]+:' | sed 's/.*"\([0-9]*\):.*/\1/' | sort -u)

    # Check for conflicts with running containers
    local conflicts=0
    while IFS= read -r port; do
        if [[ -n "${port}" ]] && netstat -tuln 2>/dev/null | grep -q ":${port} "; then
            log_warn "Port ${port} is already in use"
            conflicts=$((conflicts + 1))
        fi
    done <<< "${ports}"

    if [[ ${conflicts} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Found ${conflicts} port conflicts (this may be expected if containers are running)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_volume_mounts() {
    local compose_file="$1"
    local base_dir="$(dirname "${compose_file}")"
    local test_name="Volume Mount Validation: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Extract bind mount paths
    local mounts
    mounts=$(docker compose -f "${compose_file}" config | grep -E '^\s+- \.' | sed 's/.*- \([^:]*\):.*/\1/')

    local missing=0
    while IFS= read -r mount; do
        if [[ -n "${mount}" ]]; then
            local full_path
            if [[ "${mount}" == /* ]]; then
                full_path="${mount}"
            else
                full_path="${base_dir}/${mount}"
            fi

            if [[ ! -e "${full_path}" ]]; then
                log_warn "Mount path does not exist: ${full_path}"
                missing=$((missing + 1))
            fi
        fi
    done <<< "${mounts}"

    if [[ ${missing} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Found ${missing} missing mount paths (some may be created at runtime)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_network_configuration() {
    local compose_file="$1"
    local test_name="Network Configuration: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Validate network definitions exist
    local networks
    networks=$(docker compose -f "${compose_file}" config | grep -A 5 "^networks:" | grep -E '^\s+[a-z]' | sed 's/:.*//' | tr -d ' ')

    if [[ -z "${networks}" ]]; then
        log_warn "No custom networks defined"
        end_test "${test_name}" "WARN"
        return 0
    fi

    # Check for subnet overlaps (basic check)
    local subnets
    subnets=$(docker compose -f "${compose_file}" config | grep -E '^\s+- subnet:' | sed 's/.*subnet: //')

    local subnet_count
    subnet_count=$(echo "${subnets}" | wc -l)
    local unique_count
    unique_count=$(echo "${subnets}" | sort -u | wc -l)

    if [[ ${subnet_count} -eq ${unique_count} ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Found duplicate subnets"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_environment_variables() {
    local compose_file="$1"
    local test_name="Environment Variable Check: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Check for undefined environment variables in compose file
    local undefined
    undefined=$(docker compose -f "${compose_file}" config 2>&1 | grep -i "variable.*not set" || true)

    if [[ -z "${undefined}" ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Found undefined environment variables (defaults may be in use):"
        log_warn "${undefined}"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_container_startup() {
    local compose_file="$1"
    local timeout="${2:-300}"
    local test_name="Container Startup: $(basename "${compose_file}")"

    start_test "${test_name}"

    if docker_compose_up "${compose_file}" "${timeout}"; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Failed to start containers"
        # Capture logs
        log_info "Container status:"
        docker compose -f "${compose_file}" ps || true
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_health_checks() {
    local compose_file="$1"
    local test_name="Health Check Validation: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Get all containers from the compose file
    local containers
    containers=$(docker compose -f "${compose_file}" ps --format json 2>/dev/null | jq -r '.[].Name' || echo "")

    if [[ -z "${containers}" ]]; then
        log_error "No containers found"
        end_test "${test_name}" "FAIL"
        return 1
    fi

    local unhealthy=0
    while IFS= read -r container; do
        if [[ -n "${container}" ]]; then
            log_info "Checking health of ${container}..."
            if ! wait_for_healthy "${container}" 120; then
                unhealthy=$((unhealthy + 1))
                log_error "Container ${container} is not healthy"
                # Get logs for troubleshooting
                log_info "Last 50 lines of logs:"
                get_container_logs "${container}" 50 || true
            fi
        fi
    done <<< "${containers}"

    if [[ ${unhealthy} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "${unhealthy} containers failed health checks"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_container_logs_for_errors() {
    local compose_file="$1"
    local test_name="Container Log Error Check: $(basename "${compose_file}")"

    start_test "${test_name}"

    local containers
    containers=$(docker compose -f "${compose_file}" ps --format json 2>/dev/null | jq -r '.[].Name' || echo "")

    local errors_found=0
    while IFS= read -r container; do
        if [[ -n "${container}" ]]; then
            local logs
            logs=$(get_container_logs "${container}" 100)

            # Check for common error patterns (excluding expected warnings)
            if echo "${logs}" | grep -iE "fatal|panic|exception|error.*failed" | grep -vE "deprecated|warning|info"; then
                log_warn "Found errors in ${container} logs"
                errors_found=$((errors_found + 1))
            fi
        fi
    done <<< "${containers}"

    if [[ ${errors_found} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "Found errors in ${errors_found} container logs"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_resource_limits() {
    local compose_file="$1"
    local test_name="Resource Limit Validation: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Check if resource limits are defined
    local has_limits
    has_limits=$(docker compose -f "${compose_file}" config | grep -E 'mem_limit|cpus|memory' || echo "")

    if [[ -n "${has_limits}" ]]; then
        log_info "Resource limits are defined"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_warn "No resource limits defined (may cause resource contention)"
        end_test "${test_name}" "WARN"
        return 0
    fi
}

test_volumes_created() {
    local compose_file="$1"
    local test_name="Volume Creation: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Get volume names from compose file
    local volumes
    volumes=$(docker compose -f "${compose_file}" config --volumes 2>/dev/null || echo "")

    if [[ -z "${volumes}" ]]; then
        log_info "No named volumes defined"
        end_test "${test_name}" "PASS"
        return 0
    fi

    local missing=0
    while IFS= read -r volume; do
        if [[ -n "${volume}" ]]; then
            if ! docker volume inspect "${volume}" &>/dev/null; then
                log_error "Volume not created: ${volume}"
                missing=$((missing + 1))
            fi
        fi
    done <<< "${volumes}"

    if [[ ${missing} -eq 0 ]]; then
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "${missing} volumes were not created"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

test_inter_container_network() {
    local compose_file="$1"
    local test_name="Inter-Container Networking: $(basename "${compose_file}")"

    start_test "${test_name}"

    # Get first two containers
    local containers
    containers=$(docker compose -f "${compose_file}" ps --format json 2>/dev/null | jq -r '.[].Name' | head -2)

    local container_count
    container_count=$(echo "${containers}" | wc -l)

    if [[ ${container_count} -lt 2 ]]; then
        log_info "Less than 2 containers, skipping network test"
        end_test "${test_name}" "PASS"
        return 0
    fi

    local container1
    local container2
    container1=$(echo "${containers}" | head -1)
    container2=$(echo "${containers}" | tail -1)

    # Test ping between containers
    if exec_in_container "${container1}" ping -c 1 "${container2}" &>/dev/null; then
        log_success "Containers can communicate: ${container1} -> ${container2}"
        end_test "${test_name}" "PASS"
        return 0
    else
        log_error "Cannot ping between containers"
        end_test "${test_name}" "FAIL"
        return 1
    fi
}

# ============================================================================
# Main Test Runner
# ============================================================================

run_phase1_tests() {
    local compose_file="$1"

    start_phase "Phase 1: Environment Setup Tests"

    # Validation tests (don't require containers to be running)
    test_docker_compose_syntax "${compose_file}" || true
    test_port_conflicts "${compose_file}" || true
    test_volume_mounts "${compose_file}" || true
    test_network_configuration "${compose_file}" || true
    test_environment_variables "${compose_file}" || true
    test_resource_limits "${compose_file}" || true

    # Startup tests
    test_container_startup "${compose_file}" || return 1
    test_health_checks "${compose_file}" || true
    test_container_logs_for_errors "${compose_file}" || true
    test_volumes_created "${compose_file}" || true
    test_inter_container_network "${compose_file}" || true

    end_phase
}

# Export functions
export -f test_docker_compose_syntax
export -f test_port_conflicts
export -f test_volume_mounts
export -f test_network_configuration
export -f test_environment_variables
export -f test_container_startup
export -f test_health_checks
export -f test_container_logs_for_errors
export -f test_resource_limits
export -f test_volumes_created
export -f test_inter_container_network
export -f run_phase1_tests
