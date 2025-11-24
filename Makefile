.PHONY: help serve serve-drafts serve-debug build clean new docker-build docker-up lint update-theme

HUGO_ROOT := docs
HUGO_CMD := hugo

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

serve: ## Run Hugo server
	cd $(HUGO_ROOT) && $(HUGO_CMD) server

serve-drafts: ## Run Hugo server with drafts enabled
	cd $(HUGO_ROOT) && $(HUGO_CMD) server -D

serve-debug: ## Run Hugo server in debug mode
	cd $(HUGO_ROOT) && $(HUGO_CMD) server --debug

build: ## Build the site (minified)
	cd $(HUGO_ROOT) && $(HUGO_CMD) --minify

clean: ## Clean the public directory
	rm -rf $(HUGO_ROOT)/public

lint: ## Run pre-commit hooks
	pre-commit run --all-files

update-theme: ## Update the Hugo theme submodule
	git submodule update --remote --merge

new: ## Create a new content file (usage: make new path=devsecops/my-post.md)
ifdef path
	cd $(HUGO_ROOT) && $(HUGO_CMD) new content/$(path)
else
	@echo "Error: path is undefined. Usage: make new path=devsecops/my-post.md"
endif

docker-build: ## Build the Docker image
	docker build -t ghcr.io/irishlab-io/blog:latest -f docker/Dockerfile .

docker-up: ## Run with Docker Compose
	docker compose -f docker/compose.yml up -d
