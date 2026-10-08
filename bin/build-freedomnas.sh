#!/bin/sh
# Build the FreedomNAS packages for Void from checkouts of the component
# repositories.
#
#   bin/build-freedomnas.sh <src-root> <out-dir>              # release, 0.9.11_1
#   SNAPSHOT=1 bin/build-freedomnas.sh <src-root> <out-dir>   # 0.9.11.<stamp>_1
#   bin/build-freedomnas.sh <src-root> <out-dir> freedomnas-webui
#
# <src-root> holds freedomnas-core, -profiles, -docs, -webui and -installer.
# Nothing is compiled but the documentation, which mkdocs turns into a static
# site; the rest is Python and JSON, laid out the way the .deb, the FreeBSD
# package and the Gentoo ebuild lay it out, under paths.install_root of
# freedomnas-profiles' os/os-void.json. freedomnas-core is not a wheel: the
# package directory goes under <root>/core and a .pth file puts it on
# sys.path, as every edition does.
#
# The .pth file lives in the site-packages of the Python this builds with, so
# freedomnas-core depends on that minor version: when Void moves python3 to a
# new one, xbps holds the update back until a rebuild ships the .pth there.
#
# Runs as root inside a Void container (xbps-create, python3, git, findutils; mkdocs from
# freedomnas-docs/requirements.txt in a virtual environment for the docs).
set -eu

[ $# -ge 2 ] || { echo "usage: build-freedomnas.sh <src-root> <out-dir> [component...]" >&2; exit 2; }
SRC_ROOT="$(cd "$1" && pwd)"
OUT="$2"
shift 2
COMPONENTS="${*:-freedomnas-profiles freedomnas-core freedomnas-docs freedomnas-webui freedomnas-installer}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for tool in xbps-create python3 git find; do
    command -v "$tool" >/dev/null || { echo "build-freedomnas.sh: $tool not found — run it inside a Void container" >&2; exit 1; }
done

ROOT="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["paths"]["install_root"])' \
    "$SRC_ROOT/freedomnas-profiles/os/os-void.json")"
SITE_DIR="$(python3 -c 'import sysconfig; print(sysconfig.get_path("purelib"))')"
PYMINOR="$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')"
PYNEXT="$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1] + 1}")')"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

version_of() {
    sh "$REPO_DIR/bin/version.sh" ${SNAPSHOT:+--snapshot} "$SRC_ROOT/$1"
}

stage_profiles() {
    install -d "$1$ROOT/profiles"
    ( cd "$2" && cp -R os init installer storage network shares users packages assets "$1$ROOT/profiles/" )
}

stage_core() {
    install -d "$1$ROOT/core/freedomnas" "$1$SITE_DIR" "$1/usr/bin"
    ( cd "$2" && cp -R *.py modules "$1$ROOT/core/freedomnas/" )
    rm -f "$1$ROOT/core/freedomnas/conftest.py"
    echo "$ROOT/core" > "$1$SITE_DIR/freedomnas-core.pth"
    install -m 755 "$2/bin/freedomnas" "$1/usr/bin/freedomnas"
}

stage_docs() {
    [ -x "$WORK/mkdocs/bin/mkdocs" ] || {
        python3 -m venv "$WORK/mkdocs"
        "$WORK/mkdocs/bin/pip" install --quiet -r "$2/requirements.txt"
    }
    install -d "$1$ROOT/docs"
    FREEDOMNAS_DOCS_VERSION="$label" "$WORK/mkdocs/bin/mkdocs" build --quiet \
        --config-file "$2/mkdocs.yml" --site-dir "$1$ROOT/docs"
}

stage_webui() {
    install -d "$1$ROOT/webui/bin"
    ( cd "$2" && cp -R api frontend websocket "$1$ROOT/webui/" )
    echo "$label" > "$1$ROOT/webui/VERSION"
    ln -s ../../profiles/assets/firstboot.sh "$1$ROOT/webui/bin/firstboot.sh"
    ln -s ../../profiles/assets/supervisor.sh "$1$ROOT/webui/bin/supervisor.sh"
}

stage_installer() {
    install -d "$1$ROOT/installer/lib" "$1/usr/bin"
    install -m 755 "$2/setup.py" "$1$ROOT/installer/setup.py"
    install -m 644 "$2"/lib/*.py "$1$ROOT/installer/lib/"
    if [ -n "${SNAPSHOT:-}" ]; then echo dev; else echo main; fi > "$1$ROOT/installer/CHANNEL"
    ln -s "$ROOT/installer/setup.py" "$1/usr/bin/freedomnas-install"
}

for name in $COMPONENTS; do
    src="$SRC_ROOT/$name"
    [ -d "$src" ] || { echo "build-freedomnas.sh: no checkout at $src" >&2; exit 1; }

    version="$(version_of "$name")"
    base="$(sh "$REPO_DIR/bin/version.sh" "$src")"
    base="${base%_*}"
    case "${version%_*}" in
        "$base") label="$base" ;;
        *) label="$base+${version#"$base".}"; label="${label%_*}" ;;
    esac
    depver="$base"

    case "$name" in
    freedomnas-profiles)
        short="FreedomNAS OS profiles, the JSON translator layer"
        deps=""
        ;;
    freedomnas-core)
        short="FreedomNAS core engine, OS-agnostic storage appliance"
        deps="freedomnas-profiles>=$depver python3>=${PYMINOR}_1<${PYNEXT}_1 python3-yaml>=0 python3-cryptography>=0"
        ;;
    freedomnas-docs)
        short="FreedomNAS documentation, for reading offline in the WebUI"
        deps=""
        ;;
    freedomnas-webui)
        short="FreedomNAS web interface"
        deps="freedomnas-core>=$depver freedomnas-profiles>=$depver freedomnas-docs>=$depver python3-fastapi>=0 python3-uvicorn>=0 python3-websockets>=0 python3-Jinja2>=0 python3-pam>=0 python3-yaml>=0"
        ;;
    freedomnas-installer)
        short="Profile-driven FreedomNAS installer"
        deps="freedomnas-core>=$depver freedomnas-profiles>=$depver dialog>=0 gptfdisk>=0 dosfstools>=0 dracut>=0 efibootmgr>=0 parted>=0 curl>=0"
        ;;
    *)
        echo "build-freedomnas.sh: unknown component $name" >&2
        exit 1
        ;;
    esac

    echo "==> $name-$version ($ROOT)"
    stage="$WORK/$name"
    install -d "$stage"
    "stage_${name#freedomnas-}" "$stage" "$src"
    find "$stage" -name __pycache__ -type d -prune -exec rm -rf {} +
    python3 -m compileall -q --invalidation-mode checked-hash -s "$stage" -p / "$stage$ROOT" >/dev/null
    if [ -f "$src/README.md" ]; then
        install -D -m 644 "$src/README.md" "$stage/usr/share/doc/$name/README.md"
    fi

    # shellcheck disable=SC2086
    ( cd "$OUT" && xbps-create -A noarch -n "$name-$version" -s "$short" -l "MPL-2.0" \
        -H "https://codeberg.org/FreedomNAS/$name" \
        -m "FreedomNAS Team <dev@freedomnas.io>" \
        ${deps:+-D "$deps"} "$stage" )
done
ls -1 "$OUT"/freedomnas-*.noarch.xbps
