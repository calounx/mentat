#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Mentat Deployment Wizard
# ==============================================================================
# Interactive script to help users choose the right deployment path
# ==============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}▸${NC} $1"
}

print_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

ask_question() {
    local question="$1"
    local default="${2:-}"
    local answer

    if [[ -n "$default" ]]; then
        echo -e "${BOLD}${question}${NC} ${CYAN}[${default}]${NC}"
    else
        echo -e "${BOLD}${question}${NC}"
    fi

    read -r answer
    echo "${answer:-$default}"
}

show_menu() {
    local title="$1"
    shift
    local options=("$@")
    local choice

    echo -e "${BOLD}${title}${NC}"
    echo ""

    for i in "${!options[@]}"; do
        echo -e "  ${GREEN}$((i + 1))${NC}. ${options[$i]}"
    done

    echo ""
    read -rp "Enter your choice (1-${#options[@]}): " choice

    # Validate choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
        return "$((choice - 1))"
    else
        print_error "Invalid choice. Please try again."
        return 255
    fi
}

# ==============================================================================
# Main Wizard
# ==============================================================================

main() {
    clear
    print_header "Mentat Deployment Wizard"

    echo -e "${CYAN}This wizard will help you choose the right deployment approach.${NC}"
    echo ""

    # Question 1: What do you want to do?
    print_step "What do you want to accomplish?"
    echo ""

    local purpose_options=(
        "Monitor existing servers (metrics, logs, alerts)"
        "Build a hosting platform to manage customer sites"
        "Develop/test locally on my machine"
        "Deploy a Laravel app with monitoring (VPSManager)"
    )

    show_menu "Choose your goal:" "${purpose_options[@]}"
    local purpose=$?

    echo ""

    case $purpose in
        0) # Monitor existing servers
            print_header "Recommendation: Observability Stack"
            echo -e "${GREEN}You should deploy the Observability Stack.${NC}"
            echo ""
            print_info "What you'll get:"
            echo "  • Prometheus for metrics collection"
            echo "  • Loki for log aggregation"
            echo "  • Grafana for visualization"
            echo "  • Alertmanager for notifications"
            echo ""
            print_step "Deployment path:"
            echo ""
            echo "1. On your monitoring VPS (fresh Debian 13 recommended):"
            echo -e "   ${CYAN}curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash${NC}"
            echo ""
            echo "2. Select: ${BOLD}Observability VPS${NC}"
            echo ""
            echo "3. On servers you want to monitor:"
            echo -e "   ${CYAN}curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash${NC}"
            echo ""
            echo "4. Select: ${BOLD}Monitored Host${NC}"
            echo ""
            print_info "Location: ${BOLD}observability-stack/deploy/bootstrap.sh${NC}"
            ;;

        1) # Build hosting platform
            print_header "Recommendation: CHOM + Observability Stack"
            echo -e "${GREEN}You need both components:${NC}"
            echo ""
            print_step "Step 1: Deploy Observability Stack (Monitoring Infrastructure)"
            echo ""
            echo "On your monitoring VPS:"
            echo -e "   ${CYAN}curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash${NC}"
            echo "   Select: ${BOLD}Observability VPS${NC}"
            echo ""
            print_step "Step 2: Deploy CHOM (Control Plane)"
            echo ""
            echo "On your CHOM VPS:"
            echo -e "   ${CYAN}cd chom/deploy/${NC}"
            echo -e "   ${CYAN}./deploy.sh${NC}"
            echo ""
            echo "Configure CHOM to connect to your Observability Stack:"
            echo "   • Set CHOM_PROMETHEUS_URL=http://your-obs-vps:9090"
            echo "   • Set CHOM_LOKI_URL=http://your-obs-vps:3100"
            echo "   • Set CHOM_GRAFANA_URL=http://your-obs-vps:3000"
            echo ""
            print_info "CHOM will manage sites, backups, and billing"
            print_info "Observability Stack will handle monitoring and alerts"
            ;;

        2) # Local development
            print_header "Recommendation: CHOM Development Mode"
            echo -e "${GREEN}You should run CHOM in development mode.${NC}"
            echo ""
            print_step "Quick start:"
            echo ""
            echo "1. Clone the repository:"
            echo -e "   ${CYAN}git clone https://github.com/calounx/mentat.git${NC}"
            echo -e "   ${CYAN}cd mentat/chom${NC}"
            echo ""
            echo "2. Install dependencies:"
            echo -e "   ${CYAN}composer install${NC}"
            echo -e "   ${CYAN}npm install${NC}"
            echo ""
            echo "3. Configure environment:"
            echo -e "   ${CYAN}cp .env.example .env${NC}"
            echo -e "   ${CYAN}php artisan key:generate${NC}"
            echo ""
            echo "4. Setup database:"
            echo -e "   ${CYAN}php artisan migrate${NC}"
            echo ""
            echo "5. Build frontend:"
            echo -e "   ${CYAN}npm run build${NC}"
            echo ""
            echo "6. Start server:"
            echo -e "   ${CYAN}php artisan serve${NC}"
            echo ""
            echo "7. In another terminal, watch assets:"
            echo -e "   ${CYAN}npm run dev${NC}"
            echo ""
            print_info "Access: http://localhost:8000"
            ;;

        3) # VPSManager
            print_header "Recommendation: VPSManager Role"
            echo -e "${GREEN}You should use the VPSManager deployment role.${NC}"
            echo ""
            print_info "This includes:"
            echo "  • Full LEMP stack (Linux, Nginx, MySQL, PHP)"
            echo "  • Laravel application ready"
            echo "  • Monitoring exporters (node, nginx, mysql, php-fpm)"
            echo "  • Integrated with Observability Stack"
            echo ""
            print_step "Deployment path:"
            echo ""
            echo "1. On your VPS (fresh Debian 13 recommended):"
            echo -e "   ${CYAN}curl -sSL https://raw.githubusercontent.com/calounx/mentat/master/observability-stack/deploy/bootstrap.sh | sudo bash${NC}"
            echo ""
            echo "2. Select: ${BOLD}VPSManager${NC}"
            echo ""
            echo "3. The installer will:"
            echo "   • Install full LEMP stack"
            echo "   • Setup monitoring exporters"
            echo "   • Configure Laravel environment"
            echo "   • Setup SSL with Let's Encrypt"
            echo ""
            print_info "Perfect for deploying a Laravel app with built-in monitoring"
            ;;

        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac

    echo ""
    print_header "Next Steps"

    # Ask if they want to proceed
    echo ""
    local proceed
    proceed=$(ask_question "Do you want to proceed with this deployment? (yes/no)" "no")

    if [[ "${proceed,,}" == "yes" || "${proceed,,}" == "y" ]]; then
        echo ""
        print_success "Great! Follow the instructions above."
        echo ""

        case $purpose in
            0|1|3)
                print_warning "Make sure you have:"
                echo "  • A fresh VPS running Debian 13 or Ubuntu 22.04+"
                echo "  • Root or sudo access"
                echo "  • At least 2GB RAM and 20GB disk space"
                ;;
            2)
                print_warning "Make sure you have:"
                echo "  • PHP 8.2+ installed"
                echo "  • Composer installed"
                echo "  • Node.js 18+ and npm installed"
                ;;
        esac

        echo ""
        print_info "Documentation: ${BOLD}${SCRIPT_DIR}/README.md${NC}"
        print_info "Questions? Open an issue: https://github.com/calounx/mentat/issues"
    else
        echo ""
        print_info "No problem! Run this script again anytime:"
        echo -e "   ${CYAN}./deployment-wizard.sh${NC}"
    fi

    echo ""
}

# ==============================================================================
# Run
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
