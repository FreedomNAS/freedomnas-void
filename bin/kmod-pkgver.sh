#!/bin/sh
set -eu

[ $# -eq 1 ] || { echo "usage: kmod-pkgver.sh <kernel-series>" >&2; exit 2; }
series="$1"

kernel="$(xbps-query -R -p pkgver "$series" || true)"
zfs="$(xbps-query -R -p pkgver zfs || true)"
[ -n "$kernel" ] || { echo "kmod-pkgver.sh: $series is not in the repositories" >&2; exit 1; }
[ -n "$zfs" ] || { echo "kmod-pkgver.sh: zfs is not in the repositories" >&2; exit 1; }

kver="${kernel#"$series"-}"
zver="${zfs#zfs-}"
printf '%s-zfs-%s.%s.%s.%s_1\n' "$series" "${kver%_*}" "${kver##*_}" "${zver%_*}" "${zver##*_}"
