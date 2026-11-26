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
# rust.mk's rust-run for real, offline: a no-dependency crate that prints its P_VERSION stamp as
# compiled in and as its environment holds it at run time, run through make rust-run with the real
# cargo (CARGO_HOME and CARGO_TARGET_DIR scratch). The default keeps v1's behaviour, the stamps in
# the run's environment; RUST_RUN_UNSTAMPED=1 removes them there and keeps them compiled in; and a
# runner the workspace configures behaves as rust.mk documents it. Needs cargo and rustc; a missing
# one fails the test rather than skipping it.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for tool in cargo rustc; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "FAIL - rust-run: $tool is required" >&2
		exit 1
	}
done
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

export CARGO_HOME="$WORK/cargo-home" CARGO_TARGET_DIR="$WORK/target"
unset CARGO_BUILD_TARGET_DIR CARGO_BUILD_BUILD_DIR RUSTFLAGS MAKEFLAGS MFLAGS
unset P_VERSION P_COMMIT P_DATE

fail=0
ok() { echo "ok   - rust-run: $1"; }
bad() {
	echo "FAIL - rust-run: $1"
	if [[ -n ${2:-} ]]; then
		while IFS= read -r line; do printf '       %s\n' "$line"; done <<<"$2"
	fi
	fail=1
}

APP="$WORK/app"
mkdir -p "$APP/src"
printf '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\n' >"$APP/Cargo.toml"
cat >"$APP/src/main.rs" <<'RUST'
fn main() {
    let compiled = option_env!("P_VERSION").unwrap_or("none");
    let runtime = std::env::var("P_VERSION").unwrap_or_else(|_| "none".to_owned());
    println!("compiled={compiled} runtime={runtime}");
}
RUST
cat >"$APP/Makefile" <<MAKEFILE
REPO_ROOT := $APP
RUST_STAMP_PREFIX := P
GIT_VERSION := v9
GIT_COMMIT := c9
BUILD_DATE := d9
include $ROOT/.mk/help.mk
include $ROOT/.mk/rust.mk
MAKEFILE
(cd "$APP" && cargo generate-lockfile --offline -q)

# A runner the consumer configures: it says it ran, then runs the binary.
cat >"$WORK/runner" <<'RUNNER'
#!/usr/bin/env bash
echo "consumer-runner"
exec "$@"
RUNNER
chmod +x "$WORK/runner"

# run [make arguments...]: make rust-run's output, cargo's included; the status in $status.
run() {
	status=0
	out=$(make --no-print-directory -s -C "$APP" rust-run "$@" 2>&1) || status=$?
}

run
if ((status == 0)) && grep -qxF 'compiled=v9 runtime=v9' <<<"$out"; then
	ok "by default the binary has its stamps compiled in and in its environment, as in v1"
else
	bad "by default the stamps are not compiled in and in the run's environment (exit $status)" "$out"
fi

run RUST_RUN_UNSTAMPED=1
if ((status == 0)) && grep -qxF 'compiled=v9 runtime=none' <<<"$out"; then
	ok "RUST_RUN_UNSTAMPED=1 keeps the stamps compiled in and out of the run's environment"
else
	bad "RUST_RUN_UNSTAMPED=1 does not run the binary unstamped (exit $status)" "$out"
fi

mkdir -p "$APP/.cargo"
printf '[target.%s]\nrunner = "%s"\n' "'cfg(unix)'" "$WORK/runner" >"$APP/.cargo/config.toml"
run
if ((status == 0)) && grep -qxF consumer-runner <<<"$out" &&
	grep -qxF 'compiled=v9 runtime=v9' <<<"$out"; then
	ok "by default a runner the workspace configures under a cfg() key runs, as in v1"
else
	bad "by default a workspace cfg() runner does not run (exit $status)" "$out"
fi
run RUST_RUN_UNSTAMPED=1
if ((status != 0)) && grep -qF "several matching instances of \`target.'cfg(..)'.runner\`" <<<"$out" &&
	! grep -q 'compiled=' <<<"$out"; then
	ok "RUST_RUN_UNSTAMPED=1 beside a workspace cfg() runner: cargo refuses the run, as documented"
else
	bad "RUST_RUN_UNSTAMPED=1 beside a workspace cfg() runner did not fail as documented (exit $status)" "$out"
fi
rm -r "$APP/.cargo"

host=$(rustc -vV | sed -n 's/^host: //p')
runner_var="CARGO_TARGET_$(tr 'a-z.-' 'A-Z__' <<<"$host")_RUNNER"
status=0
out=$(env "$runner_var=$WORK/runner" make --no-print-directory -s -C "$APP" rust-run RUST_RUN_UNSTAMPED=1 2>&1) ||
	status=$?
if ((status == 0)) && grep -qxF consumer-runner <<<"$out" &&
	grep -qxF 'compiled=v9 runtime=v9' <<<"$out"; then
	ok "RUST_RUN_UNSTAMPED=1 beside a runner for the host's triple: that runner wins and gets the stamps, as documented"
else
	bad "RUST_RUN_UNSTAMPED=1 beside $runner_var did not behave as documented (exit $status)" "$out"
fi

exit "$fail"
