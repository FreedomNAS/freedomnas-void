# freedomnas-void

The OpenZFS kernel modules for the Void edition of FreedomNAS, built for
Void's own kernel and published as a signed xbps repository in Codeberg's
generic package registry.

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

## CI

`.forgejo/workflows/publish-kmod.yml` runs every hour on Codeberg's hosted
runners, in the `ghcr.io/void-linux/void-glibc` container:

| Job | Runner | What |
|-----|--------|------|
| `check` | `codeberg-tiny-lazy` | `bin/missing.sh`: the series whose module for Void's current kernel and `zfs` is not in the registry |
| `build` | `codeberg-medium` | only when one is missing: `bin/build-kmod.sh` per series, then `bin/publish-codeberg.sh` |

A build takes about three minutes on four CPUs. Secrets (organisation
level): `PACKAGE_REGISTRY_USER`, `PACKAGE_REGISTRY_TOKEN` (package scope)
and `VOID_SIGNING_KEY`, the PEM RSA key the repository is signed with.

## Building

Inside a Void container, as root:

```sh
sh bin/build-kmod.sh linux6.18 out
CODEBERG_USER=<user> CODEBERG_TOKEN=<token> VOID_SIGNING_KEY_FILE=<key.pem> sh bin/publish-codeberg.sh
```

`GROUP` is the channel (`dev` by default, `main` for releases). A package
already in the channel is skipped; a package replaced in the index by a
newer one is deleted from the registry.

## On the NAS

```
https://codeberg.org/api/packages/FreedomNAS/generic/freedomnas-void/dev
```

The repository is signed by `FreedomNAS`; `keys/` holds the public key as the
plist xbps keeps in `/var/db/xbps/keys/`, to copy there instead of answering
xbps's import prompt.
