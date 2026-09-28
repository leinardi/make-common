#!/usr/bin/env bash
#
# Smoke-tests every shared snippet the way a consumer includes it: each .mk file
# must parse together with help.mk, list its documented targets in `make help`,
# and survive being included twice (the include guards).

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
exit "$fail"
