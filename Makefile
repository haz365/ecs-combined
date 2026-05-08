.PHONY: help up down build deploy-dev deploy-staging destroy-dev destroy-staging

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ── Local dev ─────────────────────────────────────────────────────────────────
up: ## Start local dev stack
	docker compose up --build -d

down: ## Stop local dev stack
	docker compose down -v

build: ## Build all service images locally
	docker compose build

logs: ## Tail all local logs
	docker compose logs -f

# ── Full environment deploy ───────────────────────────────────────────────────
deploy-dev: ## Full deploy to dev - terraform + images + services + DNS
	cd infra/environments/dev && terraform apply -var-file=terraform.tfvars -auto-approve
	./scripts/bootstrap.sh dev

deploy-staging: ## Full deploy to staging
	cd infra/environments/staging && terraform apply -var-file=terraform.tfvars -auto-approve
	./scripts/bootstrap.sh staging

# ── Teardown ──────────────────────────────────────────────────────────────────
destroy-dev: ## Tear down dev environment
	./scripts/teardown.sh dev

destroy-staging: ## Tear down staging environment
	./scripts/teardown.sh staging

destroy-prod: ## Tear down prod (double confirmation)
	@read -p "Type 'destroy-prod' to confirm: " c && [ "$$c" = "destroy-prod" ]
	./scripts/teardown.sh prod

# ── Terraform only ────────────────────────────────────────────────────────────
plan-dev: ## Terraform plan for dev
	cd infra/environments/dev && terraform init && terraform plan -var-file=terraform.tfvars

plan-staging: ## Terraform plan for staging
	cd infra/environments/staging && terraform init && terraform plan -var-file=terraform.tfvars

plan-prod: ## Terraform plan for prod
	cd infra/environments/prod && terraform init && terraform plan -var-file=terraform.tfvars

# ── Images ────────────────────────────────────────────────────────────────────
push-images: ## Build and push app images to ECR
	./scripts/push-images.sh

# ── Load test ─────────────────────────────────────────────────────────────────
load-test-local: ## k6 load test against local stack
	k6 run load-test/script.js -e BASE_URL=http://localhost:8080

load-test-staging: ## k6 load test against staging
	k6 run load-test/script.js -e BASE_URL=https://hasanali.uk
