#!/bin/sh
set -eu

GROUP="${GROUP:-dev}"
BASE="${BASE:-https://github.com/FreedomNAS/freedomnas-void/releases/download/xbps-$GROUP}"
root="$(cd "$(dirname "$0")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl -sfL -o "$work/x86_64-repodata" "$BASE/x86_64-repodata" || true

indexed() {
    [ -f "$work/x86_64-repodata" ] || return 1
    xbps-query -i --repository="$work" -s '' | awk '{ print $2 }' | grep -qxF "$1"
}

missing=""
for series in $(cat "$root/series"); do
    pkgver="$(sh "$root/bin/kmod-pkgver.sh" "$series")"
    if indexed "$pkgver"; then echo "$pkgver is published" >&2
    else echo "$pkgver is not published" >&2; missing="$missing $series"; fi
done
pkgver="freedomnas-samba-conf-$(cat "$root/samba/version")"
if indexed "$pkgver"; then echo "$pkgver is published" >&2
else echo "$pkgver is not published" >&2; missing="$missing samba-conf"; fi
echo "${missing# }"
