# Contributing

## Setup

Install [`pre-commit`](https://pre-commit.com/) and [`shellcheck`](https://www.shellcheck.net/), then install the hooks once
with `make pre-commit-install`. It installs both the `pre-commit` and the `commit-msg` hooks, so commit messages are checked when
you commit.

- `make check` runs the full pre-commit suite on every file, `make check-stage` on the staged files only.
- `make test` smoke-tests every snippet: it parses, lists its targets in `make help`, and keeps its include guard.

Consumers fetch these files blind: read [AGENTS.md](AGENTS.md) for the invariants a change must keep. A new snippet also needs a
row in the README's module table.

## Commit messages

All commits must follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) with a scope:
`<type>(<scope>)[!]: <description>`. Use the snippet name as the scope. The `conventional-pre-commit` hook enforces this on
`commit-msg`, and the `conventional-commits` CI job checks it again on every pull request.

```text
fix(go): quote the package list in go-fmt-check
feat(docker): add a docker-push target
docs(readme): list the go and docker snippets
```

The release version is derived from these types, since the last release:

| Release | Commit | Example |
| --- | --- | --- |
| major | any type with `!` before the colon, or a `BREAKING CHANGE:` footer | `feat(go)!: rename GO_CMD to GO_MAIN` |
| minor | `feat` | `feat(docker): add a docker-push target` |
| patch | `fix` | `fix(help): keep a consumer's goal` |
| none | everything else: `build`, `chore`, `ci`, `docs`, `perf`, `refactor`, `style`, `test`, `revert` | `docs(readme): fix a link` |

Pick the type by whether consumers should receive the change, not by what kind of change it is: anything that changes a fetched
file (`.mk/*.mk`, `scripts/bootstrap-mk-common.sh`) is a `fix` or a `feat`. A breaking change is a new `v2`, never a change inside
`v1`.

Pull requests are merged with merge commits; squash and rebase merging are disabled. Every commit therefore lands on `main` as it
is, so each one needs a correct type, not just the pull request as a whole.

## Releasing

Dispatch the **Release** workflow from `main`. Leave the version empty to derive it from the commits, or pass one; tick *dry run*
first to see what it would do. It calls
[`simple-tag-and-release`](https://github.com/leinardi/gh-reusable-workflows/blob/main/.github/workflows/simple-tag-and-release.md),
which creates the release and moves `v1` and `latest`. Consumers pick it up on their next `make mk-common-update`.
