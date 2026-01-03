#!/usr/bin/env bash
# Notification utilities for deployment scripts
# Supports Slack and email notifications
# Usage: source "$(dirname "$0")/../utils/notifications.sh"

# Get utility directory (use local variable to avoid overwriting caller's SCRIPT_DIR)
_UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logging utilities
source "${_UTILS_DIR}/logging.sh"

# Send Slack notification
send_slack_notification() {
    local message="$1"
    local status="${2:-info}"  # info, success, warning, error
    local webhook_url="${SLACK_WEBHOOK_URL:-}"

    if [[ -z "$webhook_url" ]]; then
        log_info "Slack webhook URL not configured, skipping notification"
        return 0
    fi

    local color
    local emoji

    case "$status" in
        success)
            color="good"
            emoji=":white_check_mark:"
            ;;
        warning)
            color="warning"
            emoji=":warning:"
            ;;
        error)
            color="danger"
            emoji=":x:"
            ;;
        *)
            color="#0000FF"
            emoji=":information_source:"
            ;;
    esac

    local hostname=$(hostname)
    local username=$(whoami)
    local timestamp=$(date -Iseconds)

    local payload=$(cat <<EOF
{
    "username": "CHOM Deployment Bot",
    "icon_emoji": ":rocket:",
    "attachments": [
        {
            "color": "$color",
            "title": "$emoji CHOM Deployment Notification",
            "text": "$message",
            "fields": [
                {
                    "title": "Environment",
                    "value": "${ENVIRONMENT:-production}",
                    "short": true
                },
                {
                    "title": "Server",
                    "value": "$hostname",
                    "short": true
                },
                {
                    "title": "User",
                    "value": "$username",
                    "short": true
                },
                {
                    "title": "Deployment ID",
                    "value": "${DEPLOYMENT_ID:-N/A}",
                    "short": true
                }
            ],
            "footer": "CHOM Deployment System",
            "ts": $(date +%s)
        }
    ]
}
EOF
)

    if curl -s -X POST -H 'Content-type: application/json' \
        --data "$payload" \
        "$webhook_url" > /dev/null 2>&1; then
        log_info "Slack notification sent successfully"
    else
        log_warning "Failed to send Slack notification"
    fi
}

# Send email notification
send_email_notification() {
    local subject="$1"
    local message="$2"
    local recipients="${EMAIL_RECIPIENTS:-}"

    if [[ -z "$recipients" ]]; then
        log_info "Email recipients not configured, skipping notification"
        return 0
    fi

    if ! command -v mail &> /dev/null; then
        log_warning "mail command not available, skipping email notification"
        return 0
    fi

    local hostname=$(hostname)
    local username=$(whoami)
    local timestamp=$(date -Iseconds)

    local email_body=$(cat <<EOF
CHOM Deployment Notification
============================

$message

Deployment Details:
-------------------
Environment: ${ENVIRONMENT:-production}
Server: $hostname
User: $username
Deployment ID: ${DEPLOYMENT_ID:-N/A}
Timestamp: $timestamp

Log File: ${LOG_FILE:-N/A}

---
This is an automated message from the CHOM Deployment System.
EOF
)

    if echo "$email_body" | mail -s "[$hostname] $subject" "$recipients" > /dev/null 2>&1; then
        log_info "Email notification sent to: $recipients"
    else
        log_warning "Failed to send email notification"
    fi
}

# Send deployment started notification
notify_deployment_started() {
    local environment="${1:-production}"
    local branch="${2:-main}"

    local message="Deployment started for CHOM application\nEnvironment: $environment\nBranch: $branch"

    send_slack_notification "$message" "info"
    send_email_notification "Deployment Started" "$message"
}

# Send deployment success notification
notify_deployment_success() {
    local environment="${1:-production}"
    local duration="${2:-N/A}"

    local message="Deployment completed successfully\nEnvironment: $environment\nDuration: $duration"

    send_slack_notification "$message" "success"
    send_email_notification "Deployment Success" "$message"
}

# Send deployment failure notification
notify_deployment_failure() {
    local environment="${1:-production}"
    local error="${2:-Unknown error}"

    local message="Deployment failed\nEnvironment: $environment\nError: $error"

    send_slack_notification "$message" "error"
    send_email_notification "Deployment Failed" "$message"
}

# Send rollback notification
notify_rollback() {
    local environment="${1:-production}"
    local reason="${2:-Deployment failure}"

    local message="Automatic rollback initiated\nEnvironment: $environment\nReason: $reason"

    send_slack_notification "$message" "warning"
    send_email_notification "Deployment Rollback" "$message"
}

# Send health check failure notification
notify_health_check_failure() {
    local environment="${1:-production}"
    local check="${2:-Unknown check}"

    local message="Health check failed\nEnvironment: $environment\nFailed Check: $check"

    send_slack_notification "$message" "error"
    send_email_notification "Health Check Failed" "$message"
}

# Export functions
export -f send_slack_notification
export -f send_email_notification
export -f notify_deployment_started
export -f notify_deployment_success
export -f notify_deployment_failure
export -f notify_rollback
export -f notify_health_check_failure
