ifndef MK_COMMON_ZENSICAL_INCLUDED
MK_COMMON_ZENSICAL_INCLUDED := 1

# Docs site built with Zensical (https://zensical.org). The Zensical counterpart of mkdocs.mk,
# with the same docs-* targets: include one or the other, not both.
#
# Both lock files are usually gitignored, so each has a real file rule: a fresh clone compiles
# the locks before anything syncs from them, and an existing lock is only recompiled (without
# --upgrade) when what it is compiled from is newer.
#
# The Zensical lock is resolved from the tools .in and the Zensical .in together, and the venv
# is synced to that one lock. Two separately compiled locks drift apart on the packages they
# share (zensical needs pygments>=2.20 while an older tools lock pins 2.19.2 through rich),
# and pip-sync refuses two pins for the same package. The tools lock is still compiled and
# installed first, because pip-tools has to be in the venv before the combined lock can be.

# Paths / files (override these in your repo if needed)
ZENSICAL_CONFIG ?= zensical.toml

ZENSICAL_IN   ?= zensical-requirements.in
ZENSICAL_LOCK ?= zensical-requirements.txt

DOCS_TOOLS_IN   ?= requirements/tools.in
DOCS_TOOLS_LOCK ?= requirements/tools.txt

# Must match site_dir in the Zensical config (Zensical's default is site)
DOCS_SITE_DIR ?= site

DOCS_PYTHON      ?= $(shell command -v python3 >/dev/null 2>&1 && echo python3 || echo python)
DOCS_PYTHON_VENV ?= venv

DOCS_VENV_BIN := $(DOCS_PYTHON_VENV)/bin
DOCS_VENV_PIP := $(DOCS_VENV_BIN)/pip
DOCS_VENV_PY  := $(DOCS_VENV_BIN)/python

DOCS_PIP_COMPILE       := $(DOCS_VENV_BIN)/pip-compile
DOCS_PIP_COMPILE_FLAGS := --generate-hashes --strip-extras

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

# pip-tools is needed to compile the tools lock, which pins pip-tools itself, so the first
# install is unpinned; docs-dev-sync then replaces it with the pinned version.
$(DOCS_PIP_COMPILE): | docs-venv
	$(DOCS_VENV_PIP) install pip-tools

# ---- Dev tools (pip-tools, pip-audit, etc.) ----------------------------------

$(DOCS_TOOLS_LOCK): $(DOCS_TOOLS_IN) | docs-venv $(DOCS_PIP_COMPILE)
	@echo "Compiling $(DOCS_TOOLS_IN) -> $(DOCS_TOOLS_LOCK) ..."
	$(DOCS_PIP_COMPILE) $(DOCS_PIP_COMPILE_FLAGS) -o $(DOCS_TOOLS_LOCK) $(DOCS_TOOLS_IN)

.PHONY: docs-dev-lock
docs-dev-lock: | docs-venv $(DOCS_PIP_COMPILE) ## Re-lock dev tools requirements (tools.in -> tools.txt)
	@echo "Compiling $(DOCS_TOOLS_IN) -> $(DOCS_TOOLS_LOCK) ..."
	$(DOCS_PIP_COMPILE) $(DOCS_PIP_COMPILE_FLAGS) -o $(DOCS_TOOLS_LOCK) $(DOCS_TOOLS_IN)

# The tools lock is installed only when it changes, tracked by a stamp in the venv. The
# combined Zensical lock that docs-deps-sync applies afterwards can pin shared packages
# differently, so installing the tools lock on every build would downgrade them (with a pip
# resolver error) only for pip-sync to upgrade them straight back.
DOCS_TOOLS_STAMP := $(DOCS_PYTHON_VENV)/.tools-synced

$(DOCS_TOOLS_STAMP): $(DOCS_TOOLS_LOCK) | docs-venv
	@echo "Installing dev tools from $(DOCS_TOOLS_LOCK) ..."
	$(DOCS_VENV_PIP) install --upgrade pip
	$(DOCS_VENV_PIP) install -r $(DOCS_TOOLS_LOCK)
	@touch $@

.PHONY: docs-dev-sync
docs-dev-sync: $(DOCS_TOOLS_STAMP) ## Install dev tools from tools.txt into the venv (when it changed)

.PHONY: docs-bootstrap
docs-bootstrap: docs-dev-sync ## One-shot docs tooling bootstrap
	@echo "Docs bootstrap complete."

# ---- Zensical dependencies ---------------------------------------------------

$(ZENSICAL_LOCK): $(DOCS_TOOLS_IN) $(ZENSICAL_IN) | docs-bootstrap
	@echo "Compiling $(DOCS_TOOLS_IN) + $(ZENSICAL_IN) -> $(ZENSICAL_LOCK) ..."
	$(DOCS_PIP_COMPILE) $(DOCS_PIP_COMPILE_FLAGS) -o $(ZENSICAL_LOCK) $(DOCS_TOOLS_IN) $(ZENSICAL_IN)

.PHONY: docs-deps-lock
docs-deps-lock: docs-bootstrap ## Re-lock Zensical deps (no version upgrades)
	@echo "Compiling $(DOCS_TOOLS_IN) + $(ZENSICAL_IN) -> $(ZENSICAL_LOCK) ..."
	$(DOCS_PIP_COMPILE) $(DOCS_PIP_COMPILE_FLAGS) -o $(ZENSICAL_LOCK) $(DOCS_TOOLS_IN) $(ZENSICAL_IN)

.PHONY: docs-deps-upgrade
docs-deps-upgrade: docs-bootstrap ## Upgrade Zensical + dev tools deps to latest and lock
	@echo "Upgrading and compiling $(DOCS_TOOLS_IN) + $(ZENSICAL_IN) -> $(ZENSICAL_LOCK) ..."
	$(DOCS_PIP_COMPILE) --upgrade $(DOCS_PIP_COMPILE_FLAGS) -o $(ZENSICAL_LOCK) $(DOCS_TOOLS_IN) $(ZENSICAL_IN)

.PHONY: docs-deps-check-upgrade
docs-deps-check-upgrade: docs-bootstrap $(ZENSICAL_LOCK) ## Show diff of would-be Zensical upgrades
	@tmp=$$(mktemp); \
	echo "Checking for available updates (dry-run) ..."; \
	$(DOCS_PIP_COMPILE) --upgrade $(DOCS_PIP_COMPILE_FLAGS) -o $$tmp $(DOCS_TOOLS_IN) $(ZENSICAL_IN) >/dev/null 2>&1 || true; \
	if ! diff -u $(ZENSICAL_LOCK) $$tmp >/dev/null 2>&1; then \
	  echo "Updates available for $(ZENSICAL_LOCK):"; \
	  diff -u $(ZENSICAL_LOCK) $$tmp || true; \
	  echo; echo "Run: make docs-deps-upgrade && make docs-deps-sync"; \
	else \
	  echo "Zensical requirements are up-to-date."; \
	fi; \
	rm -f $$tmp

# ---- Sync + build / serve / audit / clean -----------------------------------

.PHONY: docs-deps-sync
docs-deps-sync: docs-bootstrap $(ZENSICAL_LOCK) ## Sync venv to the Zensical + dev tools lock
	@echo "Syncing venv to $(ZENSICAL_LOCK) ..."
	$(DOCS_VENV_BIN)/pip-sync $(ZENSICAL_LOCK)

.PHONY: docs-build
docs-build: docs-deps-sync ## Build the docs site (strict)
	@echo "Building docs site..."
	$(DOCS_VENV_BIN)/zensical build -f $(ZENSICAL_CONFIG) --strict --clean

.PHONY: docs-serve
docs-serve: docs-deps-sync ## Serve the docs site with live reload
	$(DOCS_VENV_BIN)/zensical serve -f $(ZENSICAL_CONFIG)

.PHONY: docs-audit
docs-audit: docs-deps-sync ## Audit docs dependencies for known vulnerabilities
	$(DOCS_VENV_BIN)/pip-audit -r $(ZENSICAL_LOCK) || true

.PHONY: docs-clean
docs-clean: ## Clean docs build artifacts
	rm -rf $(DOCS_SITE_DIR) .cache
	@echo "To remove the venv as well: rm -rf $(DOCS_PYTHON_VENV)"

# ---- Convenience OS deps ----------------------------------------------------

.PHONY: docs-install-system-deps-ubuntu
docs-install-system-deps-ubuntu: ## Install Ubuntu system packages for the docs
	sudo apt-get update
	sudo apt-get install -y python3-venv python3-pip python3-full

.PHONY: docs-install-system-deps-macos
docs-install-system-deps-macos: ## Install macOS system packages for the docs
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew not found: https://brew.sh"; exit 1; }
	brew install python || true

endif  # MK_COMMON_ZENSICAL_INCLUDED
