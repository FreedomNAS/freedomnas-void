#!/bin/sh
# Publish the packages in out/ to the xbps repository kept as the assets of
# the release xbps-<GROUP> of this GitHub repository:
#
#   https://github.com/FreedomNAS/freedomnas-void/releases/download/xbps-dev
#
# Only packages the repodata does not list yet are signed and uploaded (a
# file uploaded but missing from the repodata is added again); the repodata
# is rewritten with xbps-rindex, and the packages it no longer lists are
# deleted.
#
#   GH_TOKEN=<token> GROUP=dev|main VOID_SIGNING_KEY_FILE=<key.pem> sh bin/publish-github.sh [<package>...]
set -eu

GH_REPO="${GH_REPO:-FreedomNAS/freedomnas-void}"
GROUP="${GROUP:-dev}"
TAG="xbps-$GROUP"
BASE="https://github.com/$GH_REPO/releases/download/$TAG"
ARCH=x86_64
REPODATA="$ARCH-repodata"
export GH_REPO

root="$(cd "$(dirname "$0")/.." && pwd)"

: "${GH_TOKEN:?set GH_TOKEN to a token that can write this repository's releases}"
: "${VOID_SIGNING_KEY_FILE:?set VOID_SIGNING_KEY_FILE to the PEM private key}"
for tool in curl gh xbps-rindex xbps-query; do
    command -v "$tool" >/dev/null || { echo "publish-github.sh: $tool not found" >&2; exit 1; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" --latest=false \
    --title "xbps repository ($GROUP)" \
    --notes "The FreedomNAS xbps repository for Void, $GROUP channel: repository=$BASE"
gh release view "$TAG" --json assets --jq '.assets[].name' > "$work/assets"

published() { grep -qxF "$1" "$work/assets"; }

put() {
    mkdir -p "$work/up"
    cp "$1" "$work/up/$2"
    gh release upload "$TAG" "$work/up/$2" --clobber >/dev/null
    rm -f "$work/up/$2"
    echo "    uploaded $2"
}

delete() {
    published "$1" || return 0
    gh release delete-asset "$TAG" "$1" -y >/dev/null
}

index_files() {
    [ -f "$1/$REPODATA" ] || return 0
    xbps-query -i --repository="$1" -s '' | awk '{ print $2 }' | while read -r pkgver; do
        echo "$pkgver.$(xbps-query -i --repository="$1" -R --property=architecture "$pkgver").xbps"
    done | sort
}

if [ "$#" -gt 0 ]; then
    PKGS="$*"
else
    PKGS=""
    for pkg in "$root"/out/*."$ARCH".xbps "$root"/out/*.noarch.xbps; do
        [ -f "$pkg" ] && PKGS="$PKGS $pkg"
    done
fi
[ -n "$PKGS" ] || { echo "publish-github.sh: no package in out/" >&2; exit 1; }

if published "$REPODATA"; then curl -sfL -o "$work/$REPODATA" "$BASE/$REPODATA"; fi
index_files "$work" > "$work/before"

new=""
for pkg in $PKGS; do
    name="$(basename "$pkg")"
    if grep -qxF "$name" "$work/before"; then
        echo "==> $name is already published"
        continue
    fi
    case "$name" in
        *[!A-Za-z0-9._+-]*) echo "publish-github.sh: $name has a character GitHub renames" >&2; exit 1 ;;
    esac
    cp "$pkg" "$work/$name"
    new="$new $work/$name"
done

if [ -z "$new" ]; then
    echo "Nothing new to publish to $BASE."
    exit 0
fi

xbps-rindex -f -a $new
xbps-rindex --sign --signedby "FreedomNAS" --privkey "$VOID_SIGNING_KEY_FILE" "$work"
xbps-rindex --sign-pkg --privkey "$VOID_SIGNING_KEY_FILE" $new
index_files "$work" > "$work/after"

for pkg in $new; do
    echo "==> $(basename "$pkg")"
    put "$pkg" "$(basename "$pkg")"
    put "$pkg.sig2" "$(basename "$pkg").sig2"
done

echo "==> $REPODATA"
put "$work/$REPODATA" "$REPODATA"

comm -23 "$work/before" "$work/after" | while read -r old; do
    echo "==> removing superseded $old"
    delete "$old"
    delete "$old.sig2"
done

echo "Published to $BASE."
