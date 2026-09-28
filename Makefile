# This repository is the source of the shared snippets, so it includes them
# straight from .mk/ instead of bootstrapping them like a consumer does.
REPO_ROOT := $(shell git rev-parse --show-toplevel)
include $(REPO_ROOT)/.mk/help.mk
include $(REPO_ROOT)/.mk/pre-commit.mk
include $(REPO_ROOT)/.mk/password.mk

.PHONY: test
test: ## Smoke-test every snippet, and test the bootstrap script offline
	@"$(REPO_ROOT)/scripts/test-mk.sh"
	@"$(REPO_ROOT)/scripts/test-bootstrap.sh"
