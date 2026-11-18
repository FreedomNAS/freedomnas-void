# freedomnas-void

The FreedomNAS packages for Void, the OpenZFS kernel modules built for
Void's own kernel, and the Samba configuration, published as a signed xbps
repository in this GitHub repository's releases.

Void ships OpenZFS as `zfs`, whose module is built by DKMS on the machine
itself, which pulls `dkms`, `gcc` and the kernel headers onto the NAS and
recompiles at every kernel update. Here the module is built once, in CI:

- the NAS installs Void's `zfs` for the userland, the libraries and the
  dracut module, with `ignorepkg=dkms` in `/etc/xbps.d/`, so nothing is
  compiled there;
- it installs `<series>-zfs` from this repository for the modules.

## Packages

One package per kernel series listed in `series` (today `linux6.18`):

```
linux6.18-zfs-<kernel version>.<kernel revision>.<zfs version>.<zfs revision>_<revision>
linux6.18-zfs-6.18.54.1.2.4.4.1_2   # linux6.18-6.18.54_1 + zfs-2.4.4_1
```

`revision` is the packaging revision: raise it when a change to the package
itself has to reach machines that already have the module.

It holds `/usr/lib/modules/<kver>/extra/{spl,zfs}.ko`, runs `depmod` after
install and removal, then runs that kernel's hooks in
`/etc/kernel.d/post-install/` again: `zfs` and, on an update, the kernel build
their images before this package is configured, so without this the
initramfs (on plain Void) or the UKIs (on FreedomNAS) would carry the ZFS
dracut module but no `zfs.ko` and a root on ZFS would not boot. A hook that
must build its image only once per kernel, like the FreedomNAS UKI one, skips
while `/usr/lib/modules/<kver>/extra/zfs.ko` is missing. It depends on the
exact kernel and `zfs` it was built
against. Void builds without `CONFIG_MODVERSIONS`, so a module loads only in
that kernel: when Void publishes a newer kernel or `zfs` before the module
for it is here, xbps refuses the update ("breaks installed pkg") and the
system keeps booting the kernel it has.

Install the series package (`linux6.18`), not the `linux` meta package: when
Void moves `linux` to a new series, its kernel would get no module until the
series is added to `series`.

### freedomnas-samba-conf

```
freedomnas-samba-conf-<version>   # samba/version, e.g. 1.0_1
```

Void's `samba` installs Samba's example `smb.conf`, with a writable `[homes]`
share and `[printers]`. FreedomNAS creates every share as a usershare, so it
needs only the `[global]` settings in `samba/smb.conf`.

`/etc/samba/smb.conf` belongs to `samba` as a configuration file, and xbps
refuses two packages owning one file: the package ships ours as
`/usr/share/freedomnas/samba/smb.conf`, depends on `samba`, and its INSTALL
script copies it over Void's, kept as `/etc/samba/smb.conf.void`. When `samba`
is updated, xbps finds the file changed, keeps it, and writes Void's as
`smb.conf.new-<version>`. Removing the package puts Void's back. Raise
`samba/version` to ship a new `smb.conf`: the INSTALL script replaces an older
one of ours.

### freedomnas-core, -profiles, -docs, -webui, -installer

```
freedomnas-core-0.9.11_1                   # release, from the vX.Y.Z tag
freedomnas-core-0.9.11.20261008164152_1    # snapshot, commit date and time (UTC)
```

`bin/build-freedomnas.sh` builds them from checkouts of the component
repositories, laid out as the .deb and the FreeBSD package lay them out
under `/usr/lib/freedomnas` (freedomnas-profiles' `paths.install_root`);
`bin/version.sh` takes the version from each component's
`debian/changelog`. xbps refuses `+` and `-` in a version, so a snapshot
appends its stamp as one more number: `0.9.11.<stamp>` sorts after
`0.9.11` and below `0.9.12`. They are `noarch`. freedomnas-core's `.pth`
lives in the site-packages of the Python it was built with, so it depends
on that minor version (`python3>=3.14_1<3.15_1`): a new Python on Void waits
for a rebuild. freedomnas-installer carries `CHANNEL`: `main` in a release,
`dev` in a snapshot. The documentation is built with mkdocs from
freedomnas-docs' `requirements.txt` in a virtual environment, since Void
does not package it.

The installer installs the first four (installer-void.json's
`installer_meta.core_packages` and packages/core.json) from the group of its
channel: `/etc/xbps.d/10-freedomnas.conf` names the release `xbps-main` or
`xbps-dev`.

## CI

The repository is kept as the assets of this GitHub repository's releases:
`xbps-dev` and `xbps-main` (ADR-003 in freedomnas-specs).

`.github/workflows/publish-kmod.yml` runs every hour, on every push to `dev`
and by hand, in the `ghcr.io/void-linux/void-glibc` container:

| Job | What |
|-----|------|
| `check` | `bin/missing.sh`: the series whose module for Void's current kernel and `zfs` is not in the release, and `samba-conf` when `freedomnas-samba-conf` at `samba/version` is not |
| `build` | only when one is missing: `bin/build-kmod.sh` per series, `bin/build-samba-conf.sh` for `samba-conf`, then `bin/publish-github.sh` |

Both releases, `xbps-dev` and `xbps-main`, get every module and Samba
configuration: images and systems on the main channel read `xbps-main`.

`.github/workflows/publish-freedomnas.yml` builds the FreedomNAS packages
with `ref` (`main`: the newest `vX.Y.Z` tag of freedomnas-core, into
`xbps-main`; `dev`: snapshots into `xbps-dev`). `gather-pushes` starts it
ten minutes after the last push to a component (see freedomnas-deb's
`docs/ci-setup.md`); it also runs every night and by hand. A version
already published is skipped, and `bin/publish-github.sh` removes from the
release what the new index replaced.

A build takes about three minutes. The organisation secret
`VOID_SIGNING_KEY` is the PEM RSA key the repository is signed with. The
Forgejo workflows under `.forgejo/` are switched off.

## Building

Inside a Void container, as root:

```sh
sh bin/build-kmod.sh linux6.18 out
sh bin/build-samba-conf.sh out
SNAPSHOT=1 sh bin/build-freedomnas.sh <dir with the component checkouts> out
GH_TOKEN=<token> VOID_SIGNING_KEY_FILE=<key.pem> sh bin/publish-github.sh
```

`GROUP` is the channel (`dev` by default, `main` for releases). A package
already in the channel is skipped; a package replaced in the index by a
newer one is deleted from the release.

## On the NAS

```
https://github.com/FreedomNAS/freedomnas-void/releases/download/xbps-dev
```

The repository is signed by `FreedomNAS`; `keys/` holds the public key as the
plist xbps keeps in `/var/db/xbps/keys/`, to copy there instead of answering
xbps's import prompt.
