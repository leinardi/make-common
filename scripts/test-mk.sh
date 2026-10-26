#!/usr/bin/env bash
#
# MIT License
#
# Copyright (c) 2026 Roberto Leinardi
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
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

# Recipe expectations, one per line: <snippets>|<make arguments>|<expected line>.
# The snippets (space-separated, in include order) are included with help.mk
# only, so a recipe that leans on a target from a snippet not listed fails here.
# `make -n` prints the recipe without running it; the expected line must appear
# in it verbatim. The work directory holds a web/ app with only its manifest and
# lockfile, so web.mk's install stamp is always out of date there.
RECIPES=$(
	cat <<'EOF'
ansible-vault.mk|vault-decrypt ENV=dev|ansible-vault decrypt \
ansible-vault.mk|vault-decrypt ENV=dev ANSIBLE_VAULT=/opt/ansible/bin/ansible-vault|/opt/ansible/bin/ansible-vault decrypt \
go.mk|go-lint|pre-commit run "golangci-lint-full" --all-files
go.mk|go-lint GO_LINT_HOOK=golangci-lint-repo-mod|pre-commit run "golangci-lint-repo-mod" --all-files
web.mk|web-build WEB_DIR=web|npm --prefix "web" ci
web.mk|web-build WEB_DIR=web|npm --prefix "web" run build
web.mk|web-lint WEB_DIR=web|npm --prefix "web" run typecheck
web.mk|build WEB_DIR=web WEB_BUILD_NEXT=help|make help
web.mk parity.mk|demo-parity WEB_DIR=web SCENARIO=a/b|cd "web" && PARITY_MATRIX="" PARITY_SCENARIOS="a/b" PARITY_DEMO_PORT="5180" PARITY_PROTO_PORT="5181" npm run parity
web.mk parity.mk|demo-parity WEB_DIR=web PARITY_DEMO_PORT=5290 PARITY_PROTO_PORT=5291|cd "web" && PARITY_MATRIX="" PARITY_SCENARIOS="" PARITY_DEMO_PORT="5290" PARITY_PROTO_PORT="5291" npm run parity
web.mk parity.mk|demo-parity-accept WEB_DIR=web|echo "demo-parity-accept: REASON= is required: say why these differences are accepted" >&2; exit 2
web.mk parity.mk|demo-parity-accept WEB_DIR=web REASON=$x|cd "web" && PARITY_MATRIX="" PARITY_SCENARIOS="" PARITY_DEMO_PORT="5180" PARITY_PROTO_PORT="5181" PARITY_BASELINE=accept npm run parity
web.mk parity.mk|demo-parity-servers WEB_DIR=web|  PARITY_DEMO_PORT="5180" PARITY_PROTO_PORT="5181" npm run parity:serve:prototype & proto=$!; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web|  echo "prototype: http://127.0.0.1:5181/index.html"; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web|  echo "demo:      http://127.0.0.1:5180/"; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web|  PARITY_DEMO_PORT="5180" PARITY_PROTO_PORT="5181" npm run parity:serve:demo; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web PARITY_DEMO_PORT=5290 PARITY_PROTO_PORT=5291|  PARITY_DEMO_PORT="5290" PARITY_PROTO_PORT="5291" npm run parity:serve:prototype & proto=$!; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web PARITY_DEMO_PORT=5290 PARITY_PROTO_PORT=5291|  echo "prototype: http://127.0.0.1:5291/index.html"; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web PARITY_DEMO_PORT=5290 PARITY_PROTO_PORT=5291|  echo "demo:      http://127.0.0.1:5290/"; \
web.mk parity.mk|demo-parity-servers WEB_DIR=web PARITY_DEMO_PORT=5290 PARITY_PROTO_PORT=5291|  PARITY_DEMO_PORT="5290" PARITY_PROTO_PORT="5291" npm run parity:serve:demo; \
EOF
)
mkdir -p "$WORK/web"
touch "$WORK/web/package.json" "$WORK/web/package-lock.json"

while IFS='|' read -r name args expected; do
	# Word splitting of $name is intended: it lists the snippets to include.
	# shellcheck disable=SC2086
	includes=$(for n in $name; do printf 'include %s/.mk/%s\n' "$ROOT" "$n"; done)
	cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
$includes
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

# parity.mk without web.mk: a parity goal stops and names web.mk, rather than
# running npm with no WEB_DIR.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/parity.mk
MAKEFILE
if out=$(make --no-print-directory -n -C "$WORK" demo-parity 2>&1) ||
	! grep -q 'parity.mk needs web.mk' <<<"$out"; then
	echo "FAIL - parity.mk: a parity goal without web.mk does not stop"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - parity.mk: a parity goal without web.mk stops"
fi

exit "$fail"
