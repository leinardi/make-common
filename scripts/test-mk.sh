#!/usr/bin/env bash
#
# Smoke-tests every shared snippet the way a consumer includes it: each .mk file
# must parse together with help.mk, list its documented targets in `make help`,
# and survive being included twice (the include guards). Then dry-runs the
# recipes listed in RECIPES below, which pins what a target runs, not only that
# it parses.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail=0
for mk in "$ROOT"/.mk/*.mk; do
	name=$(basename "$mk")
	cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $mk
include $mk
MAKEFILE
	if ! out=$(make --no-print-directory -C "$WORK" help 2>&1); then
		echo "FAIL - $name: make help failed"
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
		fail=1
		continue
	fi
	if grep -q 'warning: overriding recipe' <<<"$out"; then
		echo "FAIL - $name: including it twice redefines recipes (missing include guard)"
		fail=1
		continue
	fi
	echo "ok   - $name"
done

# Recipe expectations, one per line: <snippet>|<make arguments>|<expected line>.
# Each snippet is included with help.mk only, as above, so a recipe that leans on
# a target from another snippet fails here. `make -n` prints the recipe without
# running it; the expected line must appear in it verbatim.
RECIPES=$(
	cat <<'EOF'
go.mk|go-lint|pre-commit run "golangci-lint-full" --all-files
go.mk|go-lint GO_LINT_HOOK=golangci-lint-repo-mod|pre-commit run "golangci-lint-repo-mod" --all-files
EOF
)
while IFS='|' read -r name args expected; do
	cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/$name
MAKEFILE
	# Word splitting of $args is intended: it holds a target and variable assignments.
	# shellcheck disable=SC2086
	if ! out=$(make --no-print-directory -n -C "$WORK" $args 2>&1); then
		echo "FAIL - $name: make -n $args failed"
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
		fail=1
		continue
	fi
	if ! grep -qxF -- "$expected" <<<"$out"; then
		echo "FAIL - $name: make -n $args does not run: $expected"
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
		fail=1
		continue
	fi
	echo "ok   - $name: make $args"
done <<<"$RECIPES"
exit "$fail"
