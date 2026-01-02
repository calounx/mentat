#!/bin/bash

# ============================================================================
# CHOM Email Service Setup Script
# ============================================================================
# This script helps configure email services for CHOM.
# Supports: SendGrid, Mailgun, AWS SES, SMTP, and development options
#
# Usage:
#   ./scripts/setup-email.sh
#   ./scripts/setup-email.sh --service sendgrid
#   ./scripts/setup-email.sh --service mailgun
#   ./scripts/setup-email.sh --service development
# ============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
ENV_EXAMPLE="$PROJECT_ROOT/.env.example"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# ============================================================================
# SETUP FUNCTIONS
# ============================================================================

setup_sendgrid() {
    print_header "SendGrid Configuration"

    echo "SendGrid Configuration:"
    echo "1. Sign up at https://sendgrid.com"
    echo "2. Create API key in Settings > API Keys"
    echo "3. Copy your API key below"
    echo ""

    read -p "Enter your SendGrid API key (or press Enter to skip): " sendgrid_key

    if [ -z "$sendgrid_key" ]; then
        print_warning "SendGrid API key not provided, skipping..."
        return
    fi

    # Update .env
    if grep -q "^MAIL_MAILER=" "$ENV_FILE"; then
        sed -i "s/^MAIL_MAILER=.*/MAIL_MAILER=sendgrid/" "$ENV_FILE"
    else
        echo "MAIL_MAILER=sendgrid" >> "$ENV_FILE"
    fi

    if grep -q "^SENDGRID_API_KEY=" "$ENV_FILE"; then
        sed -i "s/^SENDGRID_API_KEY=.*/SENDGRID_API_KEY=$sendgrid_key/" "$ENV_FILE"
    else
        echo "SENDGRID_API_KEY=$sendgrid_key" >> "$ENV_FILE"
    fi

    print_success "SendGrid configuration added to .env"
    print_info "Test with: php artisan tinker"
    print_info "Then: Mail::to('test@example.com')->send(new \\App\\Mail\\TeamInvitationMail(...))"
}

setup_mailgun() {
    print_header "Mailgun Configuration"

    echo "Mailgun Configuration:"
    echo "1. Sign up at https://mailgun.com"
    echo "2. Get credentials from API Keys"
    echo "3. Note your domain (e.g., sandbox12345.mailgun.org)"
    echo ""

    read -p "Enter your Mailgun Domain: " mailgun_domain
    read -p "Enter your Mailgun API Key: " mailgun_key
    read -p "Enter Mailgun Endpoint (api.mailgun.net or api.eu.mailgun.net): " mailgun_endpoint

    if [ -z "$mailgun_domain" ] || [ -z "$mailgun_key" ]; then
        print_warning "Mailgun credentials not provided, skipping..."
        return
    fi

    # Update .env
    if grep -q "^MAIL_MAILER=" "$ENV_FILE"; then
        sed -i "s/^MAIL_MAILER=.*/MAIL_MAILER=mailgun/" "$ENV_FILE"
    else
        echo "MAIL_MAILER=mailgun" >> "$ENV_FILE"
    fi

    if grep -q "^MAILGUN_DOMAIN=" "$ENV_FILE"; then
        sed -i "s/^MAILGUN_DOMAIN=.*/MAILGUN_DOMAIN=$mailgun_domain/" "$ENV_FILE"
    else
        echo "MAILGUN_DOMAIN=$mailgun_domain" >> "$ENV_FILE"
    fi

    if grep -q "^MAILGUN_SECRET=" "$ENV_FILE"; then
        sed -i "s/^MAILGUN_SECRET=.*/MAILGUN_SECRET=$mailgun_key/" "$ENV_FILE"
    else
        echo "MAILGUN_SECRET=$mailgun_key" >> "$ENV_FILE"
    fi

    if grep -q "^MAILGUN_ENDPOINT=" "$ENV_FILE"; then
        sed -i "s|^MAILGUN_ENDPOINT=.*|MAILGUN_ENDPOINT=$mailgun_endpoint|" "$ENV_FILE"
    else
        echo "MAILGUN_ENDPOINT=${mailgun_endpoint:-api.mailgun.net}" >> "$ENV_FILE"
    fi

    print_success "Mailgun configuration added to .env"
}

setup_mailhog() {
    print_header "MailHog Setup (Development)"

    echo "MailHog is a local SMTP server for testing emails."
    echo ""

    # Check if Docker is available
    if command -v docker &> /dev/null; then
        read -p "Start MailHog via Docker? (y/n): " start_mailhog

        if [ "$start_mailhog" == "y" ]; then
            echo "Starting MailHog..."
            docker-compose up -d mailhog

            print_success "MailHog started"
            print_info "Access MailHog UI at: http://localhost:8025"
        fi
    else
        print_info "Docker not installed. Install MailHog manually:"
        print_info "  - Download: https://github.com/mailhog/MailHog/releases"
        print_info "  - macOS: brew install mailhog && mailhog"
        print_info "  - Then access: http://localhost:8025"
    fi

    # Update .env
    if grep -q "^MAIL_MAILER=" "$ENV_FILE"; then
        sed -i "s/^MAIL_MAILER=.*/MAIL_MAILER=smtp/" "$ENV_FILE"
    else
        echo "MAIL_MAILER=smtp" >> "$ENV_FILE"
    fi

    if grep -q "^MAIL_HOST=" "$ENV_FILE"; then
        sed -i "s/^MAIL_HOST=.*/MAIL_HOST=mailhog/" "$ENV_FILE"
    else
        echo "MAIL_HOST=mailhog" >> "$ENV_FILE"
    fi

    if grep -q "^MAIL_PORT=" "$ENV_FILE"; then
        sed -i "s/^MAIL_PORT=.*/MAIL_PORT=1025/" "$ENV_FILE"
    else
        echo "MAIL_PORT=1025" >> "$ENV_FILE"
    fi

    print_success "MailHog configuration added to .env"
}

setup_log() {
    print_header "Log Driver Setup (Development)"

    echo "Log driver logs emails to storage/logs/laravel.log"
    echo "Perfect for quick development and testing."
    echo ""

    # Update .env
    if grep -q "^MAIL_MAILER=" "$ENV_FILE"; then
        sed -i "s/^MAIL_MAILER=.*/MAIL_MAILER=log/" "$ENV_FILE"
    else
        echo "MAIL_MAILER=log" >> "$ENV_FILE"
    fi

    print_success "Log driver configured in .env"
    print_info "View emails in: tail -f storage/logs/laravel.log"
}

test_email_configuration() {
    print_header "Testing Email Configuration"

    if command -v php &> /dev/null; then
        echo "Testing mail configuration..."
        php "$PROJECT_ROOT/artisan" config:cache

        if php "$PROJECT_ROOT/artisan" tinker <<< "echo config('mail.default');" &> /dev/null; then
            print_success "Configuration test passed"
        else
            print_warning "Could not verify configuration"
        fi
    else
        print_warning "PHP not found, skipping configuration test"
    fi
}

show_menu() {
    print_header "CHOM Email Service Setup"

    echo "Select your email service:"
    echo ""
    echo "Production Services:"
    echo "  1) SendGrid (Recommended - 100/day free)"
    echo "  2) Mailgun (5,000/month free)"
    echo ""
    echo "Development Services:"
    echo "  3) MailHog (Local SMTP testing)"
    echo "  4) Log Driver (Log to file)"
    echo ""
    echo "Other:"
    echo "  5) Test Configuration"
    echo "  6) View Documentation"
    echo "  0) Exit"
    echo ""
}

view_documentation() {
    print_header "Email Configuration Documentation"

    if [ -f "$PROJECT_ROOT/docs/EMAIL_CONFIGURATION.md" ]; then
        less "$PROJECT_ROOT/docs/EMAIL_CONFIGURATION.md"
    else
        print_error "Documentation not found at $PROJECT_ROOT/docs/EMAIL_CONFIGURATION.md"
    fi
}

# ============================================================================
# MAIN LOOP
# ============================================================================

main() {
    # Check if .env exists
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found!"
        print_info "Creating .env from .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        print_success ".env created"
    fi

    # If argument provided, use it
    if [ $# -gt 0 ]; then
        case "$1" in
            --service)
                case "$2" in
                    sendgrid) setup_sendgrid ;;
                    mailgun) setup_mailgun ;;
                    mailhog) setup_mailhog ;;
                    log) setup_log ;;
                    development)
                        print_info "Setting up for development..."
                        setup_mailhog
                        ;;
                    *)
                        print_error "Unknown service: $2"
                        echo "Available: sendgrid, mailgun, mailhog, log"
                        exit 1
                        ;;
                esac
                test_email_configuration
                print_success "Setup complete!"
                exit 0
                ;;
            --help)
                echo "Usage: $0 [--service {sendgrid|mailgun|mailhog|log}]"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    fi

    # Interactive menu
    while true; do
        show_menu
        read -p "Select option (0-6): " choice

        case $choice in
            1) setup_sendgrid ;;
            2) setup_mailgun ;;
            3) setup_mailhog ;;
            4) setup_log ;;
            5) test_email_configuration ;;
            6) view_documentation ;;
            0)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
}

# ============================================================================
# EXECUTION
# ============================================================================

main "$@"
