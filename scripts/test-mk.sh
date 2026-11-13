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
# A developer's cargo directories would steer the fake cargo and the metadata read.
unset CARGO_TARGET_DIR CARGO_BUILD_TARGET_DIR CARGO_BUILD_BUILD_DIR

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# The snippets a snippet needs included before it, as a consumer lists them.
needs() {
	case $1 in
	rust-release.mk) echo rust.mk ;;
	image.mk) echo rust.mk docker.mk rust-release.mk ;;
	*) ;;
	esac
}

fail=0
for mk in "$ROOT"/.mk/*.mk; do
	name=$(basename "$mk")
	needed=$(for n in $(needs "$name"); do printf 'include %s/.mk/%s\n' "$ROOT" "$n"; done)
	cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
$needed
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
password.mk|password|head -c 4096 /dev/urandom | env LC_ALL=C tr -dc 'A-Za-z0-9_.+=,-' | cut -c 1-99
go.mk|go-lint|pre-commit run "golangci-lint-full" --all-files
go.mk|go-lint GO_LINT_HOOK=golangci-lint-repo-mod|pre-commit run "golangci-lint-repo-mod" --all-files
web.mk|web-build WEB_DIR=web|npm --prefix "web" ci
web.mk|web-build WEB_DIR=web|npm --prefix "web" run build
web.mk|web-lint WEB_DIR=web|npm --prefix "web" run typecheck
web.mk|build WEB_DIR=web WEB_BUILD_NEXT=help|make help
web.mk go.mk|build WEB_DIR=web|make go-build
web.mk rust.mk|build WEB_DIR=web|make rust-dist
rust.mk|rust-build|cargo build --workspace --all-targets --all-features --locked
rust.mk|rust-build RUST_STAMP_PREFIX=MYAPP GIT_VERSION=v1.2.3 GIT_COMMIT=abc BUILD_DATE=d|MYAPP_VERSION="v1.2.3" MYAPP_COMMIT="abc" MYAPP_DATE="d" cargo build --workspace --all-targets --all-features --locked
rust.mk|rust-clippy RUST_FEATURES=|cargo clippy --workspace --all-targets  --locked -- -D warnings
rust.mk|rust-dist BIN_NAME=myapp|cargo build --release --locked --bin "myapp"
rust.mk|rust-dist BIN_NAME=myapp CARGO_TARGET_DIR=/tmp/t|cp "/tmp/t/release/myapp" "dist/myapp"
rust.mk|rust-run RUST_RUN_BIN=myapp ARGS=--help|cargo run --locked --bin "myapp" -- --help
rust.mk|rust-deny|cargo deny --workspace check
rust.mk|rust-build RUST_STAMP_PREFIX=MYAPP RUST_BUILD_ENV=|cargo build --workspace --all-targets --all-features --locked
rust.mk|rust-dist BIN_NAME=myapp RUST_DIST_PROFILE=dist-local|cargo build --profile "dist-local" --locked --bin "myapp"
rust.mk|rust-dist BIN_NAME=myapp RUST_DIST_PROFILE=dist-local|cp "target/dist-local/myapp" "dist/myapp"
rust.mk|rust-dist BIN_NAME=myapp RUST_DIST_PROFILE=dev CARGO_TARGET_DIR=/tmp/t|cp "/tmp/t/debug/myapp" "dist/myapp"
rust.mk|rust-dist RUST_STAMP_PREFIX=MYAPP RUST_BUILD_ENV= GIT_VERSION=v1 GIT_COMMIT=abc BUILD_DATE=d|MYAPP_VERSION="v1" MYAPP_COMMIT="abc" MYAPP_DATE="d" cargo build --release --locked --bin "app"
rust.mk|rust-clean-stale|cargo sweep --time "7"
rust.mk|rust-clean-stale RUST_SWEEP_DAYS=30|cargo sweep --time "30"
rust.mk|rust-clean-stale|cargo sweep --installed
web.mk|web-build WEB_DIR=web WEB_DIST_SYNC_DIR=web/dist|npm --prefix "web" run build -- --outDir ".dist-staging" --emptyOutDir && rsync -r --checksum --delete "web/.dist-staging/" "web/dist/"
web.mk|build WEB_DIR=web|echo "build: set WEB_BUILD_NEXT to the target that builds the binary embedding the web app" >&2; exit 2
rust.mk rust-release.mk|rust-release-binaries BIN_NAME=myapp REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/r/target|RUSTFLAGS="F"  cargo zigbuild --release --locked --target "x86_64-unknown-linux-musl" --bin myapp
rust.mk rust-release.mk|rust-release-binaries BIN_NAME=myapp REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/r/target|cp "/r/target/aarch64-unknown-linux-musl/release/myapp" "/r/dist/myapp-linux-arm64"
rust.mk rust-release.mk|rust-release-binaries BIN_NAME=myapp REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/tmp/t|cp "/tmp/t/aarch64-unknown-linux-musl/release/myapp" "/r/dist/myapp-linux-arm64"
rust.mk rust-release.mk|rust-release-checksums BIN_NAME=myapp REPO_ROOT=/r|cd "/r/dist" && sha256sum "myapp-linux-amd64" "myapp-linux-arm64" > checksums.txt
rust.mk rust-release.mk|rust-release-binaries RUST_RELEASE_BINS=controller RUST_RELEASE_BINS+=agent RUST_RELEASE_PLATFORMS=linux/amd64 REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_STAMP_PREFIX=APP GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d RUST_RELEASE_TARGET_DIR=/r/target|RUSTFLAGS="F"  APP_VERSION="v1" APP_COMMIT="c" APP_DATE="d" cargo zigbuild --release --locked --target "x86_64-unknown-linux-musl" --bin controller --bin agent
rust.mk rust-release.mk|rust-release-binaries RUST_RELEASE_BINS=controller RUST_RELEASE_BINS+=agent RUST_RELEASE_PLATFORMS=linux/amd64 REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/r/target|cp "/r/target/x86_64-unknown-linux-musl/release/controller" "/r/dist/controller-linux-amd64"
rust.mk rust-release.mk|rust-release-binaries RUST_RELEASE_BINS=controller RUST_RELEASE_BINS+=agent RUST_RELEASE_PLATFORMS=linux/amd64 REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/r/target|cp "/r/target/x86_64-unknown-linux-musl/release/agent" "/r/dist/agent-linux-amd64"
rust.mk rust-release.mk|rust-release-checksums RUST_RELEASE_BINS=controller RUST_RELEASE_BINS+=agent REPO_ROOT=/r|cd "/r/dist" && sha256sum "controller-linux-amd64" "controller-linux-arm64" "agent-linux-amd64" "agent-linux-arm64" > checksums.txt
rust.mk rust-release.mk|rust-release-binaries RUST_RELEASE_PREREQS=rust-fmt REPO_ROOT=/r RUST_RELEASE_RUSTFLAGS=F RUST_RELEASE_TARGET_DIR=/r/target|cargo fmt --all
rust.mk docker.mk rust-release.mk image.mk|image-build-prebuilt BIN_NAME=myapp REPO_ROOT=/r IMAGE_PLATFORM=linux/arm64 GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|docker buildx build --load --platform "linux/arm64" --target prebuilt --build-context dist="/r/dist" -f "deployments/docker/Dockerfile" -t "myapp:prebuilt-linux-arm64" --build-arg VERSION="v1" --build-arg COMMIT="c" --build-arg DATE="d" "."
rust.mk docker.mk rust-release.mk image.mk|image-test BIN_NAME=myapp REPO_ROOT=/r IMAGE_PLATFORM=linux/arm64 IMAGE_TEST_TIER=reduced GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|"/r/scripts/image-test.sh" --tier "reduced" --image "myapp:prebuilt-linux-arm64" --platform "linux/arm64" --binary "/r/dist/myapp-linux-arm64" --expect-version "v1 c d"
rust.mk docker.mk rust-release.mk image.mk|image-build-test BIN_NAME=myapp REPO_ROOT=/r GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|make --no-print-directory image-build-prebuilt-myapp GIT_VERSION="v1" GIT_COMMIT="c" BUILD_DATE="d"
rust.mk docker.mk rust-release.mk image.mk|image-build-test BIN_NAME=myapp REPO_ROOT=/r GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|make --no-print-directory image-test-myapp GIT_VERSION="v1" GIT_COMMIT="c" BUILD_DATE="d"
rust.mk docker.mk rust-release.mk image.mk|image-test-agent-compose DOCKER_TARGETS=controller DOCKER_TARGETS+=agent DOCKER_TARGETS+=agent-compose IMAGE_NAME_agent-compose=app-ac IMAGE_BIN_agent-compose=agent REPO_ROOT=/r IMAGE_PLATFORM=linux/amd64 IMAGE_HOST_PLATFORM=linux/amd64 GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|"/r/scripts/image-test.sh" --tier "full" --image "app-ac:prebuilt-linux-amd64" --platform "linux/amd64" --binary "/r/dist/agent-linux-amd64" --expect-version "v1 c d"
rust.mk docker.mk rust-release.mk image.mk|image-test-controller DOCKER_TARGETS=controller DOCKER_TARGETS+=agent IMAGE_NAME_controller=app-c REPO_ROOT=/r IMAGE_PLATFORM=linux/amd64 IMAGE_HOST_PLATFORM=linux/amd64 GIT_VERSION=v1 GIT_COMMIT=c BUILD_DATE=d|"/r/scripts/image-test.sh" --tier "full" --image "app-c:prebuilt-linux-amd64" --platform "linux/amd64" --binary "/r/dist/controller-linux-amd64" --expect-version "v1 c d"
rust.mk docker.mk rust-release.mk image.mk|image-test BIN_NAME=myapp IMAGE_PLATFORM=linux/amd64 IMAGE_HOST_PLATFORM=linux/amd64 IMAGE_TEST_FULL_EXTRA=help|if [ "full" = full ]; then make --no-print-directory help; fi
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

# rust.mk and rust-release.mk ask cargo where it writes (cargo metadata's target_directory and
# build_directory): a fake cargo answers as cargo does, from CARGO_TARGET_DIR when it has one, else
# from FAKE_TARGET_DIR (the recipes below: the relative target/), and logs each call.
mkdir -p "$WORK/bin"
cat >"$WORK/bin/cargo" <<'CARGO'
#!/usr/bin/env bash
[[ "$1 $2 $3 $4" == "metadata --format-version 1 --no-deps" ]] || exit 2
echo call >>"$CARGO_CALLS"
target=${CARGO_TARGET_DIR:-$FAKE_TARGET_DIR}
printf '{"packages":[],"target_directory":"%s",%s"version":1,"workspace_root":"/w","metadata":%s}\n' \
	"$target" "${FAKE_BUILD_DIR:+\"build_directory\":\"$FAKE_BUILD_DIR\",}" "${FAKE_METADATA:-null}"
CARGO
chmod +x "$WORK/bin/cargo"
export CARGO_CALLS="$WORK/cargo-calls"

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
	if ! out=$(PATH="$WORK/bin:$PATH" FAKE_TARGET_DIR=target CARGO_CALLS=/dev/null \
		make --no-print-directory -n -C "$WORK" $args 2>&1); then
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

# Run password generation too: a malformed tr range can fail while the recipe's
# final echo still makes make succeed. Check stderr, length and allowed bytes.
# SIGPIPE is ignored, as on a GitHub Actions runner, where a writer whose reader
# exits early prints "write error: Broken pipe" instead of dying quietly.
if ! out=$(
	trap '' PIPE
	make --no-print-directory -s -f "$ROOT/.mk/password.mk" password 2>"$WORK/password.err"
) ||
	[[ -s "$WORK/password.err" ]]; then
	echo "FAIL - password.mk: password generation failed or wrote stderr"
	fail=1
else
	password=${out#*$'\n'}
	if [[ ${#password} -ne 99 || $password == *[!a-zA-Z0-9_.+=,-]* ]]; then
		echo "FAIL - password.mk: expected 99 PostgreSQL-compatible characters"
		fail=1
	else
		echo "ok   - password.mk: generates 99 PostgreSQL-compatible characters"
	fi
fi

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

# rust-release.mk without rust.mk: make stops at the include and names rust.mk, rather than
# building with an empty CARGO and BIN_NAME.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust-release.mk
MAKEFILE
if out=$(make --no-print-directory -n -C "$WORK" rust-release-binaries 2>&1) ||
	! grep -q 'rust-release.mk needs rust.mk' <<<"$out"; then
	echo "FAIL - rust-release.mk: including it without rust.mk does not stop"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust-release.mk: including it without rust.mk stops"
fi

# An empty RUST_RELEASE_BINS stops make, rather than checksumming stdin.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
include $ROOT/.mk/rust-release.mk
MAKEFILE
if out=$(make --no-print-directory -n -C "$WORK" rust-release-checksums RUST_RELEASE_BINS= 2>&1) ||
	! grep -q 'RUST_RELEASE_BINS is empty' <<<"$out"; then
	echo "FAIL - rust-release.mk: an empty RUST_RELEASE_BINS does not stop"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust-release.mk: an empty RUST_RELEASE_BINS stops"
fi

# image.mk without docker.mk or rust-release.mk stops and names what is missing, and the full tier
# is refused off the host's platform.
for missing in docker.mk rust-release.mk; do
	includes=$(for n in rust.mk docker.mk rust-release.mk; do
		[[ $n == "$missing" ]] || printf 'include %s/.mk/%s\n' "$ROOT" "$n"
	done)
	cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
$includes
include $ROOT/.mk/image.mk
MAKEFILE
	if out=$(make --no-print-directory -n -C "$WORK" image-test 2>&1) ||
		! grep -q "image.mk needs $missing" <<<"$out"; then
		echo "FAIL - image.mk: including it without $missing does not stop"
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
		fail=1
	else
		echo "ok   - image.mk: including it without $missing stops"
	fi
done
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
include $ROOT/.mk/docker.mk
include $ROOT/.mk/rust-release.mk
include $ROOT/.mk/image.mk
MAKEFILE
if out=$(make --no-print-directory -C "$WORK" image-test IMAGE_TEST_TIER=full \
	IMAGE_HOST_PLATFORM=linux/amd64 IMAGE_PLATFORM=linux/arm64 2>&1) ||
	! grep -q "the full tier runs on the host's platform (linux/amd64), not linux/arm64" <<<"$out"; then
	echo "FAIL - image.mk: the full tier off the host's platform is not refused"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - image.mk: the full tier off the host's platform is refused"
fi

# web.mk's WEB_DIST_SYNC_DIR, run for real (make -n cannot see where the build writes): a fake npm
# that, like npm and vite, resolves the build's --outDir against --prefix. A second build of the
# same app leaves the synced files' modification times alone, a changed file is updated, a file the
# build no longer makes is deleted, and nothing lands under WEB_DIR/WEB_DIR. Once with WEB_DIR
# relative to the consumer's directory and once absolute.
cat >"$WORK/bin/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --prefix ]] || exit 2
cd "$2"
shift 2
[[ $1 == ci ]] && exit 0
[[ "$1 $2 $3 $4" == "run build -- --outDir" ]] || exit 2
out=$5
rm -rf "$out"
mkdir -p "$out"
cp -R "$APP_SRC/." "$out/"
NPM
chmod +x "$WORK/bin/npm"

# rust-release.mk asks cargo where it writes (cargo metadata's target_directory and
# build_directory), so a CARGO_TARGET_DIR, a build.target-dir or a build.build-dir is copied from
# or remapped, not <repo>/target: the fake cargo above answers the metadata. A directory outside
# the checkout is remapped to /src/target after the fixed remaps, which come again after it when
# inside it (rustc applies the last match), and so is another one inside the checkout; the
# checkout's target/ is not (it is /src/target already). An older cargo without build_directory
# stands for both; a cargo that cannot answer stops make.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
include $ROOT/.mk/rust-release.mk
MAKEFILE
# release_dry_run <target directory> <build directory, empty for none> [make arguments...]
release_dry_run() {
	local target=$1 build=$2
	shift 2
	: >"$CARGO_CALLS"
	FAKE_TARGET_DIR=$target FAKE_BUILD_DIR=$build make --no-print-directory -n -C "$WORK" \
		rust-release-binaries BIN_NAME=myapp RUST_RELEASE_PLATFORMS=linux/amd64 \
		CARGO="$WORK/bin/cargo" RUST_RELEASE_RUST_SRC=/rs RUST_RELEASE_RUSTC_HASH=h \
		CARGO_HOME=/ch "$@" 2>&1
}
# release_check <description> <output> <fixed strings the output holds...>, with !<string> for
# one it must not hold.
release_check() {
	local description=$1 output=$2 expected
	shift 2
	for expected in "$@"; do
		local held=0
		grep -qF -- "${expected#!}" <<<"$output" && held=1
		if { [[ $expected == !* ]] && ((held)); } || { [[ $expected != !* ]] && ((!held)); }; then
			echo "FAIL - rust-release.mk: $description ($expected)"
			while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$output"
			fail=1
			return
		fi
	done
	echo "ok   - rust-release.mk: $description"
}
cp_from='cp "%s/x86_64-unknown-linux-musl/release/myapp"'
fixed="--remap-path-prefix=$WORK=/src --remap-path-prefix=/ch=/cargo --remap-path-prefix=/rs=/rustc/h"
out=$(release_dry_run /custom/t "") || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "the copy and the remap follow cargo's target directory" "$out" \
	"$(printf "$cp_from" /custom/t)" "$fixed --remap-path-prefix=/custom/t=/src/target\"" \
	"!=/target "
release_check "cargo is asked once per run" "calls=$(wc -l <"$CARGO_CALLS" | tr -d ' ');" "calls=1;"
out=$(release_dry_run "$WORK/target" "$WORK/target") || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "a target directory inside the checkout keeps the /src remap alone" "$out" \
	"$(printf "$cp_from" "$WORK/target")" "$fixed\"" "!=/src/target"
out=$(release_dry_run "$WORK/target/" "$WORK/target/") || true
release_check "the checkout's target/ with a trailing slash keeps the /src remap alone" "$out" \
	"$fixed\"" "!=/src/target"
out=$(release_dry_run "$WORK/build" "$WORK/build") || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "another target directory inside the checkout is remapped to /src/target" "$out" \
	"$(printf "$cp_from" "$WORK/build")" "$fixed --remap-path-prefix=$WORK/build=/src/target\""
out=$(release_dry_run "$WORK/target" /b) || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "a build directory outside the checkout is remapped" "$out" \
	"$(printf "$cp_from" "$WORK/target")" "$fixed --remap-path-prefix=/b=/src/target\"" \
	"!--remap-path-prefix=$WORK/target"
out=$(release_dry_run /ch/build/target /ch/build) || true
release_check "a build directory in the cargo home, and a target directory in it, win" "$out" \
	"$fixed --remap-path-prefix=/ch/build=/src/target --remap-path-prefix=/ch/build/target=/src/target\""
out=$(release_dry_run "${WORK%/*}" "${WORK%/*}") || true
release_check "a checkout inside the target directory stays /src" "$out" \
	"$fixed --remap-path-prefix=${WORK%/*}=/src/target --remap-path-prefix=$WORK=/src\""
out=$(FAKE_METADATA='{"target_directory":"/m","build_directory":"/m"}' release_dry_run /custom/t /b) || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "workspace metadata keys of the same name are not read" "$out" \
	"$(printf "$cp_from" /custom/t)" "--remap-path-prefix=/b=/src/target" "!/m="
out=$(release_dry_run /custom/t "" RUST_RELEASE_TARGET_DIR="/a b") || true
release_check "a target directory set with a space stops" "$out" \
	"a target or build directory with a space cannot be remapped"
out=$(release_dry_run /h/ "" CARGO_HOME=/h/c) || true
release_check "a trailing slash on a directory holding the cargo home keeps the /cargo remap last" \
	"$out" "--remap-path-prefix=/h=/src/target --remap-path-prefix=/h/c=/cargo\""
out=$(release_dry_run "/a b" "") || true
release_check "a target directory with a space stops" "$out" \
	"cannot read cargo's target directory; set RUST_RELEASE_TARGET_DIR"
# make 4.4 and later give $(shell) the command line's variables by themselves, so this passes
# there without the variables passed by name; make 4.3 (ubuntu-latest, Debian 12) needs them.
out=$(release_dry_run /custom/t /custom/t CARGO_TARGET_DIR=/cli/t) || true
# shellcheck disable=SC2059 # cp_from is the format
release_check "a CARGO_TARGET_DIR on make's command line reaches cargo" "$out" \
	"$(printf "$cp_from" /cli/t)" "--remap-path-prefix=/cli/t=/src/target"
if out=$(make --no-print-directory -n -C "$WORK" rust-release-binaries BIN_NAME=myapp \
	RUST_RELEASE_PLATFORMS=linux/amd64 CARGO=false 2>&1) ||
	! grep -q "cannot read cargo's target directory; set RUST_RELEASE_TARGET_DIR" <<<"$out"; then
	echo "FAIL - rust-release.mk: a cargo that cannot report its target directory does not stop"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust-release.mk: a cargo that cannot report its target directory stops"
fi

# rust.mk's rust-dist copies from cargo's target directory (a build.target-dir that only cargo
# knows), asks cargo once for two expansions, and stops when cargo cannot report it rather than
# copying from target/.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
again: rust-dist
	cp "\$(RUST_TARGET_DIR)/again" /dev/null
MAKEFILE
: >"$CARGO_CALLS"
out=$(FAKE_TARGET_DIR=/custom/t make --no-print-directory -n -C "$WORK" again BIN_NAME=myapp \
	CARGO="$WORK/bin/cargo" 2>&1) || true
if [[ $out != *'cp "/custom/t/release/myapp" "dist/myapp"'* ]]; then
	echo "FAIL - rust.mk: rust-dist does not copy from cargo's target directory"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
elif [[ $(wc -l <"$CARGO_CALLS" | tr -d ' ') != 1 ]]; then
	echo "FAIL - rust.mk: rust-dist asks cargo more than once"
	fail=1
else
	echo "ok   - rust.mk: rust-dist copies from cargo's target directory, asking cargo once"
fi
out=$(FAKE_TARGET_DIR=/custom/t make --no-print-directory -n -C "$WORK" rust-dist BIN_NAME=myapp \
	CARGO="$WORK/bin/cargo" RUST_TARGET_DIR=/set 2>&1) || true
if [[ $out != *'cp "/set/release/myapp" "dist/myapp"'* ]]; then
	echo "FAIL - rust.mk: a RUST_TARGET_DIR the consumer sets is not used"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust.mk: a RUST_TARGET_DIR the consumer sets is used"
fi
if out=$(make --no-print-directory -n -C "$WORK" rust-dist BIN_NAME=myapp CARGO=false 2>&1) ||
	! grep -q "cannot read cargo's target directory (run cargo metadata to see why); set RUST_TARGET_DIR" <<<"$out"; then
	echo "FAIL - rust.mk: a cargo that cannot report its target directory does not stop rust-dist"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust.mk: a cargo that cannot report its target directory stops rust-dist"
fi

# A file's modification time in seconds: GNU stat, else BSD/macOS stat.
mtime() {
	stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

sync_case() {
	local label=$1 web_dir=$2 consumer=$WORK/sync-$1
	mkdir -p "$consumer/web/node_modules" "$consumer/src"
	touch "$consumer/web/package.json" "$consumer/web/package-lock.json"
	touch "$consumer/web/node_modules/.package-lock.json"
# rust.mk's rust-dist copies from cargo's target directory (a build.target-dir that only cargo
# knows), asks cargo once for two expansions, and stops when cargo cannot report it rather than
# copying from target/.
cat >"$WORK/Makefile" <<MAKEFILE
REPO_ROOT := $WORK
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
again: rust-dist
	cp "\$(RUST_TARGET_DIR)/again" /dev/null
MAKEFILE
: >"$CARGO_CALLS"
out=$(FAKE_TARGET_DIR=/custom/t make --no-print-directory -n -C "$WORK" again BIN_NAME=myapp \
	CARGO="$WORK/bin/cargo" 2>&1) || true
if [[ $out != *'cp "/custom/t/release/myapp" "dist/myapp"'* ]]; then
	echo "FAIL - rust.mk: rust-dist does not copy from cargo's target directory"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
elif [[ $(wc -l <"$CARGO_CALLS" | tr -d ' ') != 1 ]]; then
	echo "FAIL - rust.mk: rust-dist asks cargo more than once"
	fail=1
else
	echo "ok   - rust.mk: rust-dist copies from cargo's target directory, asking cargo once"
fi
out=$(FAKE_TARGET_DIR=/custom/t make --no-print-directory -n -C "$WORK" rust-dist BIN_NAME=myapp \
	CARGO="$WORK/bin/cargo" RUST_TARGET_DIR=/set 2>&1) || true
if [[ $out != *'cp "/set/release/myapp" "dist/myapp"'* ]]; then
	echo "FAIL - rust.mk: a RUST_TARGET_DIR the consumer sets is not used"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust.mk: a RUST_TARGET_DIR the consumer sets is used"
fi
if out=$(make --no-print-directory -n -C "$WORK" rust-dist BIN_NAME=myapp CARGO=false 2>&1) ||
	! grep -q "cannot read cargo's target directory (run cargo metadata to see why); set RUST_TARGET_DIR" <<<"$out"; then
	echo "FAIL - rust.mk: a cargo that cannot report its target directory does not stop rust-dist"
	while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$out"
	fail=1
else
	echo "ok   - rust.mk: a cargo that cannot report its target directory stops rust-dist"
fi

	printf 'one\n' >"$consumer/src/index.html"
	printf 'two\n' >"$consumer/src/app.js"
	printf 'gone\n' >"$consumer/src/old.js"
	cat >"$consumer/Makefile" <<MAKEFILE
REPO_ROOT := $consumer
include $ROOT/.mk/help.mk
include $ROOT/.mk/web.mk
MAKEFILE
	local build=(make --no-print-directory -s -C "$consumer" web-build WEB_DIR="$web_dir"
		WEB_DIST_SYNC_DIR="$web_dir/dist")
	local dist=$consumer/web/dist problem="" before=""
	PATH="$WORK/bin:$PATH" APP_SRC="$consumer/src" "${build[@]}" >/dev/null 2>&1 ||
		problem="the first build failed"
	if [[ -z $problem ]]; then
		# touch -t is POSIX; the time it sets is read back rather than assumed.
		touch -t 200101010000 "$dist/index.html" "$dist/app.js"
		before=$(mtime "$dist/index.html")
		printf 'three\n' >"$consumer/src/app.js"
		rm "$consumer/src/old.js"
		PATH="$WORK/bin:$PATH" APP_SRC="$consumer/src" "${build[@]}" >/dev/null 2>&1 ||
			problem="the second build failed"
	fi
	if [[ -z $problem ]]; then
		if [[ $(mtime "$dist/index.html") != "$before" ]]; then
			problem="an unchanged file got a new modification time"
		elif [[ $(cat "$dist/app.js") != three ]]; then
			problem="a changed file was not updated"
		elif [[ -e $dist/old.js ]]; then
			problem="a file the build no longer makes was not deleted"
		elif [[ -e $consumer/web/web ]]; then
			problem="the build wrote under WEB_DIR/WEB_DIR"
		fi
	fi
	if [[ -n $problem ]]; then
		echo "FAIL - web.mk: WEB_DIST_SYNC_DIR with $label WEB_DIR: $problem"
		fail=1
	else
		echo "ok   - web.mk: WEB_DIST_SYNC_DIR with $label WEB_DIR syncs only changed files"
	fi
}
sync_case relative web
sync_case absolute "$WORK/sync-absolute/web"

exit "$fail"
