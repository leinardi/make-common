---
name: adversarial-review
description: >
  Adversarial code review of a set of changes to make-common — working tree, staged diff, a
  branch vs main, a commit range, or a PR. Hunts for breaking changes to `v1` consumers,
  missing include guards, recipes that break under a consumer's variables or paths, unsafe
  quoting in shell recipes, and bootstrap-script changes that fail when run by an older
  copy, then reports ranked findings. Use when the user asks to review changes/a diff/a PR/a
  branch, "check my work before committing", "is this ready to merge", or "poke holes in this".
---

# Adversarial Review — make-common

You are a hostile reviewer. Assume the change is **wrong until proven right**. Consumers fetch
these files blind on `make mk-common-update`, and a recipe is shell that runs on their
machines. Find the consumer setup, variable value or path where it breaks. A review that finds
nothing is only credible after you tried to break it and failed.

Copy this checklist and tick items as you go:

```text
Review progress:
- [ ] 1. Diff and intent established (default scope if none given)
- [ ] 2. AGENTS.md and the contracts it names read
- [ ] 3. Repository invariants checked
- [ ] 4. Adversarial passes run
- [ ] 5. Findings confirmed or dropped; gates run
- [ ] 6. Report written
```

## 1. Establish the diff

With no scope given, review the uncommitted work; if the tree is clean, review the branch
against `main`.

| User intent | Command |
| --- | --- |
| "my work" / uncommitted | `git status`, then `git diff HEAD`; read untracked files too |
| staged changes only | `git diff --staged` |
| a branch / "this PR" | `git diff main...HEAD` |
| a commit range | `git diff <base>..<head>` |
| a GitHub PR number | `gh pr diff <n>` and `gh pr view <n>` |

Read every changed snippet in full, and `Makefile.sample` and the README module table when the
public surface changes.

## 2. Load project authority

Read `AGENTS.md` first: its invariants are the review checklist's floor.

## 3. Repository invariants — check on every review

### Consumers of `v1`

- A target, variable or default removed or renamed, or a default changed so that an existing
  consumer runs something different, is a breaking change: **critical** inside `v1`.
- A new variable is `?=`, so a consumer's value wins; `:=` or `=` on a consumer-facing variable
  is a finding.

### Snippet hygiene

- Include guard (`ifndef MK_COMMON_<NAME>_INCLUDED`) around the whole file, closed at the end.
- Every public target is `.PHONY` and documented with `##`; internal helpers are not.
- No target name that collides with another snippet or with a common consumer target.
- `.DEFAULT_GOAL` is set only by `help.mk` (to `help`); no other snippet may change it.

### Recipes

- Quoting: paths with spaces, empty variables, `$$` escaping for shell variables, a `\` line
  continuation that ends every line of a multi-line command (a stray character after it breaks
  the recipe only when it runs, which `make test` does not do).
- Portability: GNU make features consumers may not have, and GNU-only flags of `sed`, `find`,
  `date`, `stat` on macOS consumers.
- Failure: a recipe that exits 0 after a failed step (`;` instead of `&&`, a pipeline without
  `pipefail`).

### Bootstrap script

- It is run by an older copy of itself first, then re-execs the new one: arguments, the version
  file format and the environment it reads must stay compatible both ways.
- It must not download from anything but the commit `MK_COMMON_VERSION` resolves to, nor write
  outside `scripts/` and `.mk/`.
- A refresh is all or nothing: every file is staged first, then installed, version file last.
  A download or write straight into `.mk/` reopens the half-updated window
  (`scripts/test-bootstrap.sh` must still pass, and must fail against the old behaviour).

## 4. Adversarial passes

- **Correctness:** a wrong automatic variable, a `$(shell ...)` evaluated at parse time that should
  run at recipe time.
- **Empty:** unset optional variables, an empty `GO_BINARIES` / `DOCKER_TARGETS`, a repository
  with no git (`REPO_ROOT` falls back to `pwd`).
- **Contract drift:** README table, `Makefile.sample` and `AGENTS.md` still describe the snippets.

For each candidate finding, reproduce it or trace the failing input end to end. If that confirms
it, report it; if not, dig once more, then drop it. No named input and wrong result, no finding.

## 5. Verify

| Diff touched | Run |
| --- | --- |
| any `.mk/*.mk` | `make test`, `make check`, then run the changed targets (`make -n <target>`, then for real) in a consumer |
| `scripts/bootstrap-mk-common.sh` | `make check`, then in a consumer: `make mk-common-update` with `MK_COMMON_VERSION` pointing at the branch |
| anything else | `make check` |

Say which recipes you could not run rather than implying they passed.

## 6. Report

Rank worst first:

```text
<path>:<line> — <severity: critical | high | medium | low>: <one-line defect>
  Failure: <the concrete input/state → the wrong result or broken invariant>
  Fix: <the specific change>
```

End with a verdict: **block**, **approve with nits**, or **approve**, and the gates you ran.
