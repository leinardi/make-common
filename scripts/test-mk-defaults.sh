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
# Holds the defaults of rust.mk, rust-release.mk and web.mk to v1: the whole `make -n` output of
# every target, in the scenarios below, must match scripts/testdata/mk-defaults.golden byte for byte. An opt-in a
# consumer has not set must change nothing it runs. Each line ends with a `|` marker, so a
# trailing space in a recipe is part of the comparison too.
#
#   scripts/test-mk-defaults.sh           compare against the golden file
#   scripts/test-mk-defaults.sh --update  rewrite it (only for an intended change of a default)

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GOLDEN="$ROOT/scripts/testdata/mk-defaults.golden"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The stamps' inputs are fixed, so the output does not depend on the checkout or the clock; the
# environment that rust.mk reads is cleared.
FIXED=(GIT_COMMIT=abc123 GIT_VERSION=v1.2.3 BUILD_DATE=2026-01-02T03:04:05Z)
unset CARGO_TARGET_DIR RUSTDOCFLAGS MAKEFLAGS MFLAGS

RUST_TARGETS="rust-build rust-dist rust-run rust-test rust-clippy rust-fmt rust-fmt-check rust-doc rust-deny verify-rust"
RUST_RELEASE_TARGETS="rust-zigbuild-check rust-release-binaries rust-release-checksums rust-release-dist rust-zigbuild-install"
# rust-release.mk asks rustc for its sysroot and commit, and reads HOME and CARGO_HOME, for the
# remapped paths: those are the machine's, so a fake rustc answers with fixed ones and HOME is
# fixed, and the defaults that read them are still the ones compared.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/rustc" <<'RUSTC'
#!/usr/bin/env bash
case "$*" in
--print\ sysroot) echo /sysroot ;;
-vV) printf 'rustc 1.0.0\ncommit-hash: 0123abcd\n' ;;
*) exit 2 ;;
esac
RUSTC
chmod +x "$WORK/bin/rustc"
export PATH="$WORK/bin:$PATH" HOME=/home/user
unset CARGO_HOME
WEB_TARGETS="web-install web-update web-dev web-demo web-build web-build-demo web-test web-lint api-types build"

# Scenarios, one per line: <snippets>|<variable assignments>|<targets>.
SCENARIOS=$(
	cat <<EOF2
rust.mk||$RUST_TARGETS
rust.mk|RUST_STAMP_PREFIX=MYAPP BIN_NAME=myapp|$RUST_TARGETS
rust.mk|RUST_STAMP_PREFIX=MYAPP RUST_RUN_BIN=myapp ARGS=--help CARGO_TARGET_DIR=/tmp/t BIN_NAME=myapp|$RUST_TARGETS
rust.mk rust-release.mk||$RUST_RELEASE_TARGETS
rust.mk rust-release.mk|RUST_STAMP_PREFIX=MYAPP BIN_NAME=myapp|$RUST_RELEASE_TARGETS
web.mk rust.mk|WEB_DIR=web|$WEB_TARGETS
web.mk rust.mk||$WEB_TARGETS
web.mk rust.mk|RUST_STAMP_PREFIX=MYAPP WEB_DIR=web BIN_NAME=myapp|build
EOF2
)

mkdir -p "$WORK/web"
touch "$WORK/web/package.json" "$WORK/web/package-lock.json"

render() {
	while IFS='|' read -r snippets assignments targets; do
		# Word splitting of $snippets, $assignments and $targets is intended: they are lists.
		# shellcheck disable=SC2086
		{
			printf 'REPO_ROOT := %s\n' "$WORK"
			printf 'include %s/.mk/help.mk\n' "$ROOT"
			for snippet in $snippets; do printf 'include %s/.mk/%s\n' "$ROOT" "$snippet"; done
		} >"$WORK/Makefile"
		# shellcheck disable=SC2086
		for target in $targets; do
			printf '### %s | %s | %s\n' "$snippets" "$assignments" "$target"
			# A target that fails under -n (web-build-next-unset's exit 2) still prints its recipe;
			# its status is part of the output.
			status=0
			out=$(make --no-print-directory -n -C "$WORK" "$target" "${FIXED[@]}" $assignments 2>&1) || status=$?
			printf '%s\n' "$out" | sed -e "s|$WORK|@WORK@|g" -e "s|$ROOT|@ROOT@|g" -e 's/$/|/'
			printf '### status %s\n' "$status"
		done
	done <<<"$SCENARIOS"
}

actual=$(render)

if [[ ${1:-} == --update ]]; then
	mkdir -p "$(dirname "$GOLDEN")"
	printf '%s\n' "$actual" >"$GOLDEN"
	echo "updated $GOLDEN"
	exit 0
fi

if ! diff -u "$GOLDEN" <(printf '%s\n' "$actual"); then
	echo "FAIL - mk defaults: make -n output differs from scripts/testdata/mk-defaults.golden"
	exit 1
fi
echo "ok   - mk defaults: rust.mk, rust-release.mk and web.mk run what v1 ran"
