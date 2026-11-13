# make-common

Shared Makefile snippets and reusable tasks, designed to provide a consistent developer experience
across multiple repositories. These snippets are versioned, self-bootstrapping, and safe to include
in public projects.

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
4. Run any `make` command. On the first run:

    * `scripts/bootstrap-mk-common.sh` will **update itself** to the pinned version
      (`MK_COMMON_REPO@MK_COMMON_VERSION`)
    * All required `.mk` files will be fetched into `.mk/`

After that, both the script and the `.mk` files will automatically refresh whenever you bump
`MK_COMMON_VERSION` in your Makefile.

Example minimal configuration (see [Makefile.sample](./Makefile.sample) for the full version):

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

`Makefile.sample` also carries the `mk-common-update` target and the "do not add recipes to this
file" note: project targets go in a local `.mk/<fragment>.mk` listed in `MK_LOCAL_FILES`, and
generic ones are proposed upstream here.

Once added, `make` will **automatically fetch and update** both the bootstrap script and the
selected `.mk` files based on the version you specify.

---

## 🔄 Updating the shared snippets

To pull a newer version:

1. Update `MK_COMMON_VERSION` to the desired tag
2. Re-run any `make` target

The bootstrap logic will detect the version change and refresh the local `.mk` files. With a moving
tag such as `v1`, run `make mk-common-update`: it compares the commit the tag points at with the one
recorded in `.mk/.mk-common-version` and refreshes when they differ.

---

## 📁 Available modules (.mk files)

| File | Description |
| --- | --- |
| `ansible-vault.mk` | Ansible Vault helpers for encrypt/decrypt per environment + plaintext clean; `ANSIBLE_VAULT` (default `ansible-vault`) sets the command, e.g. a pinned `uvx --from ansible-core==<version> ansible-vault` |
| `docker.mk` | `docker-build` / `docker-tag-latest`, per image for every entry in `DOCKER_TARGETS` |
| `go.mk` | Go build (per binary in `GO_BINARIES`), run, clean, tidy, fmt, fmt-check, vet, test (race) and coverage; `go-lint` runs golangci-lint through the consumer's own pre-commit hook (`GO_LINT_HOOK`, default `golangci-lint-full`), so the make target, the commit hook and CI use the same pinned version |
| `help.mk` | Default `help` target with auto-generated documentation from `##` comments |
| `image.mk` | Prebuilt images from the release assets, needs `docker.mk` and `rust-release.mk` listed before it: per `DOCKER_TARGETS` entry `image-build-prebuilt-<t>` (the Dockerfile's `prebuilt` stage with the `dist` build context, tagged `PREBUILT_IMAGE_<t>`), `image-test-<t>` (the consumer's `scripts/image-test.sh` with `--tier`, `--image`, `--platform`, `--binary` (the asset of `IMAGE_BIN_<t>`, default `<t>`) and `--expect-version`; `IMAGE_TEST_TIER=full` only on the host's platform, then `IMAGE_TEST_FULL_EXTRA`) and `image-build-test-<t>` (build, then test), with the aggregates `image-build-prebuilt`, `image-test` and `image-build-test` (images side by side under `make -j`, each tested after its own build, with the stamps computed once for both); one `IMAGE_PLATFORM` per run, the host's (`IMAGE_HOST_PLATFORM`) by default; `IMAGE_TEST_SCRIPT` names the test script; `IMAGE_TEST_FULL_EXTRA` (make arguments) may use `$(IMAGE_TEST_IMAGE)`, the image under test; a multi-image consumer sets `IMAGE_NAME_<t>` per target, as for `docker.mk` |
| `mkdocs.mk` | MkDocs + Python tooling: venv, pip-tools, locked deps, build/serve/audit |
| `opentofu.mk` | Helpers for OpenTofu `init`, `plan`, `apply`, and local cleanup |
| `parity.mk` | Demo parity harness around Playwright: compare a design-system prototype with the app's demo build, keep the known differences in a ratcheted `.parity-baseline` (`demo-parity`, `-full`, `-update`, `-accept REASON=`, `-report`, `-triage`, `-servers`), the two servers on `PARITY_DEMO_PORT` and `PARITY_PROTO_PORT` (5180, 5181) so projects can run side by side; needs `web.mk` listed before it |
| `password.mk` | Secure PostgreSQL-compatible password generator |
| `pre-commit.mk` | `check` / `check-stage` around `pre-commit`; `pre-commit-install` installs every hook type listed in `default_install_hook_types` (e.g. `commit-msg` for the Conventional Commits check) |
| `rust-release.mk` | Static musl release binaries with cargo-zigbuild and pinned zig, needs `rust.mk` listed before it: `rust-release-binaries` (every binary in `RUST_RELEASE_BINS`, default `BIN_NAME`, for every `RUST_RELEASE_PLATFORMS` entry, default `linux/amd64 linux/arm64`, into `RUST_RELEASE_DIR`, default `$(REPO_ROOT)/$(DIST_DIR)`, as `<bin>-<os>-<arch>`, copied from cargo's effective target directory, `RUST_RELEASE_TARGET_DIR`, which `cargo metadata` gives by default (with `RUST_RELEASE_BUILD_DIR`) so `CARGO_TARGET_DIR`, `build.target-dir` and `build.build-dir` count, after `RUST_RELEASE_PREREQS`), `rust-release-checksums` (`checksums.txt` over every binary on `RUST_RELEASE_SHIPPED_PLATFORMS`), `rust-release-dist` (both, ordered under `make -j`), `rust-zigbuild-check` and `rust-zigbuild-install` (the pinned zig and cargo-zigbuild, sha256-checked, into `RUST_RELEASE_TOOLS_DIR`); paths remapped so a rebuild gives the same bytes (a target or build directory other than the checkout's `target/` as `/src/target`); the zig, cargo-zigbuild and rust-std pins are `?=` variables |
| `rust.mk` | Cargo workspace, `--locked` throughout: `rust-build` (every target, `RUST_FEATURES`, default `--all-features`), `rust-dist` (the release `BIN_NAME` into `DIST_DIR`, copied from cargo's effective target directory, `RUST_TARGET_DIR`, which `cargo metadata` gives by default, so `CARGO_TARGET_DIR` and `build.target-dir` count), `rust-run` (`RUST_RUN_BIN`, `ARGS`), `rust-test`, `rust-clippy` (warnings as errors), `rust-fmt`, `rust-fmt-check`, `rust-doc` (warnings as errors), `rust-deny` (cargo-deny, `RUST_DENY_ARGS`, default `--workspace`), `rust-clean-stale` (cargo-sweep: artifacts unused for `RUST_SWEEP_DAYS`, default 7, or from removed toolchains) and `verify-rust`; `RUST_STAMP_PREFIX` sets the `<prefix>_VERSION`, `_COMMIT` and `_DATE` compile-time stamps. Opt-ins for a build cache that survives repeated builds: `RUST_BUILD_ENV :=` builds `rust-build` unstamped, sharing its units with the tests; `BUILD_DATE ?= $(or $(GIT_COMMIT_DATE),…)` stamps the commit date rather than the clock; `RUST_DIST_PROFILE` builds `rust-dist` in another Cargo profile (default `release`) |
| `web.mk` | npm web app in `WEB_DIR` (default `web/`): `web-install` (`npm ci`), `web-dev`, `web-demo`, `web-build`, `web-build-demo`, `web-test`, `web-lint`, `web-update`, `api-types`, and `build` (the app, then `WEB_BUILD_NEXT`, which embeds it: `go-build` by default when `go.mk` is listed, `rust-dist` when `rust.mk` is, otherwise required); every target installs only when `package.json`, `package-lock.json` or `.npmrc` changed; opt-in `WEB_DIST_SYNC_DIR` builds into `WEB_DIST_STAGING` and copies only changed files there (rsync), so an mtime-keyed embed does not rebuild for an unchanged app |
| `zensical.mk` | Zensical counterpart of `mkdocs.mk` with the same `docs-*` targets (use one or the other): venv, pip-tools, a lock compiled with the tools so the two never conflict, strict build/serve/audit |

All modules include built-in guards to prevent accidental double inclusion. `make test` checks that
every module parses, lists its targets in `make help`, and survives being included twice, dry-runs
the recipes pinned in `scripts/test-mk.sh`, holds the whole `make -n` output of the `rust.mk` and
`web.mk` defaults to `scripts/testdata/mk-defaults.golden`, and tests the bootstrap script offline.

Every snippet and the bootstrap script carry the MIT header, so a consumer's copy says where it came
from; `Makefile.sample` does not, because it becomes the consumer's own `Makefile`.

The bootstrap fetches the exact commit the tag resolves to and installs nothing unless every
download succeeded, so a failed refresh leaves `.mk/` as it was.

---

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).

---

## 📄 License

MIT License. See [LICENSE](./LICENSE).
