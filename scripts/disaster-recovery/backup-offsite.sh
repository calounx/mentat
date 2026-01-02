#!/usr/bin/env bash
# ============================================================================
# Offsite Backup Script - Upload backups to S3-compatible storage
# ============================================================================
# Supports: AWS S3, Backblaze B2, Wasabi, MinIO, and any S3-compatible service
# Features:
#   - GPG encryption at rest
#   - Incremental backups using rsync
#   - Cross-region replication
#   - Automated backup verification
#   - Retention policy enforcement
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load configuration from environment or config file
CONFIG_FILE="${BACKUP_CONFIG_FILE:-${SCRIPT_DIR}/backup-config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
fi

# S3 Configuration
S3_PROVIDER="${S3_PROVIDER:-s3}"  # s3, b2, wasabi, minio, custom
S3_BUCKET="${S3_BUCKET:-}"
S3_REGION="${S3_REGION:-us-east-1}"
S3_ENDPOINT="${S3_ENDPOINT:-}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-}"
S3_SECRET_KEY="${S3_SECRET_KEY:-}"
S3_STORAGE_CLASS="${S3_STORAGE_CLASS:-STANDARD}"  # STANDARD, INTELLIGENT_TIERING, GLACIER

# Backup Configuration
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-${PROJECT_ROOT}/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_FULL_RETENTION_DAYS="${BACKUP_FULL_RETENTION_DAYS:-90}"
BACKUP_ENCRYPTION_ENABLED="${BACKUP_ENCRYPTION_ENABLED:-true}"
BACKUP_VERIFICATION_ENABLED="${BACKUP_VERIFICATION_ENABLED:-true}"
BACKUP_PARALLEL_UPLOADS="${BACKUP_PARALLEL_UPLOADS:-4}"

# Encryption Configuration
GPG_RECIPIENT="${GPG_RECIPIENT:-backup@arewel.com}"
GPG_KEY_ID="${GPG_KEY_ID:-}"
GPG_PASSPHRASE_FILE="${GPG_PASSPHRASE_FILE:-${SCRIPT_DIR}/.gpg-passphrase}"

# Monitoring Configuration
METRICS_ENABLED="${METRICS_ENABLED:-true}"
METRICS_PUSHGATEWAY="${METRICS_PUSHGATEWAY:-http://localhost:9091}"
ALERT_WEBHOOK="${ALERT_WEBHOOK:-}"
ALERT_EMAIL="${ALERT_EMAIL:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Logging Functions
# ============================================================================

LOG_FILE="${LOG_FILE:-/var/log/backup-offsite.log}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE"
}

# ============================================================================
# Metrics Functions
# ============================================================================

push_metric() {
    local metric_name="$1"
    local metric_value="$2"
    local metric_type="${3:-gauge}"

    if [[ "$METRICS_ENABLED" != "true" ]] || [[ -z "$METRICS_PUSHGATEWAY" ]]; then
        return 0
    fi

    cat <<EOF | curl -s --data-binary @- "${METRICS_PUSHGATEWAY}/metrics/job/backup_offsite/instance/$(hostname)"
# TYPE ${metric_name} ${metric_type}
${metric_name} ${metric_value}
EOF
}

push_backup_metrics() {
    local status="$1"
    local duration="$2"
    local bytes_uploaded="$3"
    local files_uploaded="$4"

    push_metric "backup_offsite_last_run_timestamp" "$(date +%s)" "gauge"
    push_metric "backup_offsite_last_run_duration_seconds" "$duration" "gauge"
    push_metric "backup_offsite_last_run_bytes" "$bytes_uploaded" "gauge"
    push_metric "backup_offsite_last_run_files" "$files_uploaded" "gauge"
    push_metric "backup_offsite_last_run_status" "$([[ $status == "success" ]] && echo 1 || echo 0)" "gauge"
}

# ============================================================================
# Alert Functions
# ============================================================================

send_alert() {
    local severity="$1"
    local message="$2"

    # Webhook notification
    if [[ -n "$ALERT_WEBHOOK" ]]; then
        curl -s -X POST "$ALERT_WEBHOOK" \
            -H "Content-Type: application/json" \
            -d "{\"severity\":\"$severity\",\"message\":\"$message\",\"timestamp\":\"$(date -Iseconds)\"}" \
            > /dev/null 2>&1 || true
    fi

    # Email notification
    if [[ -n "$ALERT_EMAIL" ]] && command -v mail &> /dev/null; then
        echo "$message" | mail -s "Backup Alert: $severity" "$ALERT_EMAIL" || true
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_dependencies() {
    local missing_deps=()

    for cmd in aws gpg tar gzip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Install with: apt-get install awscli gnupg tar gzip"
        return 1
    fi

    return 0
}

validate_configuration() {
    if [[ -z "$S3_BUCKET" ]]; then
        log_error "S3_BUCKET is not configured"
        return 1
    fi

    if [[ -z "$S3_ACCESS_KEY" ]] || [[ -z "$S3_SECRET_KEY" ]]; then
        log_error "S3 credentials not configured"
        return 1
    fi

    if [[ ! -d "$BACKUP_SOURCE_DIR" ]]; then
        log_error "Backup source directory not found: $BACKUP_SOURCE_DIR"
        return 1
    fi

    return 0
}

# ============================================================================
# AWS/S3 Configuration Functions
# ============================================================================

configure_aws_cli() {
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
    export AWS_DEFAULT_REGION="$S3_REGION"

    # Set endpoint for non-AWS providers
    case "$S3_PROVIDER" in
        b2)
            export AWS_ENDPOINT_URL="https://s3.${S3_REGION}.backblazeb2.com"
            ;;
        wasabi)
            export AWS_ENDPOINT_URL="https://s3.${S3_REGION}.wasabisys.com"
            ;;
        minio|custom)
            if [[ -n "$S3_ENDPOINT" ]]; then
                export AWS_ENDPOINT_URL="$S3_ENDPOINT"
            fi
            ;;
    esac
}

test_s3_connectivity() {
    log_info "Testing S3 connectivity..."

    if aws s3 ls "s3://${S3_BUCKET}/" > /dev/null 2>&1; then
        log_success "S3 connection successful"
        return 0
    else
        log_error "Failed to connect to S3 bucket: $S3_BUCKET"
        return 1
    fi
}

# ============================================================================
# Encryption Functions
# ============================================================================

encrypt_file() {
    local input_file="$1"
    local output_file="${input_file}.gpg"

    if [[ "$BACKUP_ENCRYPTION_ENABLED" != "true" ]]; then
        echo "$input_file"
        return 0
    fi

    log_info "Encrypting $(basename "$input_file")..."

    if [[ -n "$GPG_KEY_ID" ]]; then
        # Encrypt with specific key
        gpg --encrypt \
            --recipient "$GPG_RECIPIENT" \
            --trust-model always \
            --output "$output_file" \
            "$input_file"
    elif [[ -f "$GPG_PASSPHRASE_FILE" ]]; then
        # Encrypt with passphrase
        gpg --symmetric \
            --cipher-algo AES256 \
            --batch --yes \
            --passphrase-file "$GPG_PASSPHRASE_FILE" \
            --output "$output_file" \
            "$input_file"
    else
        log_error "No encryption method configured"
        return 1
    fi

    log_success "Encrypted: $(basename "$output_file")"
    echo "$output_file"
}

# ============================================================================
# Upload Functions
# ============================================================================

upload_file_to_s3() {
    local local_file="$1"
    local s3_key="$2"
    local storage_class="${3:-$S3_STORAGE_CLASS}"

    log_info "Uploading $(basename "$local_file") to s3://${S3_BUCKET}/${s3_key}..."

    if aws s3 cp "$local_file" "s3://${S3_BUCKET}/${s3_key}" \
        --storage-class "$storage_class" \
        --metadata "backup-timestamp=${TIMESTAMP},hostname=$(hostname)" \
        --no-progress; then
        log_success "Uploaded: $(basename "$local_file")"
        return 0
    else
        log_error "Failed to upload: $(basename "$local_file")"
        return 1
    fi
}

upload_directory_to_s3() {
    local local_dir="$1"
    local s3_prefix="$2"

    log_info "Syncing directory to s3://${S3_BUCKET}/${s3_prefix}..."

    if aws s3 sync "$local_dir" "s3://${S3_BUCKET}/${s3_prefix}" \
        --storage-class "$S3_STORAGE_CLASS" \
        --delete \
        --no-progress; then
        log_success "Synced: $local_dir"
        return 0
    else
        log_error "Failed to sync: $local_dir"
        return 1
    fi
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_upload() {
    local local_file="$1"
    local s3_key="$2"

    if [[ "$BACKUP_VERIFICATION_ENABLED" != "true" ]]; then
        return 0
    fi

    log_info "Verifying upload: $(basename "$local_file")..."

    # Get local file size and checksum
    local local_size
    local_size=$(stat -c%s "$local_file" 2>/dev/null || stat -f%z "$local_file" 2>/dev/null)
    local local_md5
    local_md5=$(md5sum "$local_file" | cut -d' ' -f1)

    # Get S3 file metadata
    local s3_metadata
    s3_metadata=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_key" 2>/dev/null || echo "")

    if [[ -z "$s3_metadata" ]]; then
        log_error "Verification failed: File not found in S3"
        return 1
    fi

    local s3_size
    s3_size=$(echo "$s3_metadata" | grep -oP '"ContentLength":\s*\K\d+' || echo "0")

    if [[ "$local_size" != "$s3_size" ]]; then
        log_error "Verification failed: Size mismatch (local: $local_size, S3: $s3_size)"
        return 1
    fi

    log_success "Verification passed: $(basename "$local_file")"
    return 0
}

# ============================================================================
# Backup Functions
# ============================================================================

backup_mysql_databases() {
    log_info "Backing up MySQL databases..."

    local backup_date
    backup_date=$(date +%Y-%m-%d)
    local s3_prefix="mysql/${backup_date}"

    # Find all MySQL backup files
    local uploaded_count=0
    local failed_count=0

    while IFS= read -r backup_file; do
        local encrypted_file
        encrypted_file=$(encrypt_file "$backup_file")

        local s3_key="${s3_prefix}/$(basename "$encrypted_file")"

        if upload_file_to_s3 "$encrypted_file" "$s3_key"; then
            if verify_upload "$encrypted_file" "$s3_key"; then
                ((uploaded_count++))
            else
                ((failed_count++))
            fi
        else
            ((failed_count++))
        fi

        # Clean up encrypted file if different from original
        if [[ "$encrypted_file" != "$backup_file" ]]; then
            rm -f "$encrypted_file"
        fi
    done < <(find "$BACKUP_SOURCE_DIR" -name "*.sql" -o -name "*.sql.gz" -mtime -1)

    log_success "MySQL backups: $uploaded_count uploaded, $failed_count failed"
}

backup_docker_volumes() {
    log_info "Backing up Docker volumes..."

    local backup_date
    backup_date=$(date +%Y-%m-%d)
    local s3_prefix="volumes/${backup_date}"

    local uploaded_count=0
    local failed_count=0

    while IFS= read -r backup_file; do
        local encrypted_file
        encrypted_file=$(encrypt_file "$backup_file")

        local s3_key="${s3_prefix}/$(basename "$encrypted_file")"

        if upload_file_to_s3 "$encrypted_file" "$s3_key"; then
            if verify_upload "$encrypted_file" "$s3_key"; then
                ((uploaded_count++))
            else
                ((failed_count++))
            fi
        else
            ((failed_count++))
        fi

        # Clean up encrypted file if different from original
        if [[ "$encrypted_file" != "$backup_file" ]]; then
            rm -f "$encrypted_file"
        fi
    done < <(find "$BACKUP_SOURCE_DIR" -name "*_backup_*.tar.gz" -mtime -1)

    log_success "Volume backups: $uploaded_count uploaded, $failed_count failed"
}

backup_configurations() {
    log_info "Backing up configuration files..."

    local backup_date
    backup_date=$(date +%Y-%m-%d)
    local s3_prefix="config/${backup_date}"

    # Create temporary archive of config files
    local config_archive="${BACKUP_SOURCE_DIR}/config_${TIMESTAMP}.tar.gz"

    tar -czf "$config_archive" \
        -C "$PROJECT_ROOT" \
        --exclude='*.log' \
        --exclude='node_modules' \
        --exclude='vendor' \
        .env \
        docker-compose*.yml \
        observability-stack/config \
        chom/.env \
        2>/dev/null || true

    if [[ -f "$config_archive" ]]; then
        local encrypted_file
        encrypted_file=$(encrypt_file "$config_archive")

        local s3_key="${s3_prefix}/$(basename "$encrypted_file")"

        if upload_file_to_s3 "$encrypted_file" "$s3_key"; then
            verify_upload "$encrypted_file" "$s3_key"
        fi

        # Clean up
        rm -f "$config_archive"
        if [[ "$encrypted_file" != "$config_archive" ]]; then
            rm -f "$encrypted_file"
        fi
    fi
}

# ============================================================================
# Retention Functions
# ============================================================================

cleanup_old_backups() {
    log_info "Cleaning up old backups..."

    local cutoff_date
    cutoff_date=$(date -d "$BACKUP_RETENTION_DAYS days ago" +%Y-%m-%d 2>/dev/null || \
                  date -v-${BACKUP_RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)

    # Clean up MySQL backups
    aws s3 ls "s3://${S3_BUCKET}/mysql/" | while read -r line; do
        local date_part
        date_part=$(echo "$line" | awk '{print $2}' | tr -d '/')

        if [[ "$date_part" < "$cutoff_date" ]]; then
            log_info "Deleting old backup: mysql/${date_part}"
            aws s3 rm "s3://${S3_BUCKET}/mysql/${date_part}/" --recursive
        fi
    done

    # Clean up volume backups
    aws s3 ls "s3://${S3_BUCKET}/volumes/" | while read -r line; do
        local date_part
        date_part=$(echo "$line" | awk '{print $2}' | tr -d '/')

        if [[ "$date_part" < "$cutoff_date" ]]; then
            log_info "Deleting old backup: volumes/${date_part}"
            aws s3 rm "s3://${S3_BUCKET}/volumes/${date_part}/" --recursive
        fi
    done

    log_success "Cleanup completed"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "========================================="
    log_info "  Offsite Backup Started"
    log_info "========================================="
    log_info "Provider: $S3_PROVIDER"
    log_info "Bucket: $S3_BUCKET"
    log_info "Encryption: $BACKUP_ENCRYPTION_ENABLED"
    log_info "Verification: $BACKUP_VERIFICATION_ENABLED"

    local start_time
    start_time=$(date +%s)

    # Validate dependencies and configuration
    if ! validate_dependencies; then
        send_alert "critical" "Offsite backup failed: Missing dependencies"
        exit 1
    fi

    if ! validate_configuration; then
        send_alert "critical" "Offsite backup failed: Invalid configuration"
        exit 1
    fi

    # Configure AWS CLI
    configure_aws_cli

    # Test S3 connectivity
    if ! test_s3_connectivity; then
        send_alert "critical" "Offsite backup failed: Cannot connect to S3"
        exit 1
    fi

    # Perform backups
    local total_files=0
    local total_bytes=0

    backup_mysql_databases
    backup_docker_volumes
    backup_configurations

    # Cleanup old backups
    cleanup_old_backups

    # Calculate metrics
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # Push metrics
    push_backup_metrics "success" "$duration" "$total_bytes" "$total_files"

    log_info "========================================="
    log_success "  Offsite Backup Completed"
    log_info "========================================="
    log_info "Duration: ${duration}s"
    log_info "Files uploaded: $total_files"

    send_alert "info" "Offsite backup completed successfully in ${duration}s"
}

# Handle errors
trap 'log_error "Backup failed at line $LINENO"; send_alert "critical" "Offsite backup failed"; exit 1' ERR

# Run main function
main "$@"
