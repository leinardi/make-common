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
2. Adjust:

    * `MK_COMMON_VERSION` → which tag of this repo to use
    * `MK_COMMON_FILES` → which `.mk` snippets you want to include
3. Run any `make` command; missing `.mk` files will be downloaded automatically.

Example minimal configuration (see [Makefile.sample](./Makefile.sample) for the full version):

```make
MK_COMMON_REPO        ?= leinardi/make-common
MK_COMMON_VERSION     ?= v1.0.0

MK_COMMON_DIR         := .mk
MK_COMMON_FILES       := help.mk pre-commit.mk password.mk

# ... bootstrap logic ...
include $(addprefix $(MK_COMMON_DIR)/,$(MK_COMMON_FILES))
```

Once added, `make` will automatically fetch the specified `.mk` files from the selected version/tag.

---

## 🔄 Updating the shared snippets

To pull a newer version:

1. Update `MK_COMMON_VERSION` to the desired tag
2. Re-run any `make` target

The bootstrap logic will detect the version change and refresh the local `.mk` files.

---

## 📁 Available modules (.mk files)

| File            | Description                                                |
|-----------------|------------------------------------------------------------|
| `help.mk`       | Default `help` target with auto-generated docs             |
| `pre-commit.mk` | Wrapper around `pre-commit run`, stage checks, etc.        |
| `password.mk`   | Secure PostgreSQL-compatible password generator            |
| `opentofu.mk`   | Optional: helpers for `init`, `plan`, `apply`, and cleanup |

All modules include built-in guards to prevent accidental double inclusion.

---

## 📄 License

MIT License. See [LICENSE](./LICENSE).
