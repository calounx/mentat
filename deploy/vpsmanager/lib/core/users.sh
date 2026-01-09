#!/usr/bin/env bash
# User management functions for VPSManager
# Handles per-site system user creation for security isolation

# Create site-specific system user
# Each site gets its own isolated system user (www-site-example-com)
# This prevents cross-site file access and enforces security boundaries
#
# Usage: create_site_user "example.com"
create_site_user() {
    local domain="$1"
    local username
    username=$(domain_to_username "$domain")

    # Check if user already exists
    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
        return 0
    fi

    # Create system user with restricted permissions
    # - --system: Create as system user (UID < 1000)
    # - --no-create-home: No home directory needed
    # - --shell /usr/sbin/nologin: Cannot login interactively
    # - --comment: Document which site this user belongs to
    if useradd --system \
        --no-create-home \
        --shell /usr/sbin/nologin \
        --comment "Site: $domain" \
        "$username" 2>/dev/null; then
        log_info "Created system user: $username for $domain"
        return 0
    else
        log_error "Failed to create user: $username"
        return 1
    fi
}

# Convert domain to safe username
# Transforms domain.example.com -> www-site-domain-example-com
# Ensures compatibility with Linux username restrictions:
# - Max 32 characters (we use 28 + 4 for "www-" prefix)
# - Only alphanumeric and hyphens
# - Must start with letter
#
# Usage: username=$(domain_to_username "example.com")
domain_to_username() {
    local domain="$1"
    local safe_domain

    # Replace dots with hyphens: example.com -> example-com
    safe_domain="${domain//\./-}"

    # Truncate to 28 chars to leave room for "www-" prefix (total 32)
    safe_domain="${safe_domain:0:28}"

    # Remove any trailing hyphens that might result from truncation
    safe_domain="${safe_domain%-}"

    # Add "www-site-" prefix to clearly identify these as site users
    echo "www-site-${safe_domain}"
}

# Delete site-specific user
# Removes the system user when a site is deleted
# Does not remove files - those should be deleted separately
#
# Usage: delete_site_user "example.com"
delete_site_user() {
    local domain="$1"
    local username
    username=$(domain_to_username "$domain")

    if id "$username" &>/dev/null; then
        if userdel "$username" 2>/dev/null; then
            log_info "Deleted system user: $username"
            return 0
        else
            log_error "Failed to delete user: $username"
            return 1
        fi
    else
        log_info "User $username does not exist (already deleted)"
        return 0
    fi
}

# Check if site user exists
# Usage: if site_user_exists "example.com"; then ... fi
site_user_exists() {
    local domain="$1"
    local username
    username=$(domain_to_username "$domain")

    id "$username" &>/dev/null
}

# Get username for domain
# Convenience function to get username without creating it
# Usage: username=$(get_site_username "example.com")
get_site_username() {
    local domain="$1"
    domain_to_username "$domain"
}

# Verify user ownership of site directory
# Checks that site files are owned by the correct site-specific user
# Usage: verify_site_ownership "example.com" "/var/www/sites/example.com"
verify_site_ownership() {
    local domain="$1"
    local site_root="$2"
    local username
    username=$(domain_to_username "$domain")

    if [[ ! -d "$site_root" ]]; then
        log_error "Site directory does not exist: $site_root"
        return 1
    fi

    local actual_owner
    actual_owner=$(stat -c '%U' "$site_root")

    if [[ "$actual_owner" == "$username" ]]; then
        log_success "Site ownership verified: $site_root owned by $username"
        return 0
    else
        log_error "Site ownership mismatch: $site_root owned by $actual_owner (expected $username)"
        return 1
    fi
}
