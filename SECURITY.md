# Security policy

## Supported versions

Only the latest release gets security fixes, and consumers pick it up through the moving `v1` tag with `make mk-common-update`.
Released `vX.Y.Z` tags are immutable and are never re-pointed.

## Reporting a vulnerability

Report it privately through GitHub's
[private vulnerability reporting](https://github.com/leinardi/make-common/security/advisories/new), not in a public issue or pull
request. Include the snippet or script, the version, and how a consuming repository would be affected.

This is a project maintained in spare time, so reports are handled on a best-effort basis. You will get an answer in the advisory,
and the fix, once released, is credited there unless you prefer otherwise.

## Scope

In scope: the snippets under `.mk/` and `scripts/bootstrap-mk-common.sh`, which consumers download and run. A way to make them run
something other than what they document (injection through a variable, a download that is not the pinned tag, a write outside
`.mk/`) is a vulnerability.

## Security model

- The bootstrap script resolves `MK_COMMON_VERSION` to a commit, downloads from `raw.githubusercontent.com/<MK_COMMON_REPO>/<commit>/`
  only, installs nothing unless every download succeeded, and records that commit in `.mk/.mk-common-version`.
- Consumers commit the fetched files, so every change arrives as a reviewable diff in the consuming repository.
