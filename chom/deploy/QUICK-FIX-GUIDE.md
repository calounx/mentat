# Quick Fix Guide - Priority Order

## 🔥 CRITICAL - Fix Today (4-8 hours)

### 1. Command Injection in remote_exec (60 min)

**File:** `deploy-enhanced.sh` line 934

**Find this:**
```bash
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        "$cmd"
}
```

**Replace with:**
```bash
remote_exec() {
    local host=$1
    local user=$2
    local port=$3
    local cmd=$4
    local key_path="${KEYS_DIR}/chom_deploy_key"

    # Validate inputs
    if ! [[ "$host" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid host IP: $host"
        return 1
    fi
    if ! [[ "$user" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid username: $user"
        return 1
    fi
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ $port -lt 1 || $port -gt 65535 ]]; then
        log_error "Invalid port: $port"
        return 1
    fi

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -i "$key_path" \
        -p "$port" \
        "${user}@${host}" \
        -- \
        "$cmd"
}
```

**Also fix line 1917:**
```bash
# Before this line:
local obs_ip=$(get_config '.observability.ip')

# Add validation:
if ! [[ "$obs_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    log_error "Invalid observability IP: $obs_ip"
    exit 1
fi
```

---

### 2. Remove eval Usage (120 min)

**File:** `deploy-enhanced.sh` line 989-1046

**Find this:**
```bash
retry_with_healing() {
    local operation_name=$1
    local command_to_retry=$2
    local auto_fix_function=${3:-""}

    local attempt=1
    local max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $operation_name"

        if eval "$command_to_retry"; then  # BAD!
            if [[ $attempt -gt 1 ]]; then
                log_success "$operation_name succeeded after $attempt attempts"
            fi
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -eq $max_attempts ]]; then
            log_error "$operation_name failed after $max_attempts attempts"
            return $exit_code
        fi

        if [[ -n "$auto_fix_function" && "$AUTO_FIX" == "true" ]]; then
            log_warn "Attempting auto-fix..."
            if eval "$auto_fix_function"; then  # BAD!
                log_info "Auto-fix successful, retrying immediately"
                ((attempt++))
                continue
            fi
        fi

        local delay=$(calculate_backoff $attempt)
        log_warn "$operation_name failed (exit code: $exit_code)"
        log_info "Retrying in $delay seconds... (attempt $((attempt + 1))/$max_attempts)"

        if [[ "$QUIET" != "true" ]]; then
            for ((i=delay; i>0; i--)); do
                printf "\r  ${BLUE}Waiting: %2ds ${NC}" $i
                sleep 1
            done
            printf "\r                \r"
        else
            sleep $delay
        fi

        ((attempt++))
    done

    return 1
}
```

**Replace with:**
```bash
retry_with_healing() {
    local operation_name=$1
    shift  # Remove first arg, rest are command + args

    local attempt=1
    local max_attempts=$MAX_RETRIES

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: $operation_name"

        # Execute command directly (no eval!)
        if "$@"; then
            if [[ $attempt -gt 1 ]]; then
                log_success "$operation_name succeeded after $attempt attempts"
            fi
            return 0
        fi

        local exit_code=$?

        if [[ $attempt -eq $max_attempts ]]; then
            log_error "$operation_name failed after $max_attempts attempts"
            return $exit_code
        fi

        local delay=$(calculate_backoff $attempt)
        log_warn "$operation_name failed (exit code: $exit_code)"
        log_info "Retrying in $delay seconds... (attempt $((attempt + 1))/$max_attempts)"

        if [[ "$QUIET" != "true" ]]; then
            for ((i=$delay; i>0; i--)); do
                printf "\r  ${BLUE}Waiting: %2ds ${NC}" $i
                sleep 1
            done
            printf "\r                \r"
        else
            sleep "$delay"
        fi

        ((attempt++))
    done

    return 1
}
```

**Update all callers** (search for `retry_with_healing`):
```bash
# OLD:
retry_with_healing "operation" "some_function arg1 arg2"

# NEW:
retry_with_healing "operation" some_function arg1 arg2
```

---

### 3. Fix Credential Temp File (60 min)

**File:** `setup-vpsmanager-vps.sh` line 228-244

**Find this:**
```bash
cat > /tmp/.my.cnf << EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD}
