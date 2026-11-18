#!/bin/sh
set -eu

[ $# -eq 1 ] || { echo "usage: build-samba-conf.sh <out-dir>" >&2; exit 2; }
out="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"

command -v xbps-create >/dev/null || { echo "build-samba-conf.sh: run it inside a Void container" >&2; exit 1; }

pkgver="freedomnas-samba-conf-$(cat "$root/samba/version")"
share=usr/share/freedomnas/samba

dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT
install -d "$dest/$share"
install -m 644 "$root/samba/smb.conf" "$dest/$share/smb.conf"

cat > "$dest/INSTALL" <<EOF
#!/bin/sh
[ "\$1" = post ] || exit 0
ours=$share/smb.conf
conf=etc/samba/smb.conf
[ -f "\$ours" ] || exit 0
[ -f "\$conf" ] && [ "\$(cat "\$ours")" = "\$(cat "\$conf")" ] && exit 0
if [ -f "\$conf" ] && ! grep -qE '^# (Installed by freedomnas-samba-conf|Written by the FreedomNAS installer)' "\$conf"; then
    cp -p "\$conf" etc/samba/smb.conf.void
fi
install -D -m 644 "\$ours" "\$conf"
exit 0
EOF

cat > "$dest/REMOVE" <<EOF
#!/bin/sh
[ "\$1" = post ] || exit 0
[ "\$4" = yes ] && exit 0
if [ -f etc/samba/smb.conf.void ] && grep -q '^# Installed by freedomnas-samba-conf' etc/samba/smb.conf 2>/dev/null; then
    mv -f etc/samba/smb.conf.void etc/samba/smb.conf
fi
exit 0
EOF
chmod 755 "$dest/INSTALL" "$dest/REMOVE"

mkdir -p "$out"
cd "$out"
xbps-create -A x86_64 -n "$pkgver" \
    -s "FreedomNAS Samba configuration: global settings and usershares only" \
    -l "MPL-2.0" \
    -H "https://github.com/FreedomNAS/freedomnas-void" \
    -D "samba>=0" \
    "$dest"
echo "build-samba-conf.sh: $out/$pkgver.x86_64.xbps"
