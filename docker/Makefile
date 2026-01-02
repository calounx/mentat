# ============================================================================
# CHOM Docker Test Environment - Makefile
# ============================================================================
# Convenient shortcuts for common Docker operations
# ============================================================================

.PHONY: help up down restart logs ps stats clean build rebuild shell health test

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

## help: Show this help message
help:
	@echo "$(BLUE)CHOM Docker Test Environment$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  $(YELLOW)/' | sed 's/:/ - $(NC)/'
	@echo ""

## up: Start all services in detached mode
up:
	@echo "$(GREEN)Starting all services...$(NC)"
	docker-compose up -d
	@echo "$(GREEN)Services started. Use 'make logs' to view logs.$(NC)"
	@echo "$(BLUE)Access URLs:$(NC)"
	@echo "  Application:    http://localhost:8000"
	@echo "  Grafana:        http://localhost:3000 (admin/admin)"
	@echo "  Prometheus:     http://localhost:9090"

## down: Stop all services
down:
	@echo "$(YELLOW)Stopping all services...$(NC)"
	docker-compose down
	@echo "$(GREEN)Services stopped.$(NC)"

## restart: Restart all services
restart: down up

## restart-web: Restart web application service only
restart-web:
	@echo "$(YELLOW)Restarting web application...$(NC)"
	docker-compose restart web
	@echo "$(GREEN)Web application restarted.$(NC)"

## restart-obs: Restart observability stack only
restart-obs:
	@echo "$(YELLOW)Restarting observability stack...$(NC)"
	docker-compose restart observability
	@echo "$(GREEN)Observability stack restarted.$(NC)"

## logs: Tail logs from all services
logs:
	docker-compose logs -f

## logs-web: Tail logs from web application
logs-web:
	docker-compose logs -f web

## logs-obs: Tail logs from observability stack
logs-obs:
	docker-compose logs -f observability

## ps: Show status of all services
ps:
	docker-compose ps

## stats: Show resource usage statistics
stats:
	docker stats

## health: Check health status of all services
health:
	@echo "$(BLUE)Checking service health...$(NC)"
	@docker-compose ps
	@echo ""
	@echo "$(BLUE)Web Application Health:$(NC)"
	@curl -f http://localhost:8000/health 2>/dev/null && echo "$(GREEN)✓ Nginx$(NC)" || echo "$(RED)✗ Nginx$(NC)"
	@curl -f http://localhost:8000/fpm-ping 2>/dev/null && echo "$(GREEN)✓ PHP-FPM$(NC)" || echo "$(RED)✗ PHP-FPM$(NC)"
	@echo ""
	@echo "$(BLUE)Observability Stack Health:$(NC)"
	@curl -f http://localhost:9090/-/healthy 2>/dev/null && echo "$(GREEN)✓ Prometheus$(NC)" || echo "$(RED)✗ Prometheus$(NC)"
	@curl -f http://localhost:3100/ready 2>/dev/null && echo "$(GREEN)✓ Loki$(NC)" || echo "$(RED)✗ Loki$(NC)"
	@curl -f http://localhost:3000/api/health 2>/dev/null && echo "$(GREEN)✓ Grafana$(NC)" || echo "$(RED)✗ Grafana$(NC)"

## shell-web: Open shell in web application container
shell-web:
	docker-compose exec web bash

## shell-obs: Open shell in observability container
shell-obs:
	docker-compose exec observability bash

## build: Build all Docker images
build:
	@echo "$(YELLOW)Building Docker images...$(NC)"
	docker-compose build
	@echo "$(GREEN)Images built successfully.$(NC)"

## rebuild: Rebuild all images from scratch (no cache)
rebuild:
	@echo "$(YELLOW)Rebuilding Docker images from scratch...$(NC)"
	docker-compose build --no-cache
	@echo "$(GREEN)Images rebuilt successfully.$(NC)"

## clean: Stop and remove containers, networks, and volumes
clean:
	@echo "$(RED)WARNING: This will delete all data!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		docker-compose down -v; \
		echo "$(GREEN)Environment cleaned.$(NC)"; \
	else \
		echo "$(YELLOW)Operation cancelled.$(NC)"; \
	fi

## clean-all: Remove containers, networks, volumes, and images
clean-all:
	@echo "$(RED)WARNING: This will delete all data and images!$(NC)"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		docker-compose down -v --rmi all; \
		echo "$(GREEN)Environment completely cleaned.$(NC)"; \
	else \
		echo "$(YELLOW)Operation cancelled.$(NC)"; \
	fi

## test: Run Laravel tests in web container
test:
	@echo "$(BLUE)Running Laravel tests...$(NC)"
	docker-compose exec web php /var/www/chom/artisan test

## migrate: Run database migrations
migrate:
	@echo "$(BLUE)Running database migrations...$(NC)"
	docker-compose exec web php /var/www/chom/artisan migrate --force

## migrate-fresh: Reset database and run migrations
migrate-fresh:
	@echo "$(YELLOW)Resetting database...$(NC)"
	docker-compose exec web php /var/www/chom/artisan migrate:fresh --force --seed

## artisan: Run Laravel artisan command (usage: make artisan CMD="route:list")
artisan:
	docker-compose exec web php /var/www/chom/artisan $(CMD)

## mysql: Open MySQL console
mysql:
	docker-compose exec web mysql -u root -proot chom

## redis: Open Redis CLI
redis:
	docker-compose exec web redis-cli

## backup-db: Backup database to backup.sql
backup-db:
	@echo "$(BLUE)Backing up database...$(NC)"
	docker-compose exec web mysqldump -u root -proot chom > backup-$$(date +%Y%m%d-%H%M%S).sql
	@echo "$(GREEN)Database backed up.$(NC)"

## restore-db: Restore database from backup.sql (usage: make restore-db FILE=backup.sql)
restore-db:
	@echo "$(YELLOW)Restoring database from $(FILE)...$(NC)"
	@if [ -f "$(FILE)" ]; then \
		docker-compose exec -T web mysql -u root -proot chom < $(FILE); \
		echo "$(GREEN)Database restored.$(NC)"; \
	else \
		echo "$(RED)Error: File $(FILE) not found.$(NC)"; \
	fi

## update: Update all Docker images
update:
	@echo "$(BLUE)Pulling latest images...$(NC)"
	docker-compose pull
	@echo "$(GREEN)Images updated. Run 'make restart' to apply changes.$(NC)"

## prune: Clean up unused Docker resources
prune:
	@echo "$(YELLOW)Cleaning up unused Docker resources...$(NC)"
	docker system prune -f
	@echo "$(GREEN)Cleanup complete.$(NC)"

## env: Create .env file from .env.example
env:
	@if [ -f .env ]; then \
		echo "$(YELLOW).env file already exists. Skipping.$(NC)"; \
	else \
		cp .env.example .env; \
		echo "$(GREEN).env file created from .env.example$(NC)"; \
		echo "$(YELLOW)Please edit .env and configure your settings.$(NC)"; \
	fi
