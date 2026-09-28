#!/usr/bin/env bash
#
# Tests scripts/bootstrap-mk-common.sh offline. A fake `git ls-remote` answers
# from a fixture, and a fake `curl` serves files from fixture directories named
# after the commit SHA in the URL, logging every URL and failing on request.
# Every other git command goes to the real git.
#
# check() takes each condition as a single-quoted string and evals it when the
# check runs, so the expansions inside are meant to be deferred (SC2016), and
# the linter cannot see that variables used only inside them are read (SC2034).
# shellcheck disable=SC2016,SC2034

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/scripts/bootstrap-mk-common.sh"
REAL_GIT=$(command -v git)

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

REPO=leinardi/make-common
SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
TAGOBJ=3333333333333333333333333333333333333333

# Fixtures: two commits, each serving the script under test and two snippets.
for sha in "$SHA1" "$SHA2"; do
	mkdir -p "$WORK/remote/$sha/scripts" "$WORK/remote/$sha/.mk"
	cp "$SCRIPT" "$WORK/remote/$sha/scripts/bootstrap-mk-common.sh"
	echo "# help from $sha" >"$WORK/remote/$sha/.mk/help.mk"
	echo "# go from $sha" >"$WORK/remote/$sha/.mk/go.mk"
done

mkdir -p "$WORK/bin"
cat >"$WORK/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "ls-remote" ]; then
	cat "$WORK/ls-remote"
	exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
cat >"$WORK/bin/curl" <<EOF
#!/usr/bin/env bash
url="" out=""
while [ "\$#" -gt 0 ]; do
	case "\$1" in
	-o) out=\$2; shift 2 ;;
	-*) shift ;;
	*) url=\$1; shift ;;
	esac
done
echo "\$url" >>"$WORK/curl.log"
path=\${url#https://raw.githubusercontent.com/$REPO/}
# A tag URL serves the commit the tag currently points at.
case "\$path" in
v1/*) path="\$(awk '\$2 == "refs/tags/v1" { print \$1; exit }' "$WORK/ls-remote")/\${path#v1/}" ;;
esac
if [ -n "\${FAIL_ON:-}" ] && [ "\${path##*/}" = "\$FAIL_ON" ]; then
	exit 22
fi
[ -f "$WORK/remote/\$path" ] || exit 22
cp "$WORK/remote/\$path" "\$out"
EOF
chmod +x "$WORK/bin/git" "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"

# The consumer repository, with the script under test as its bootstrap.
C="$WORK/consumer"
mkdir -p "$C/scripts"
"$REAL_GIT" init -q "$C"
cp "$SCRIPT" "$C/scripts/bootstrap-mk-common.sh"

bootstrap() {
	: >"$WORK/curl.log"
	STATUS=0
	(cd "$C" && "$C/scripts/bootstrap-mk-common.sh" "$REPO" v1 "$C/.mk" "help.mk go.mk") >"$WORK/out" 2>&1 || STATUS=$?
}
snapshot() { (cd "$C" && find .mk scripts -type f -exec sha256sum {} + | sort) }

PASS=0
FAIL=0
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
no_stage() { ! find "$C/.mk" -maxdepth 1 -name '.mk-common-stage.*' | grep -q .; }

printf '%s\trefs/tags/v1\n' "$SHA1" >"$WORK/ls-remote"
bootstrap
check "a first run installs every file" '[ "$STATUS" -eq 0 ] && grep -q "$SHA1" "$C/.mk/help.mk" && grep -q "$SHA1" "$C/.mk/go.mk"'
check "the version file records the resolved commit" '[ "$(cat "$C/.mk/.mk-common-version")" = "$REPO@v1 $SHA1" ]'
check "downloads use the commit SHA, not the tag" 'grep -q "/$SHA1/" "$WORK/curl.log" && ! grep -q "/v1/" "$WORK/curl.log"'
check "no staging directory is left behind" 'no_stage'

bootstrap
check "an up-to-date normal run downloads nothing" '[ "$STATUS" -eq 0 ] && [ ! -s "$WORK/curl.log" ]'

printf '%s\trefs/tags/v1\n' "$SHA2" >"$WORK/ls-remote"
BEFORE=$(snapshot)
: >"$WORK/curl.log"
STATUS=0
(cd "$C" && MK_COMMON_UPDATE=1 FAIL_ON=go.mk "$C/scripts/bootstrap-mk-common.sh" "$REPO" v1 "$C/.mk" "help.mk go.mk") >"$WORK/out" 2>&1 || STATUS=$?
check "a download failing part-way fails the run" '[ "$STATUS" -ne 0 ]'
check "a failed update changes nothing (script, snippets, version file)" '[ "$(snapshot)" = "$BEFORE" ]'
check "a failed update leaves no staging directory" 'no_stage'

: >"$WORK/curl.log"
STATUS=0
(cd "$C" && MK_COMMON_UPDATE=1 "$C/scripts/bootstrap-mk-common.sh" "$REPO" v1 "$C/.mk" "help.mk go.mk") >"$WORK/out" 2>&1 || STATUS=$?
check "the retried update installs the new commit" '[ "$STATUS" -eq 0 ] && grep -q "$SHA2" "$C/.mk/go.mk" && [ "$(cat "$C/.mk/.mk-common-version")" = "$REPO@v1 $SHA2" ]'

printf '%s\trefs/tags/v1\n%s\trefs/tags/v1^{}\n%s\trefs/tags/other/v1\n' "$TAGOBJ" "$SHA1" "$SHA2" >"$WORK/ls-remote"
rm -f "$C/.mk/.mk-common-version"
bootstrap
check "an annotated tag is peeled to its commit" '[ "$STATUS" -eq 0 ] && [ "$(cat "$C/.mk/.mk-common-version")" = "$REPO@v1 $SHA1" ] && grep -q "/$SHA1/" "$WORK/curl.log"'

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
