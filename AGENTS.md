# AGENTS.md

## What this is

Shared Makefile snippets (`.mk/*.mk`) that other `leinardi/*` repositories fetch into their own `.mk/` with
`scripts/bootstrap-mk-common.sh`, pinned to a tag (usually the moving `v1`). Consumers run `make mk-common-update` to pick up a
new release, so a change here reaches every repository that pins `v1` the next time it refreshes; there it shows up only as a diff
of the fetched files, which is easy to wave through.

## Common commands

```bash
make check               # pre-commit on all files (checkmake, shellcheck, actionlint, yamllint, markdownlint, prettier, …)
make check-stage         # pre-commit on the staged files only
make test                # every snippet parses, lists its targets in `make help`, keeps its include guard; the bootstrap, offline
make pre-commit-install  # installs the pre-commit and commit-msg hooks
```

This repository includes its snippets straight from `.mk/` (see `Makefile`); it does not bootstrap itself like a consumer.

## Layout

| Path | What lives there |
| --- | --- |
| `.mk/*.mk` | the shared snippets; every file a consumer lists in `MK_COMMON_FILES` is fetched from here |
| `scripts/bootstrap-mk-common.sh` | the bootstrap consumers copy once; it updates itself from the pinned tag |
| `Makefile.sample` | the canonical consumer `Makefile` (`MK_COMMON_FILES` / `MK_LOCAL_FILES` split) |
| `scripts/test-mk.sh`, `scripts/test-bootstrap.sh` | the tests behind `make test`: snippet smoke test, bootstrap with a fake `git`/`curl` |

## Invariants

- **Backward compatible within `v1`.** A target, variable or default that consumers rely on is never removed or renamed, and a
  default is never changed in a way that changes what an existing consumer runs. A breaking change is a `v2`.
- **Every snippet has an include guard** (`ifndef MK_COMMON_<NAME>_INCLUDED`) and documents its public targets with `##`, so
  `make help` lists them.
- **Configurable through `?=` variables**, never by editing the snippet in the consumer: consumers overwrite `.mk/` on every
  refresh, so a local edit to a fetched file is lost.
- **The bootstrap script is fetched by itself too.** A change to it must keep working when it is run by an older copy of itself.
  It downloads everything into a staging directory, from the exact commit it records, and installs only once every download
  succeeded, with the version file last: a failed refresh changes nothing. `scripts/test-bootstrap.sh` holds it to that.
- **Recipes are shell run by `make`:** `make test` parses them but does not run them, so a recipe change needs running by hand
  in a consumer (e.g. with `make -n <target>` and then for real).

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) with a mandatory scope, enforced by the
`conventional-pre-commit` `commit-msg` hook (`--force-scope`) and by the `conventional-commits` CI job. The release version is
derived from them: a change consumers should receive is a `fix` or a `feat`; use the snippet name as the scope. Examples:
`fix(go): quote the package list in go-fmt-check`, `feat(docker): add a docker-push target`.

## Project skills

- `.agents/skills/adversarial-review/` — how to review a change to this repository. `.claude/skills` is a symlink to
  `.agents/skills`.
