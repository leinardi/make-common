ifndef MK_COMMON_MKDOCS_INCLUDED
MK_COMMON_MKDOCS_INCLUDED := 1

# Paths / files (override these in your repo if needed)
MKDOCS_CONFIG ?= mkdocs.yaml

MKDOCS_IN   ?= mkdocs-requirements.in
MKDOCS_LOCK ?= mkdocs-requirements.txt

DOCS_TOOLS_IN   ?= requirements/tools.in
DOCS_TOOLS_LOCK ?= requirements/tools.txt

DOCS_PYTHON      ?= $(shell command -v python3 >/dev/null 2>&1 && echo python3 || echo python)
DOCS_PYTHON_VENV ?= venv

DOCS_VENV_BIN := $(DOCS_PYTHON_VENV)/bin
DOCS_VENV_PIP := $(DOCS_VENV_BIN)/pip
DOCS_VENV_PY  := $(DOCS_VENV_BIN)/python

# ---- Python / venv bootstrap -------------------------------------------------

.PHONY: docs-check-python
docs-check-python: # Internal: ensure Python exists
	@if ! command -v $(DOCS_PYTHON) >/dev/null 2>&1; then \
	  echo "Error: Python 3 not found."; \
	  echo "Install it with:"; \
	  echo "  macOS:  brew install python"; \
	  echo "  Ubuntu: sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip"; \
	  exit 1; \
	fi

# Stamp file to avoid /bin/python confusion + PEP 668 issues
$(DOCS_PYTHON_VENV)/.ready: | docs-check-python
	@echo "Creating venv at $(DOCS_PYTHON_VENV) (if missing)..."
	$(DOCS_PYTHON) -m venv $(DOCS_PYTHON_VENV)
	$(DOCS_VENV_PY) -m pip install --upgrade pip
	@touch $@

.PHONY: docs-venv
docs-venv: $(DOCS_PYTHON_VENV)/.ready ## Ensure Python virtualenv for docs exists

# ---- Dev tools (pip-tools, pip-audit, etc.) ----------------------------------

.PHONY: docs-dev-lock
docs-dev-lock: docs-venv $(DOCS_TOOLS_IN) ## Lock dev tools requirements (tools.in -> tools.txt)
	@echo "Compiling $(DOCS_TOOLS_IN) -> $(DOCS_TOOLS_LOCK) ..."
	$(DOCS_VENV_PIP) install --upgrade pip-tools
	$(DOCS_VENV_BIN)/pip-compile --generate-hashes --strip-extras -o $(DOCS_TOOLS_LOCK) $(DOCS_TOOLS_IN)

.PHONY: docs-dev-sync
docs-dev-sync: docs-venv $(DOCS_TOOLS_LOCK) ## Install dev tools from tools.txt into the venv
	@echo "Installing dev tools from $(DOCS_TOOLS_LOCK) ..."
	$(DOCS_VENV_PIP) install --upgrade pip
	$(DOCS_VENV_PIP) install -r $(DOCS_TOOLS_LOCK)

.PHONY: docs-bootstrap
docs-bootstrap: docs-venv docs-dev-lock docs-dev-sync ## One-shot docs tooling bootstrap
	@echo "Docs bootstrap complete."

# ---- MkDocs dependencies -----------------------------------------------------

.PHONY: docs-deps-lock
docs-deps-lock: docs-bootstrap $(MKDOCS_IN) ## Lock MkDocs deps (no version upgrades)
	@echo "Compiling $(MKDOCS_IN) -> $(MKDOCS_LOCK) ..."
	$(DOCS_VENV_BIN)/pip-compile --generate-hashes --strip-extras -o $(MKDOCS_LOCK) $(MKDOCS_IN)

.PHONY: docs-deps-upgrade
docs-deps-upgrade: docs-bootstrap $(MKDOCS_IN) ## Upgrade MkDocs deps to latest and lock
	@echo "Upgrading and compiling $(MKDOCS_IN) -> $(MKDOCS_LOCK) ..."
	$(DOCS_VENV_BIN)/pip-compile --upgrade --generate-hashes --strip-extras -o $(MKDOCS_LOCK) $(MKDOCS_IN)

.PHONY: docs-deps-check-upgrade
docs-deps-check-upgrade: docs-bootstrap $(MKDOCS_IN) ## Show diff of would-be MkDocs upgrades
	@tmp=$$(mktemp); \
	echo "Checking for available updates (dry-run) ..."; \
	$(DOCS_VENV_BIN)/pip-compile --upgrade --generate-hashes --strip-extras -o $$tmp $(MKDOCS_IN) >/dev/null 2>&1 || true; \
	if ! diff -u $(MKDOCS_LOCK) $$tmp >/dev/null 2>&1; then \
	  echo "Updates available for $(MKDOCS_LOCK):"; \
	  diff -u $(MKDOCS_LOCK) $$tmp || true; \
	  echo; echo "Run: make docs-deps-upgrade && make docs-deps-sync"; \
	else \
	  echo "MkDocs requirements are up-to-date."; \
	fi; \
	rm -f $$tmp

# ---- Sync + build / serve / audit / clean -----------------------------------

.PHONY: docs-deps-sync
docs-deps-sync: docs-bootstrap $(MKDOCS_LOCK) ## Sync venv to dev + MkDocs lock files
	@echo "Syncing venv to $(DOCS_TOOLS_LOCK) + $(MKDOCS_LOCK) ..."
	$(DOCS_VENV_BIN)/pip-sync $(DOCS_TOOLS_LOCK) $(MKDOCS_LOCK)

.PHONY: docs-build
docs-build: docs-deps-sync ## Build MkDocs site
	@echo "Building MkDocs site..."
	$(DOCS_VENV_BIN)/mkdocs build -f $(MKDOCS_CONFIG) --strict

.PHONY: docs-serve
docs-serve: docs-deps-sync ## Serve MkDocs site with live reload
	$(DOCS_VENV_BIN)/mkdocs serve -f $(MKDOCS_CONFIG)

.PHONY: docs-audit
docs-audit: docs-deps-sync ## Audit docs dependencies for known vulnerabilities
	$(DOCS_VENV_BIN)/pip-audit -r $(MKDOCS_LOCK) || true

.PHONY: docs-clean
docs-clean: ## Clean MkDocs build artifacts
	rm -rf site
	@echo "To remove the venv as well: rm -rf $(DOCS_PYTHON_VENV)"

# ---- Convenience OS deps ----------------------------------------------------

.PHONY: docs-install-system-deps-ubuntu
docs-install-system-deps-ubuntu: ## Install Ubuntu system packages for MkDocs/docs
	sudo apt-get update
	sudo apt-get install -y python3-venv python3-pip python3-full build-essential
	@echo "If you use CairoSVG features, also: sudo apt-get install -y libcairo2 libpango-1.0-0 libgdk-pixbuf2.0-0"

.PHONY: docs-install-system-deps-macos
docs-install-system-deps-macos: ## Install macOS system packages for MkDocs/docs
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found: https://brew.sh"; exit 1; }
	brew install python cairo pango pkg-config gdk-pixbuf || true

endif  # MK_COMMON_MKDOCS_INCLUDED
