#!/bin/bash
#===============================================================================
# Installation Helper Functions
# Common security-hardened functions for module installation
#===============================================================================

# SECURITY: Standard systemd hardening template
# Returns hardened systemd service directives
# Usage: get_systemd_hardening_directives
get_systemd_hardening_directives() {
    cat << 'EOF'
# SECURITY: Systemd hardening directives
# Restrict filesystem access
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

# Prevent privilege escalation
NoNewPrivileges=true

# Kernel protection
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true

# Network restrictions
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# System call filtering
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources
SystemCallErrorNumber=EPERM

# Capabilities - minimal required
CapabilityBoundingSet=

# Namespace and device restrictions
RestrictNamespaces=true
PrivateDevices=true

# Additional hardening
LockPersonality=true
RestrictRealtime=true
ProtectClock=true
EOF
}

# SECURITY: Download binary with checksum verification
# Usage: secure_download_binary "url" "checksum_url" "output_file"
secure_download_binary() {
    local url="$1"
    local checksum_url="$2"
    local output_file="$3"

    if type download_and_verify &>/dev/null; then
        if ! download_and_verify "$url" "$output_file" "$checksum_url"; then
            log_error "SECURITY: Failed to download and verify $(basename "$output_file")"
            return 1
        fi
    else
        log_warn "SECURITY: download_and_verify not available, downloading without verification"
        if ! wget -q --timeout=60 --tries=3 "$url" -O "$output_file"; then
            log_error "Failed to download from $url"
            return 1
        fi
    fi
    return 0
}

# SECURITY: Set ownership and permissions safely
# Usage: secure_install_binary "source" "destination" "owner:group"
secure_install_binary() {
    local source="$1"
    local destination="$2"
    local owner_group="$3"

    if ! cp "$source" "$destination"; then
        log_error "Failed to copy binary to $destination"
        return 1
    fi

    if type safe_chown &>/dev/null && type safe_chmod &>/dev/null; then
        safe_chown "$owner_group" "$destination" || {
            log_error "Failed to set ownership on $destination"
            rm -f "$destination"
            return 1
        }
        safe_chmod 755 "$destination" "$(basename "$destination") binary" || {
            log_error "Failed to set permissions on $destination"
            rm -f "$destination"
            return 1
        }
    else
        chown "$owner_group" "$destination"
        chmod 755 "$destination"
    fi

    log_success "Binary installed: $destination"
    return 0
}
