#!/bin/sh
set -eu

[ $# -eq 2 ] || { echo "usage: build-kmod.sh <kernel-series> <out-dir>" >&2; exit 2; }
series="$1"
out="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "build-kmod.sh: must run as root inside a Void container" >&2; exit 1; }

xbps-install -Syu xbps
xbps-install -yu
xbps-install -y "$series" "$series-headers" zfs

pkgver="$(sh "$root/bin/kmod-pkgver.sh" "$series")"
kernel="$(xbps-query -p pkgver "$series")"
zfs="$(xbps-query -p pkgver zfs)"
kver="${kernel#"$series"-}"
zver="${zfs#zfs-}"

extra="/usr/lib/modules/$kver/extra"
for m in spl zfs; do
    [ -f "$extra/$m.ko" ] || { echo "build-kmod.sh: dkms left no $extra/$m.ko" >&2; exit 1; }
    magic="$(modinfo -F vermagic "$extra/$m.ko" | awk '{ print $1 }')"
    [ "$magic" = "$kver" ] || { echo "build-kmod.sh: $m.ko is for $magic, not $kver" >&2; exit 1; }
    version="$(modinfo -F version "$extra/$m.ko")"
    [ "$version" = "${zver%_*}-1" ] || { echo "build-kmod.sh: $m.ko is version $version, not ${zver%_*}" >&2; exit 1; }
done

dest="$(mktemp -d)"
trap 'rm -rf "$dest"' EXIT
install -d "$dest$extra"
install -m 644 "$extra/spl.ko" "$extra/zfs.ko" "$dest$extra/"
# zfs regenerates the initramfs before this package is configured, and on an
# update the kernel runs its hooks before it too, so the images they build
# get zfs's dracut module without zfs.ko: run the kernel's post-install hooks
# again here (the initramfs on plain Void, the UKIs on FreedomNAS).
for script in INSTALL REMOVE; do
    cat > "$dest/$script" <<EOF
#!/bin/sh
[ "\$1" = post ] || exit 0
[ "$script" = REMOVE ] && [ "\$4" = yes ] && exit 0
[ -d usr/lib/modules/$kver/kernel ] || exit 0
depmod -a $kver
for hook in etc/kernel.d/post-install/*; do
    [ -x "\$hook" ] && "\$hook" $series $kver
done
exit 0
EOF
    chmod 755 "$dest/$script"
done

mkdir -p "$out"
cd "$out"
xbps-create -A x86_64 -n "$pkgver" \
    -s "OpenZFS ${zver%_*} modules for $kernel" \
    -l "CDDL-1.0" \
    -H "https://codeberg.org/FreedomNAS/freedomnas-void" \
    -D "$kernel $zfs kmod>=0" \
    "$dest"
echo "build-kmod.sh: $out/$pkgver.x86_64.xbps"
