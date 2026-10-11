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
# Tests scripts/check-license-headers.sh offline, in a scratch repository: the
# check must pass on a tree whose governed files carry the MIT header, and fail,
# naming the file, on each way a header can be missing or wrong.
#
# check() takes each condition as a single-quoted string and evals it when the
# check runs, so the expansions inside are meant to be deferred (SC2016), and
# the linter cannot see that STATUS, read only inside them, is used (SC2034).
# shellcheck disable=SC2016,SC2034

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/check-license-headers.sh"

# A git hook exports GIT_DIR, GIT_INDEX_FILE and friends; the scratch repository
# must not inherit them, or `git add` below would write into the real index.
while IFS= read -r var; do
	unset "$var"
done < <(env | sed -n 's/^\(GIT_[A-Z_]*\)=.*/\1/p')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

R="$WORK/repo"
mkdir -p "$R/scripts" "$R/.mk"
git init -q "$R"
cp "$SCRIPT" "$R/scripts/check-license-headers.sh"

# The header exactly as this repository's own files carry it (lines 2-24 of the
# checker), with the year of the file under test.
header() { sed -n '2,24p' "$SCRIPT" | sed "s/Copyright (c) [0-9-]* /Copyright (c) $1 /"; }

{ header 2025; printf '\nifndef X\nendif\n'; } >"$R/.mk/good.mk"
{ header 2025-2026; printf '\nall:\n'; } >"$R/Makefile"
printf 'all:\n' >"$R/Makefile.sample"
printf 'key: value\n' >"$R/config.yaml"
printf '# Title\n' >"$R/README.md"
git -C "$R" add -A

PASS=0
FAIL=0
run() {
	STATUS=0
	(cd "$R" && scripts/check-license-headers.sh) >"$WORK/out" 2>&1 || STATUS=$?
}
check() {
	if eval "$2"; then
		PASS=$((PASS + 1))
		echo "ok   - $1"
	else
		FAIL=$((FAIL + 1))
		echo "FAIL - $1"
		while IFS= read -r line; do printf '       %s\n' "$line"; done <"$WORK/out"
	fi
}
# Adds a tracked file, runs the check, and removes the file again.
with_file() {
	printf '%s' "$2" >"$R/$1"
	git -C "$R" add -- "$1"
	run
	git -C "$R" rm -q --cached -- "$1"
	rm -f -- "$R/$1"
}

run
check "a tree with every header passes (Makefile.sample, YAML and Markdown are not governed)" \
	'[ "$STATUS" -eq 0 ] && grep -q "3 files checked" "$WORK/out"'

with_file .mk/bare.mk $'ifndef X\nendif\n'
check "a snippet without a header fails and is named" '[ "$STATUS" -eq 1 ] && grep -qx "  .mk/bare.mk" "$WORK/out"'

with_file scripts/other.sh "$(header 2026 | sed 's/Roberto Leinardi/Someone Else/')"
check "a header with another copyright holder fails" '[ "$STATUS" -eq 1 ] && grep -qx "  scripts/other.sh" "$WORK/out"'

with_file scripts/gpl.sh $'#!/usr/bin/env bash\n#\n# Copyright (c) 2026 Roberto Leinardi\n#\n# This program is free software: you can redistribute it and/or modify\n'
check "a header from another licence fails" '[ "$STATUS" -eq 1 ] && grep -qx "  scripts/gpl.sh" "$WORK/out"'

with_file scripts/late.sh "$(printf '#!/usr/bin/env bash\n'; for _ in $(seq 1 30); do echo "#"; done; header 2026)"
check "a header below the first 30 lines fails" '[ "$STATUS" -eq 1 ] && grep -qx "  scripts/late.sh" "$WORK/out"'

printf 'echo untracked\n' >"$R/scripts/untracked.sh"
run
check "an untracked file is not checked" '[ "$STATUS" -eq 0 ]'
rm -f "$R/scripts/untracked.sh"

rm -f "$R/.mk/good.mk"
run
check "a tracked file deleted in the working tree is skipped" '[ "$STATUS" -eq 0 ]'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
