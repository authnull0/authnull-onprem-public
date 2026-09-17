# =============================================================================
# authnull-service — Developer Makefile
# =============================================================================

.PHONY: dev prod build test logs stop clean vendor help

# --------------------------------------------------------------------------
# Dev — reads .env, builds from source
# --------------------------------------------------------------------------
dev:
	docker compose up --build redis authnz authnull-service

dev-full:
	docker compose --profile ssi --profile authn up --build

dev-down:
	docker compose down

# --------------------------------------------------------------------------
# Prod — reads .env.prod, same compose file
# --------------------------------------------------------------------------
prod:
	docker compose --env-file .env.prod up -d

prod-down:
	docker compose --env-file .env.prod down

# --------------------------------------------------------------------------
# Individual service rebuilds
# --------------------------------------------------------------------------
rebuild-backend:
	docker compose up --build authnull-service

rebuild-authnz:
	docker compose up --build authnz

rebuild-ssi:
	docker compose --profile ssi up --build ssi-service

rebuild-authn:
	docker compose --profile authn up --build authn-service

# --------------------------------------------------------------------------
# Logs
# --------------------------------------------------------------------------
logs:
	docker compose logs -f authnull-service

logs-all:
	docker compose logs -f

# --------------------------------------------------------------------------
# Test
# --------------------------------------------------------------------------
test:
	bash test_backend.sh

# --------------------------------------------------------------------------
# Vendor — run after adding/changing dependencies
# --------------------------------------------------------------------------
vendor:
	GOPRIVATE="github.com/authnull0/*" GONOSUMDB="github.com/authnull0/*" go mod vendor

# --------------------------------------------------------------------------
# Stop all containers
# --------------------------------------------------------------------------
stop:
	docker compose stop

# --------------------------------------------------------------------------
# Remove containers + volumes (WARNING: deletes DB data)
# --------------------------------------------------------------------------
clean:
	docker compose down -v --remove-orphans

# --------------------------------------------------------------------------
# Help
# --------------------------------------------------------------------------
help:
	@echo ""
	@echo "  make dev            Start backend in dev mode (host postgres)"
	@echo "  make dev-full       Start all services in dev mode"
	@echo "  make dev-down       Stop dev stack"
	@echo "  make prod           Start full prod stack (containerized postgres)"
	@echo "  make prod-down      Stop prod stack"
	@echo "  make rebuild-backend Rebuild only authnull-service"
	@echo "  make logs           Tail authnull-service logs"
	@echo "  make logs-all       Tail all service logs"
	@echo "  make test           Run backend test suite"
	@echo "  make vendor         Re-vendor dependencies"
	@echo "  make stop           Stop all containers"
	@echo "  make clean          Remove containers + volumes"
	@echo ""
