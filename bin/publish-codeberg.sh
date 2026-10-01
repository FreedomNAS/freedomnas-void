#!/bin/sh
set -eu

OWNER="${CODEBERG_OWNER:-FreedomNAS}"
GROUP="${GROUP:-dev}"
BASE="${BASE:-https://codeberg.org/api/packages/$OWNER/generic/freedomnas-void/$GROUP}"
ARCH=x86_64
REPODATA="$ARCH-repodata"

root="$(cd "$(dirname "$0")/.." && pwd)"

: "${CODEBERG_USER:?set CODEBERG_USER to your Codeberg username}"
: "${CODEBERG_TOKEN:?set CODEBERG_TOKEN to a token with the package scope}"
: "${VOID_SIGNING_KEY_FILE:?set VOID_SIGNING_KEY_FILE to the PEM private key}"
for tool in curl xbps-rindex xbps-query; do
    command -v "$tool" >/dev/null || { echo "publish-codeberg.sh: $tool not found" >&2; exit 1; }
done

auth() { printf 'user = "%s:%s"\n' "$CODEBERG_USER" "$CODEBERG_TOKEN"; }

published() {
    case "$(curl -s -o /dev/null -w '%{http_code}' -r 0-0 "$BASE/$1")" in
        200|206) return 0 ;;
        *) return 1 ;;
    esac
}

put() {
    status="$(auth | curl --config - -s -S -o /dev/null -w '%{http_code}' --upload-file "$1" "$BASE/$2")"
    case "$status" in
        200|201) echo "    uploaded $2" ;;
        *) echo "publish-codeberg.sh: upload of $2: HTTP $status" >&2; return 1 ;;
    esac
}

delete() {
    status="$(auth | curl --config - -s -S -o /dev/null -w '%{http_code}' -X DELETE "$BASE/$1")"
    case "$status" in
        200|204|404) ;;
        *) echo "publish-codeberg.sh: delete of $1: HTTP $status" >&2; return 1 ;;
    esac
}

index_files() {
    [ -f "$1/$REPODATA" ] || return 0
    xbps-query -i --repository="$1" -s '' | awk -v a="$ARCH" '{ print $2 "." a ".xbps" }' | sort
}

if [ "$#" -gt 0 ]; then
    PKGS="$*"
else
    PKGS=""
    for pkg in "$root"/out/*."$ARCH".xbps; do
        [ -f "$pkg" ] && PKGS="$PKGS $pkg"
    done
fi
[ -n "$PKGS" ] || { echo "publish-codeberg.sh: no package in out/" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

new=""
for pkg in $PKGS; do
    name="$(basename "$pkg")"
    if published "$name"; then
        echo "==> $name is already published"
        continue
    fi
    cp "$pkg" "$work/$name"
    new="$new $work/$name"
done

if [ -z "$new" ]; then
    echo "Nothing new to publish to $BASE."
    exit 0
fi

curl -sf -o "$work/$REPODATA" "$BASE/$REPODATA" || rm -f "$work/$REPODATA"
index_files "$work" > "$work/before"

xbps-rindex -a $new
xbps-rindex --sign --signedby "FreedomNAS" --privkey "$VOID_SIGNING_KEY_FILE" "$work"
xbps-rindex --sign-pkg --privkey "$VOID_SIGNING_KEY_FILE" $new
index_files "$work" > "$work/after"

for pkg in $new; do
    echo "==> $(basename "$pkg")"
    put "$pkg" "$(basename "$pkg")"
    put "$pkg.sig2" "$(basename "$pkg").sig2"
done

echo "==> $REPODATA"
delete "$REPODATA"
put "$work/$REPODATA" "$REPODATA"

comm -23 "$work/before" "$work/after" | while read -r old; do
    echo "==> removing superseded $old"
    delete "$old"
    delete "$old.sig2"
done

echo "Published to $BASE."
