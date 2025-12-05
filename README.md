# make-common

Shared Makefile snippets and reusable tasks, designed to provide a consistent developer experience across multiple repositories.
These snippets are versioned, self-bootstrapping, and safe to include in public projects.

---

## ✨ Features

* Modular `.mk` files you can mix and match
* Automatic bootstrap on first `make` run
* Version-pinned to avoid unexpected changes

---

## 🚀 Using make-common in your repository

1. Copy **`Makefile.sample`** into your project as `Makefile`.
2. Copy the initial version of **`scripts/bootstrap-mk-common.sh`** into your repository at
   `scripts/bootstrap-mk-common.sh` (make this file executable).
3. Adjust in your Makefile:

    * `MK_COMMON_VERSION` → which tag of `make-common` to use
    * `MK_COMMON_FILES` → which `.mk` snippets you want to include
4. Run any `make` command.
   On the first run:

    * `scripts/bootstrap-mk-common.sh` will **update itself** to the pinned version
      (`MK_COMMON_REPO@MK_COMMON_VERSION`)
    * All required `.mk` files will be fetched into `.mk/`

After that, both the script and the `.mk` files will automatically refresh whenever
you bump `MK_COMMON_VERSION` in your Makefile.

Example minimal configuration
(see [Makefile.sample](./Makefile.sample) for the full version):

```make
# Resolve repository root (Makefile can live anywhere)
REPO_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null || pwd)

MK_COMMON_REPO        ?= leinardi/make-common
MK_COMMON_VERSION     ?= v1

MK_COMMON_DIR         := $(REPO_ROOT)/.mk
MK_COMMON_FILES       := help.mk pre-commit.mk password.mk

MK_COMMON_BOOTSTRAP_SCRIPT := $(REPO_ROOT)/scripts/bootstrap-mk-common.sh

# Bootstrap: the script will self-update and fetch the selected .mk snippets
MK_COMMON_BOOTSTRAP := $(shell "$(MK_COMMON_BOOTSTRAP_SCRIPT)" \
  "$(MK_COMMON_REPO)" \
  "$(MK_COMMON_VERSION)" \
  "$(MK_COMMON_DIR)" \
  "$(MK_COMMON_FILES)")

# Include shared make logic
include $(addprefix $(MK_COMMON_DIR)/,$(MK_COMMON_FILES))

.PHONY: mk-common-update
mk-common-update: ## Check for remote updates of shared .mk files
 @echo "[mk] Checking for updates from $(MK_COMMON_REPO)@$(MK_COMMON_VERSION)"
 MK_COMMON_UPDATE=1 "$(MK_COMMON_BOOTSTRAP_SCRIPT)" \
   "$(MK_COMMON_REPO)" \
   "$(MK_COMMON_VERSION)" \
   "$(MK_COMMON_DIR)" \
   "$(MK_COMMON_FILES)"

```

Once added, `make` will **automatically fetch and update** both the bootstrap script
and the selected `.mk` files based on the version you specify.

---

## 🔄 Updating the shared snippets

To pull a newer version:

1. Update `MK_COMMON_VERSION` to the desired tag
2. Re-run any `make` target

The bootstrap logic will detect the version change and refresh the local `.mk` files.

---

## 📁 Available modules (.mk files)

| File               | Description                                                                 |
|--------------------|-----------------------------------------------------------------------------|
| `ansible-vault.mk` | Ansible Vault helpers for encrypt/decrypt per environment + plaintext clean |
| `help.mk`          | Default `help` target with auto-generated documentation from `##` comments  |
| `mkdocs.mk`        | MkDocs + Python tooling: venv, pip-tools, locked deps, build/serve/audit    |
| `opentofu.mk`      | Helpers for OpenTofu `init`, `plan`, `apply`, and local cleanup             |
| `password.mk`      | Secure PostgreSQL-compatible password generator                             |
| `pre-commit.mk`    | Common `check` / `check-stage` targets around `pre-commit`                  |

All modules include built-in guards to prevent accidental double inclusion.

---

## 📄 License

MIT License. See [LICENSE](./LICENSE).
