# AGENTS.md

## What this is

Shared Makefile snippets (`.mk/*.mk`) that other `leinardi/*` repositories fetch into their own
`.mk/` with `scripts/bootstrap-mk-common.sh`, pinned to a tag (usually the moving `v1`). Consumers
run `make mk-common-update` to pick up a new release, so a change here reaches every repository that
pins `v1` the next time it refreshes; there it shows up only as a diff of the fetched files, which
is easy to wave through.

## Common commands

```bash
make check               # pre-commit on all files (checkmake, shellcheck, actionlint, yamllint, markdownlint, prettier, licence headers, …)
make check-stage         # pre-commit on the staged files only
make test                # snippet smoke test and pinned recipe dry-runs; the bootstrap and the licence header check, offline
make pre-commit-install  # installs the pre-commit and commit-msg hooks
scripts/check-license-headers.sh  # the licence header check alone (also a pre-commit hook)
```

This repository includes its snippets straight from `.mk/` (see `Makefile`); it does not bootstrap
itself like a consumer.

## Layout

| Path | What lives there |
| --- | --- |
| `.mk/*.mk` | the shared snippets; every file a consumer lists in `MK_COMMON_FILES` is fetched from here |
| `scripts/bootstrap-mk-common.sh` | the bootstrap consumers copy once; it updates itself from the pinned tag |
| `Makefile.sample` | the canonical consumer `Makefile` (`MK_COMMON_FILES` / `MK_LOCAL_FILES` split) |
| `scripts/test-mk.sh`, `scripts/test-bootstrap.sh` | the tests behind `make test`: snippet smoke test and the `RECIPES` dry-runs, bootstrap with a fake `git`/`curl` |
| `scripts/check-license-headers.sh`, `scripts/test-license-headers.sh` | the MIT header check (a pre-commit hook) and its offline test |
| `.github/workflows/ci.yaml` | `pre-commit-all` and `mk-smoke` gate, the reviewdog jobs annotate pull requests, `ci-result` is the one required check |

## Invariants

- **Backward compatible within `v1`.** A target, variable or default that consumers rely on is never
  removed or renamed, and a default is never changed in a way that changes what an existing consumer
  runs. A breaking change is a `v2`.
- **Every snippet has an include guard** (`ifndef MK_COMMON_<NAME>_INCLUDED`) and documents its
  public targets with `##`, so `make help` lists them.
- **Configurable through `?=` variables**, never by editing the snippet in the consumer: consumers
  overwrite `.mk/` on every refresh, so a local edit to a fetched file is lost.
- **The bootstrap script is fetched by itself too.** A change to it must keep working when it is run
  by an older copy of itself. It downloads everything into a staging directory, from the exact
  commit it records, and installs only once every download succeeded, with the version file last: a
  failed refresh changes nothing. `scripts/test-bootstrap.sh` holds it to that.
- **Recipes are shell run by `make`:** `make test` parses them and dry-runs the few pinned in
  `scripts/test-mk.sh`'s `RECIPES` table, but runs none of them, so a recipe change needs running by
  hand in a consumer (e.g. with `make -n <target>` and then for real).

## Validation matrix

Run before considering an edit done. `make check` applies to every row.

| You edited | Run |
| --- | --- |
| `.mk/*.mk` | `make test`; then the changed target in a consumer, `make -n <target>` and for real. A new or changed recipe gets a `RECIPES` line in `scripts/test-mk.sh` |
| `scripts/bootstrap-mk-common.sh` | `make test`; then in a consumer, `make mk-common-update` with `MK_COMMON_VERSION` set to the branch |
| `scripts/test-*.sh`, `scripts/check-license-headers.sh` | `make test`; break what the test guards once and see it fail |
| `Makefile`, `Makefile.sample` | `make help`, `make test` |
| `.github/workflows/**` | `pre-commit run actionlint --all-files` |
| `.pre-commit-config.yaml` | `make check` (it is the change's own test) |
| `*.md` | `make check`: markdownlint holds prose to 100 columns; tables, code blocks and headings are exempt |

## Licence headers

Every tracked shell script, `.mk` snippet and the `Makefile` carries the MIT header, dated with the
year of the file's first commit; `scripts/check-license-headers.sh` (an always-run pre-commit hook)
fails on any that lacks it. Copy the header from an existing file, or use the IntelliJ copyright
profile in `.idea/copyright/`. `Makefile.sample` has none: consumers copy it as their own
`Makefile`. The snippets and the bootstrap script are fetched into consumers with their header;
consumers exempt them from their own header checks.

## Commit messages

All commits MUST be [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
**with a scope**: `<type>(<scope>)[!]: <description>`, optional blank-line body and footers.
Enforced by the `conventional-pre-commit` `commit-msg` hook (`--force-scope`) and by the
`conventional-commits` CI job. Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`,
`ci`, `chore`, `style`, `revert`. Use the snippet name as the scope. Examples:
`fix(go): quote the package list in go-fmt-check`, `ci(ci): add the ci-result job`.

Release versions are derived by `svu` (in the reusable `simple-tag-and-release` workflow) from the
commits since the last tag, so a wrong type ships a wrong version:

| Release | Commit | Example |
| --- | --- | --- |
| major | any type with `!` before the colon, or a `BREAKING CHANGE:` footer | `feat(go)!: rename GO_CMD to GO_MAIN` (a `v2`, never inside `v1`) |
| minor | `feat` | `feat(go): add the go-lint target` |
| patch | `fix` | `fix(help): keep a consumer's goal` |
| none | everything else: `perf`, `refactor`, `build`, `ci`, `chore`, `docs`, `style`, `test`, `revert` | `docs(readme): fix a link` |

The highest bump among the commits wins; with only "none" commits since the last tag, a release with
no version fails with "nothing to bump".

**Pick the type by whether consumers should receive the change, not by what kind of change it is.**
Anything that changes what a fetched file (`.mk/*.mk`, `scripts/bootstrap-mk-common.sh`) does is
`fix` (or `feat`), even when it is a performance improvement, a refactor or a revert. A change to
comments only in a fetched file (a licence header, a typo) may be `docs` or `chore`; it reaches
consumers with the next release. A `revert` of a shipped `feat` or `fix` is itself a `fix`. `svu`
matches `feat`/`fix` anywhere in the subject (e.g. `prefix:` counts as `fix:`), so avoid a word
ending in `feat` or `fix` directly before a colon in other subjects. PRs land as merge commits, so
every commit counts, not just the PR title. See [CONTRIBUTING.md](CONTRIBUTING.md#releasing).

## Project skills

- `.agents/skills/adversarial-review/` — how to review a change to this repository. `.claude/skills`
  is a symlink to `.agents/skills`.
