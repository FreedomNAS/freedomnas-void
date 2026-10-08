#!/bin/sh
# Print the xbps version (version_revision) a FreedomNAS package is built with.
#
#   bin/version.sh ../freedomnas-core              -> 0.9.11_1
#   bin/version.sh --snapshot ../freedomnas-core   -> 0.9.11.20261008163001_1
#
# The base version is the upstream half of debian/changelog, the number
# freedomnas-deb and freedomnas-freebsd publish too, so a release carries one
# version everywhere. A snapshot appends the commit's UTC date and time as one
# more number: xbps compares versions number by number, so
# `0.9.11.<stamp>` sorts after `0.9.11` and below `0.9.12`. xbps refuses `+`
# and `-` in a version, which is why this is not Debian's `0.9.11+<stamp>`.
set -eu

snapshot=0
if [ "${1:-}" = "--snapshot" ]; then
    snapshot=1
    shift
fi
src="${1:?usage: version.sh [--snapshot] <source-dir>}"
[ -f "$src/debian/changelog" ] || { echo "version.sh: no debian/changelog in $src" >&2; exit 1; }

base="$(sed -n '1s/^[^(]*(\([^)]*\)).*/\1/p' "$src/debian/changelog")"
upstream="${base%-*}"
[ -n "$upstream" ] || { echo "version.sh: cannot read the version from $src/debian/changelog" >&2; exit 1; }

if [ "$snapshot" = 0 ]; then
    printf '%s_1\n' "$upstream"
    exit 0
fi

stamp="$(TZ=UTC git -C "$src" log -1 --format=%cd --date=format-local:%Y%m%d%H%M%S)"
printf '%s.%s_1\n' "$upstream" "$stamp"
