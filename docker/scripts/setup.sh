#!/bin/bash
# ============================================================================
# CHOM Docker Test Environment - Setup Script
# ============================================================================
# Automated setup and validation of the Docker test environment
# ============================================================================

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOCKER_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "\n${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_info() {
    echo -e "${BLUE}i${NC} $1"
}

check_command() {
    if command -v $1 &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

# ============================================================================
# Main Setup
# ============================================================================

print_header "CHOM Docker Test Environment - Setup"

# Check prerequisites
print_info "Checking prerequisites..."

PREREQ_OK=true

if ! check_command docker; then
    PREREQ_OK=false
    print_error "Please install Docker: https://docs.docker.com/get-docker/"
fi

if ! check_command docker-compose; then
    print_warning "docker-compose command not found, checking for 'docker compose'..."
    if docker compose version &> /dev/null; then
        print_success "Docker Compose (plugin) is installed"
    else
        PREREQ_OK=false
        print_error "Please install Docker Compose: https://docs.docker.com/compose/install/"
    fi
fi

if ! check_command make; then
    print_warning "make is not installed (optional, but recommended)"
fi

if [ "$PREREQ_OK" = false ]; then
    print_error "Prerequisites not met. Please install missing tools."
    exit 1
fi

# Check Docker daemon
print_info "Checking Docker daemon..."
if docker info &> /dev/null; then
    print_success "Docker daemon is running"
else
    print_error "Docker daemon is not running. Please start Docker."
    exit 1
fi

# Check available resources
print_info "Checking system resources..."

# Get available memory (in MB)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $7}')
elif [[ "$OSTYPE" == "darwin"* ]]; then
    AVAILABLE_MEM=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
else
    AVAILABLE_MEM=8192  # Assume sufficient memory
fi

if [ $AVAILABLE_MEM -lt 4096 ]; then
    print_warning "Available memory is less than 4GB. Performance may be degraded."
else
    print_success "Sufficient memory available (${AVAILABLE_MEM}MB)"
fi

# Check disk space
AVAILABLE_DISK=$(df -BG "$DOCKER_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ $AVAILABLE_DISK -lt 10 ]; then
    print_warning "Available disk space is less than 10GB. You may run out of space."
else
    print_success "Sufficient disk space available (${AVAILABLE_DISK}GB)"
fi

# Create .env file if it doesn't exist
print_info "Checking environment configuration..."
cd "$DOCKER_DIR"

if [ -f .env ]; then
    print_success ".env file exists"
else
    print_info "Creating .env file from .env.example..."
    cp .env.example .env
    print_success ".env file created"
    print_warning "Please review and edit .env file with your settings"
fi

# Check if CHOM application exists
print_info "Checking for CHOM application..."
CHOM_PATH="$(dirname "$DOCKER_DIR")/chom"

if [ -d "$CHOM_PATH" ] && [ -f "$CHOM_PATH/artisan" ]; then
    print_success "CHOM application found at $CHOM_PATH"
else
    print_error "CHOM application not found at $CHOM_PATH"
    print_warning "Please ensure your CHOM Laravel application is in the correct location"
    print_info "Expected location: $CHOM_PATH"
fi

# Create required directories
print_info "Creating required directories..."
mkdir -p observability/prometheus/rules
mkdir -p observability/grafana/dashboards/json
print_success "Directories created"

# Build Docker images
print_header "Building Docker Images"
print_info "This may take 10-15 minutes on first run..."

if docker compose build; then
    print_success "Docker images built successfully"
else
    print_error "Failed to build Docker images"
    exit 1
fi

# Start services
print_header "Starting Services"
print_info "Starting all services in detached mode..."

if docker compose up -d; then
    print_success "Services started successfully"
else
    print_error "Failed to start services"
    exit 1
fi

# Wait for services to be healthy
print_info "Waiting for services to be healthy (this may take 2-3 minutes)..."
sleep 30

# Health checks
print_header "Health Checks"

HEALTH_OK=true

# Check web application
print_info "Checking web application..."
if curl -f http://localhost:8000/health &> /dev/null; then
    print_success "Web application is healthy"
else
    print_error "Web application is not responding"
    HEALTH_OK=false
fi

# Check Prometheus
print_info "Checking Prometheus..."
if curl -f http://localhost:9090/-/healthy &> /dev/null; then
    print_success "Prometheus is healthy"
else
    print_error "Prometheus is not responding"
    HEALTH_OK=false
fi

# Check Loki
print_info "Checking Loki..."
if curl -f http://localhost:3100/ready &> /dev/null; then
    print_success "Loki is healthy"
else
    print_error "Loki is not responding"
    HEALTH_OK=false
fi

# Check Grafana
print_info "Checking Grafana..."
if curl -f http://localhost:3000/api/health &> /dev/null; then
    print_success "Grafana is healthy"
else
    print_error "Grafana is not responding"
    HEALTH_OK=false
fi

# Summary
print_header "Setup Complete"

if [ "$HEALTH_OK" = true ]; then
    print_success "All services are healthy and running!"
else
    print_warning "Some services are not healthy. Check logs with: docker compose logs"
fi

# Print access URLs
echo -e "\n${GREEN}Access URLs:${NC}"
echo -e "  ${BLUE}Application:${NC}    http://localhost:8000"
echo -e "  ${BLUE}Grafana:${NC}        http://localhost:3000 (admin/admin)"
echo -e "  ${BLUE}Prometheus:${NC}     http://localhost:9090"
echo -e "  ${BLUE}Alertmanager:${NC}   http://localhost:9093"
echo -e "  ${BLUE}Loki:${NC}           http://localhost:3100"

echo -e "\n${GREEN}Useful Commands:${NC}"
echo -e "  ${YELLOW}make logs${NC}       - View all logs"
echo -e "  ${YELLOW}make ps${NC}         - View service status"
echo -e "  ${YELLOW}make health${NC}     - Check service health"
echo -e "  ${YELLOW}make down${NC}       - Stop all services"
echo -e "  ${YELLOW}make help${NC}       - Show all available commands"

echo -e "\n${GREEN}Documentation:${NC}"
echo -e "  Read ${BLUE}README.md${NC} for detailed documentation\n"

exit 0
