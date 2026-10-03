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
    * `MK_LOCAL_FILES` → your repository's own `.mk/<fragment>.mk` files, which are never fetched
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

MK_COMMON_REPO    ?= leinardi/make-common
MK_COMMON_VERSION ?= v1

MK_COMMON_DIR := $(REPO_ROOT)/.mk

# Shared snippets coming from make-common
MK_COMMON_FILES := help.mk pre-commit.mk

# Repo-local snippets that are NOT in make-common
MK_LOCAL_FILES :=

MK_COMMON_BOOTSTRAP_SCRIPT := $(REPO_ROOT)/scripts/bootstrap-mk-common.sh

# Bootstrap: the script will self-update and fetch the selected .mk snippets
MK_COMMON_BOOTSTRAP := $(shell "$(MK_COMMON_BOOTSTRAP_SCRIPT)" \
  "$(MK_COMMON_REPO)" \
  "$(MK_COMMON_VERSION)" \
  "$(MK_COMMON_DIR)" \
  "$(MK_COMMON_FILES)")

include $(addprefix $(MK_COMMON_DIR)/,$(MK_COMMON_FILES))
-include $(addprefix $(REPO_ROOT)/.mk/,$(MK_LOCAL_FILES))
```

`Makefile.sample` also carries the `mk-common-update` target and the "do not add recipes to this file" note: project targets go
in a local `.mk/<fragment>.mk` listed in `MK_LOCAL_FILES`, and generic ones are proposed upstream here.

Once added, `make` will **automatically fetch and update** both the bootstrap script
and the selected `.mk` files based on the version you specify.

---

## 🔄 Updating the shared snippets

To pull a newer version:

1. Update `MK_COMMON_VERSION` to the desired tag
2. Re-run any `make` target

The bootstrap logic will detect the version change and refresh the local `.mk` files. With a moving tag such as `v1`, run
`make mk-common-update`: it compares the commit the tag points at with the one recorded in `.mk/.mk-common-version` and
refreshes when they differ.

---

## 📁 Available modules (.mk files)

| File | Description |
| --- | --- |
| `ansible-vault.mk` | Ansible Vault helpers for encrypt/decrypt per environment + plaintext clean |
| `docker.mk` | `docker-build` / `docker-tag-latest`, per image for every entry in `DOCKER_TARGETS` |
| `go.mk` | Go build (per binary in `GO_BINARIES`), run, clean, tidy, fmt, fmt-check, vet, test (race) and coverage |
| `help.mk` | Default `help` target with auto-generated documentation from `##` comments |
| `mkdocs.mk` | MkDocs + Python tooling: venv, pip-tools, locked deps, build/serve/audit |
| `opentofu.mk` | Helpers for OpenTofu `init`, `plan`, `apply`, and local cleanup |
| `password.mk` | Secure PostgreSQL-compatible password generator |
| `pre-commit.mk` | `check` / `check-stage` around `pre-commit`; `pre-commit-install` installs every hook type listed in `default_install_hook_types` (e.g. `commit-msg` for the Conventional Commits check) |
| `zensical.mk` | Zensical counterpart of `mkdocs.mk` with the same `docs-*` targets (use one or the other): venv, pip-tools, a lock compiled with the tools so the two never conflict, strict build/serve/audit |

All modules include built-in guards to prevent accidental double inclusion. `make test` checks that every module parses, lists
its targets in `make help`, and survives being included twice, and tests the bootstrap script offline.

The bootstrap fetches the exact commit the tag resolves to and installs nothing unless every download succeeded, so a failed
refresh leaves `.mk/` as it was.

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

---

## 📄 License

MIT License. See [LICENSE](./LICENSE).
