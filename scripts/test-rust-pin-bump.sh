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
## rust-pin-bump for real, offline: local file:// git repositories stand in for rust-common and its
# dependencies, a consumer workspace pins rust-common v1.0.0, and the bump to v1.1.0 runs with the
# real cargo (CARGO_HOME scratch, no registry). Where a case needs Cargo to move something a
# pin-only step never moves, a cargo wrapper doctors the lock or the metadata after the real run,
# and the check must catch it and roll every file back. Needs cargo, git and python3; a missing
# one fails the test rather than skipping it.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for tool in cargo git python3; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "FAIL - rust-pin-bump: $tool is required" >&2
		exit 1
	}
done
REAL_CARGO=$(command -v cargo)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export CARGO_HOME="$WORK/cargo-home" CARGO_TARGET_DIR="$WORK/target"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset CARGO_BUILD_TARGET_DIR CARGO_BUILD_BUILD_DIR RUSTFLAGS MAKEFLAGS MFLAGS

fail=0
ok() { echo "ok   - rust-pin-bump: $1"; }
bad() {
	echo "FAIL - rust-pin-bump: $1"
	if [[ -n ${2:-} ]]; then
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$2"
	fi
	fail=1
}

repo() { git -C "$WORK/repos/$1" "${@:2}"; }

# A one-crate repository: name, version, [dependencies] text; commits it on main.
crate_repo() {
	local dir="$WORK/repos/$1"
	mkdir -p "$dir/src"
	[[ -d $dir/.git ]] || git init -q -b main "$dir"
	printf '[package]\nname = "%s"\nversion = "%s"\nedition = "2021"\n\n%s\n' "$1" "$2" "$3" >"$dir/Cargo.toml"
	printf '// %s %s\n' "$1" "$2" >"$dir/src/lib.rs"
	repo "$1" add -A
	repo "$1" commit -q -m "$1 $2"
}

url() { printf 'file://%s/repos/%s' "$WORK" "$1"; }

crate_repo leaf 0.1.0 ''
repo leaf tag v0.1.0
crate_repo leaf 0.2.0 ''
repo leaf tag v0.2.0
crate_repo old 0.1.0 ''
repo old tag v0.1.0
# dual: two versions the consumer holds both of, before the bump and after it, outside the
# rust-common closure; the retarget cases move tool's edge between them.
crate_repo dual 0.1.0 ''
repo dual tag v0.1.0
crate_repo dual 0.2.0 ''
repo dual tag v0.2.0
crate_repo extra 0.1.0 ''
EXTRA_REV1=$(repo extra rev-parse HEAD)
echo '// two' >>"$WORK/repos/extra/src/lib.rs"
repo extra commit -qam 'extra two'
EXTRA_REV2=$(repo extra rev-parse HEAD)
crate_repo other 0.1.0 ''
OTHER_REV1=$(repo other rev-parse HEAD)
echo '// two' >>"$WORK/repos/other/src/lib.rs"
repo other commit -qam 'other two'
OTHER_REV2=$(repo other rev-parse HEAD)
# tool: a third-party crate with an optional dependency, which app enables.
crate_repo tool 0.1.0 "[dependencies]
extra = { git = \"$(url extra)\", branch = \"main\", optional = true }
leaf = { git = \"$(url leaf)\", tag = \"v0.1.0\" }
dual = { git = \"$(url dual)\", tag = \"v0.1.0\" }"
repo tool tag v0.1.0

# rust-common: v1.0.0's alpha needs old and leaf 0.1; v1.1.0's alpha needs leaf 0.2 only, so old
# leaves the graph and leaf splits from the consumer's own.
RC="$WORK/repos/rust-common"
mkdir -p "$RC/crates/alpha/src"
git init -q -b main "$RC"
rc_version() {
	printf '[workspace]\nmembers = ["crates/alpha"]\nresolver = "2"\n\n[workspace.package]\nversion = "%s"\n' "$1" >"$RC/Cargo.toml"
	printf '[package]\nname = "alpha"\nversion.workspace = true\nedition = "2021"\n\n[dependencies]\n%s\n' "$2" >"$RC/crates/alpha/Cargo.toml"
	printf '// alpha %s\n' "$1" >"$RC/crates/alpha/src/lib.rs"
	git -C "$RC" add -A
	git -C "$RC" commit -q -m "v$1"
	git -C "$RC" tag "v$1"
}
rc_version 1.0.0 "old = { git = \"$(url old)\", tag = \"v0.1.0\" }
leaf = { git = \"$(url leaf)\", tag = \"v0.1.0\" }"
rc_version 1.1.0 "leaf = { git = \"$(url leaf)\", tag = \"v0.2.0\" }"
RC_URL=$(url rust-common)

# The consumer: two members on rust-common v1.0.0, and app's own leaf 0.1, tool and other.
C="$WORK/consumer"
mkdir -p "$C/app/src" "$C/lib2/src"
git init -q -b main "$C"
cat >"$C/Cargo.toml" <<EOF
[workspace]
members = ["app", "lib2"]
resolver = "2"
EOF
cat >"$C/app/Cargo.toml" <<EOF
[package]
name = "app"
version = "0.1.0"
edition = "2021"

[dependencies]
alpha = { git = "$RC_URL", tag = "v1.0.0", version = "1.0" }
leaf = { git = "$(url leaf)", tag = "v0.1.0" }
tool = { git = "$(url tool)", tag = "v0.1.0" }
other = { git = "$(url other)", branch = "main" }
dual = { git = "$(url dual)", tag = "v0.1.0" }

[features]
full = ["tool/extra"]
EOF
cat >"$C/lib2/Cargo.toml" <<EOF
[package]
name = "lib2"
version = "0.1.0"
edition = "2021"

[dependencies]
# rust-common, renamed
rc-alpha = { package = "alpha", git = "$RC_URL", tag = "v1.0.0", version = "1.0" } # the pin
dual = { git = "$(url dual)", tag = "v0.2.0" }
EOF
touch "$C/app/src/lib.rs" "$C/lib2/src/lib.rs"
cat >"$C/AGENTS.md" <<'EOF'
# Consumer

The current rust-common pin is v1.0.0. <!-- rust-pin-current -->

It moved from v0.9.0 to v1.0.0 last year.
EOF
printf 'v1.0.0 <!-- rust-pin-current -->\nv0.9.0 <!-- rust-pin-current -->\n' >"$C/TWO.md"
printf 'no marker here, v1.0.0\n' >"$C/NONE.md"
cat >"$C/Makefile" <<EOF
REPO_ROOT := $C
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk

.PHONY: bump-all
bump-all: rust-pin-bump
EOF
(cd "$C" && "$REAL_CARGO" generate-lockfile -q)
# Hold other and extra at their first revisions, so a move to the second is a real one.
sed -i -e "s|#$OTHER_REV2\"|#$OTHER_REV1\"|" -e "s|#$EXTRA_REV2\"|#$EXTRA_REV1\"|" "$C/Cargo.lock"
(cd "$C" && "$REAL_CARGO" metadata --format-version 1 --locked --all-features >/dev/null)
grep -q "#$EXTRA_REV1\"" "$C/Cargo.lock" || {
	echo "FAIL - rust-pin-bump: the fixture's lock lacks tool's extra at its first revision" >&2
	exit 1
}
git -C "$C" add -A
git -C "$C" commit -q -m consumer

# The cargo wrapper: the real cargo, then, after the re-resolving (unlocked) metadata, the move
# FAKE_MOVE names. On the locked metadata reads, FAKE_HIDE drops extra from the output (a package
# Cargo.lock holds and metadata leaves out), and FAKE_RETARGET rewrites tool's edge to dual 0.2.0
# in the read after the bump. FAKE_MOVE=lock-retarget rewrites tool's dependency string in
# Cargo.lock from dual 0.1.0 to dual 0.2.0 and keeps the real lock for cargo's own locked reads, so
# only the script's Cargo.lock view sees the move.
cat >"$WORK/cargo" <<EOF
#!/usr/bin/env bash
set -euo pipefail
locked=no
for arg in "\$@"; do [[ \$arg == --locked ]] && locked=yes; done
if [[ \$locked == yes && -f \$PWD/.real-lock ]]; then
	cp Cargo.lock .doctored-lock
	cp .real-lock Cargo.lock
	status=0
	"$REAL_CARGO" "\$@" || status=\$?
	cp .doctored-lock Cargo.lock
	exit "\$status"
fi
if [[ \$locked == yes && -n \${FAKE_HIDE:-}\${FAKE_RETARGET:-} ]]; then
	retarget=no
	[[ -n \${FAKE_RETARGET:-} && -f \$PWD/.bumped ]] && retarget=yes
	"$REAL_CARGO" "\$@" | RETARGET=\$retarget python3 -c '
import json, os, sys
data = json.load(sys.stdin)
ids = {p["name"] + "@" + p["version"]: p["id"] for p in data["packages"]}
if os.environ.get("FAKE_HIDE"):
    hidden = {p["id"] for p in data["packages"] if p["name"] == "extra"}
    data["packages"] = [p for p in data["packages"] if p["id"] not in hidden]
    nodes = [n for n in data["resolve"]["nodes"] if n["id"] not in hidden]
    for node in nodes:
        node["deps"] = [d for d in node["deps"] if d["pkg"] not in hidden]
    data["resolve"]["nodes"] = nodes
if os.environ["RETARGET"] == "yes":
    for node in data["resolve"]["nodes"]:
        if node["id"] == ids["tool@0.1.0"]:
            for dep in node["deps"]:
                if dep["name"] == "dual":
                    dep["pkg"] = ids["dual@0.2.0"]
json.dump(data, sys.stdout)
'
	exit 0
fi
"$REAL_CARGO" "\$@"
if [[ \$locked == no && \$1 == metadata ]]; then
	touch "\$PWD/.bumped"
	case \${FAKE_MOVE:-} in
	extra) sed -i "s|#$EXTRA_REV1\"|#$EXTRA_REV2\"|" Cargo.lock ;;
	other) sed -i "s|#$OTHER_REV1\"|#$OTHER_REV2\"|" Cargo.lock ;;
	lock-retarget)
		cp Cargo.lock .real-lock
		sed -i '/^name = "tool"\$/,/^\$/ s/"dual 0.1.0"/"dual 0.2.0"/' Cargo.lock
		if cmp -s Cargo.lock .real-lock; then
			echo "the lock retarget changed nothing" >&2
			exit 1
		fi
		;;
	esac
fi
EOF
chmod +x "$WORK/cargo"
printf '.bumped\n.real-lock\n.doctored-lock\n' >"$C/.git/info/exclude"

snapshot() { (cd "$C" && git ls-files -z | xargs -0 sha256sum); }
reset() {
	git -C "$C" checkout -q -- .
	rm -f "$C/.bumped" "$C/.real-lock" "$C/.doctored-lock"
}
bump() {
	make --no-print-directory -s -C "$C" rust-pin-bump RUST_PIN_URL="$RC_URL" CARGO="$WORK/cargo" "$@" 2>&1
}

# Refused before anything is touched: each leaves every tracked file as it was.
refused() {
	local what=$1 expect=$2
	shift 2
	local before out
	before=$(snapshot)
	if out=$(bump "$@"); then
		bad "$what passes" "$out"
	elif ! grep -qF -- "$expect" <<<"$out"; then
		bad "$what fails without saying: $expect" "$out"
	elif [[ $(snapshot) != "$before" ]]; then
		bad "$what changes a file" "$out"
	else
		ok "$what is refused, nothing changed"
	fi
	reset
}

refused "a malformed TAG" "is not of the form vX.Y.Z" TAG=1.1.0
refused "the current TAG" "the pin is already v1.0.0" TAG=v1.0.0
refused "a doc with no marker" "NONE.md: holds 0 lines marked rust-pin-current" TAG=v1.1.0 RUST_PIN_DOCS=NONE.md
refused "a doc with two markers" "TWO.md: holds 2 lines marked rust-pin-current" TAG=v1.1.0 RUST_PIN_DOCS=TWO.md
echo '# dirty' >>"$C/app/Cargo.toml"
refused "a dirty manifest" "uncommitted changes" TAG=v1.1.0
echo 'dirty' >>"$C/AGENTS.md"
refused "a dirty doc" "uncommitted changes" TAG=v1.1.0 RUST_PIN_DOCS=AGENTS.md
if out=$(make --no-print-directory -s -C "$C" rust-pin-bump TAG=v1.1.0 2>&1) ||
	! grep -qF "set RUST_PIN_URL" <<<"$out"; then
	bad "an unset RUST_PIN_URL passes or does not say so" "$out"
else
	ok "an unset RUST_PIN_URL is refused"
fi
if out=$(make --no-print-directory -s -C "$C" bump-all RUST_PIN_URL="$RC_URL" TAG=v1.1.0 2>&1) ||
	! grep -qF "run it as a goal of its own" <<<"$out"; then
	bad "rust-pin-bump as a prerequisite passes or does not say so" "$out"
else
	ok "rust-pin-bump as a prerequisite is refused, saying why"
fi
# A tracked manifest of another workspace (its own lock is not re-resolved here) pinning the URL.
mkdir -p "$C/fuzz"
printf '[package]\nname = "fuzz"\nversion = "0.1.0"\nedition = "2021"\n\n[workspace]\n\n[dependencies]\nalpha = { git = "%s", tag = "v1.0.0", version = "1.0" }\n' "$RC_URL" >"$C/fuzz/Cargo.toml"
git -C "$C" add fuzz/Cargo.toml
git -C "$C" commit -q -m fuzz
refused "a pin in another workspace's manifest" "fuzz/Cargo.toml pin" TAG=v1.1.0
git -C "$C" reset -q --hard HEAD~1

# Moved beyond the pin by the re-resolution: refused after the fact, and rolled back.
rolled_back() {
	local what=$1 expect=$2
	shift 2
	local before out
	before=$(snapshot)
	if out=$(env "$@" make --no-print-directory -s -C "$C" rust-pin-bump RUST_PIN_URL="$RC_URL" \
		CARGO="$WORK/cargo" TAG=v1.1.0 RUST_PIN_DOCS=AGENTS.md 2>&1); then
		bad "$what passes" "$out"
	elif ! grep -qF -- "$expect" <<<"$out" || ! grep -qF "rolled back" <<<"$out"; then
		bad "$what fails without saying: $expect, rolled back" "$out"
	elif [[ $(snapshot) != "$before" ]]; then
		bad "$what leaves a changed file" "$out"
	else
		ok "$what fails and rolls back"
	fi
	reset
}

rolled_back "an optional dependency outside the closures that moves" \
	"-> extra moved from extra 0.1.0" FAKE_MOVE=extra
# The same move with extra out of cargo metadata's view: Cargo.lock's own check still finds it.
rolled_back "a move only Cargo.lock shows" "Cargo.lock: extra 0.1.0" FAKE_MOVE=extra FAKE_HIDE=1
rolled_back "an unrelated move" "the edge app 0.1.0 (path) -> other moved" FAKE_MOVE=other
rolled_back "a transitive retarget between two packages of both graphs" \
	"metadata: the edge tool 0.1.0" FAKE_RETARGET=1
rolled_back "a retarget only Cargo.lock shows, between two packages of both graphs" \
	"Cargo.lock: the edge tool 0.1.0" FAKE_MOVE=lock-retarget

# The happy path: both members' pins, the doc's marked line, one revision in the lock, every
# member's edge on the new revision, old removed, and leaf's split reported.
if ! out=$(bump TAG=v1.1.0 RUST_PIN_DOCS=AGENTS.md); then
	bad "the bump to v1.1.0 fails" "$out"
else
	problems=()
	grep -q 'alpha = { git = ".*", tag = "v1.1.0", version = "1.1" }' "$C/app/Cargo.toml" ||
		problems+=("app's pin did not move")
	grep -q 'rc-alpha = { package = "alpha", git = ".*", tag = "v1.1.0", version = "1.1" } # the pin' "$C/lib2/Cargo.toml" ||
		problems+=("lib2's renamed pin did not move")
	grep -qx 'The current rust-common pin is v1.1.0. <!-- rust-pin-current -->' "$C/AGENTS.md" ||
		problems+=("the marked doc line did not move")
	grep -qx 'It moved from v0.9.0 to v1.0.0 last year.' "$C/AGENTS.md" ||
		problems+=("a historical mention moved")
	if ! grep -q "rust-common?tag=v1.1.0#" "$C/Cargo.lock" || grep -q "rust-common?tag=v1.0.0#" "$C/Cargo.lock"; then
		problems+=("the lock does not hold v1.1.0 alone")
	fi
	changed=$(git -C "$C" diff --name-only | LC_ALL=C sort | tr '\n' ' ')
	[[ $changed == "AGENTS.md Cargo.lock app/Cargo.toml lib2/Cargo.toml " ]] ||
		problems+=("changed files: $changed")
	edges=$(cd "$C" && "$REAL_CARGO" metadata --format-version 1 --locked --all-features | python3 -c '
import json, sys
data = json.load(sys.stdin)
for node in data["resolve"]["nodes"]:
    if node["id"] in data["workspace_members"]:
        for dep in node["deps"]:
            if "rust-common" in dep["pkg"]:
                print(dep["pkg"])
')
	[[ $(grep -c 'tag=v1.1.0' <<<"$edges") -eq 2 && $(grep -c . <<<"$edges") -eq 2 ]] ||
		problems+=("the members' edges: $edges")
	grep -q '^  - old 0.1.0' <<<"$out" || problems+=("old's removal is not reported")
	grep -q '^  split: leaf' <<<"$out" || problems+=("leaf's split is not reported")
	grep -q '"leaf 0.1.0' "$C/Cargo.lock" ||
		problems+=("Cargo did not qualify the consumer's leaf (the temporary split's case)")
	if ((${#problems[@]})); then
		bad "the bump to v1.1.0: $(printf '%s; ' "${problems[@]}")" "$out"
	else
		ok "the bump to v1.1.0 moves both members' pins, the doc's pin and the lock, and reports the split"
	fi
fi

exit "$fail"
