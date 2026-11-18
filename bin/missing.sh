#!/bin/sh
set -eu

GROUP="${GROUP:-dev}"
BASE="${BASE:-https://github.com/FreedomNAS/freedomnas-void/releases/download/xbps-$GROUP}"
root="$(cd "$(dirname "$0")/.." && pwd)"

missing=""
for series in $(cat "$root/series"); do
    file="$(sh "$root/bin/kmod-pkgver.sh" "$series").x86_64.xbps"
    case "$(curl -sL -o /dev/null -w '%{http_code}' -r 0-0 "$BASE/$file")" in
        200|206) echo "$file is published" >&2 ;;
        *) echo "$file is not published" >&2; missing="$missing $series" ;;
    esac
done
file="freedomnas-samba-conf-$(cat "$root/samba/version").x86_64.xbps"
case "$(curl -sL -o /dev/null -w '%{http_code}' -r 0-0 "$BASE/$file")" in
    200|206) echo "$file is published" >&2 ;;
    *) echo "$file is not published" >&2; missing="$missing samba-conf" ;;
esac
echo "${missing# }"
