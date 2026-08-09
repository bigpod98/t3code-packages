# T3 Code native Linux packaging

This repository provides unofficial Linux packages for T3 Code. It builds from
the canonical `pingdotgg/t3code` repository and forms packages with native
format toolchains:

- Debian/Ubuntu: `dpkg-buildpackage` plus a small, explicit `debhelper` ruleset.
- Fedora/RHEL-family: `rpmbuild` plus a conventional spec file.
- Arch Linux: `makepkg` plus a conventional `PKGBUILD`.
- Alpine Linux: Melange's declarative APK builder, without `APKBUILD` or
  `abuild`.

The Electron application is built once as an unpacked payload. All package
formats consume that exact payload, so adding formats does not compile the
application repeatedly. No package is created by electron-builder, fpm, npm
packaging wrappers, or a package-conversion tool.

## Supported targets

- x86-64: DEB `amd64`, RPM/Arch/APK `x86_64`, Electron `x64`
- ARM64: DEB `arm64`, RPM/APK `aarch64`, Electron `arm64`

The DEB dependency names target Debian 13 and Ubuntu 24.04 or newer. The RPM
dependency names target current Fedora and RHEL-family distributions.
Arch Linux packages target official x86-64 Arch. Alpine APKs target Alpine
3.23 on x86-64 and ARM64.

Electron's upstream Linux binaries use glibc, while Alpine uses musl. The APK
therefore depends on Alpine's `gcompat` compatibility layer and declares its
runtime libraries explicitly. Alpine support is compatibility-based and the CI
installation test is the authoritative support gate for each payload update.

## Build requirements

Building the payload requires Node.js 24.13.1, pnpm 11.10.0, Rust 1.97.1 with the
matching GNU Linux target, ImageMagick, a C/C++ toolchain, and normal Electron
native-module build prerequisites. The source commit and archive SHA-256 are
pinned in `Makefile`.

Package formation additionally requires:

- DEB: `dpkg-dev`, `debhelper`, and `fakeroot`
- RPM: `rpm-build`, `desktop-file-utils`, and `libappstream-glib`
- Arch: Docker and the `archlinux:base-devel` image containing `makepkg`
- Alpine: Melange 0.57.0 and Docker; Melange is used directly rather than
  Alpine's `abuild`

Full package validation additionally uses `lintian`, `rpmlint`, Melange's APK
linter, `namcap`, and Docker. The Docker checks install and smoke-test the
packages in Debian 13, Fedora 43, Alpine 3.23, and Arch containers on the
native build architecture as applicable.

The source build downloads the dependency graph locked by `pnpm-lock.yaml`.
That is appropriate for vendor packages and CI, but it is not acceptable for
an official Debian or Fedora repository build environment. Admission to those
archives would also require vendoring/auditing the Node dependency sources and
fully declaring bundled components.

## Commands

```sh
make payload
make packages
make check
make install-test
```

Outputs are written to `dist/`. To build one format only:

```sh
make deb
make rpm
make arch
make apk
```

`make packages` reuses the same input-keyed `build/payload/<arch>/` directory
for every format. Changing the source, version, timestamp, or toolchain selects
a fresh payload rather than silently reusing incompatible output. On ARM64,
`packages` omits Arch because official Arch Linux is x86-64 only. The Makefile
is orchestration only; the format recipes are [`debian/rules`](debian/rules),
[`rpm/t3code.spec`](rpm/t3code.spec), [`arch/PKGBUILD`](arch/PKGBUILD), and
[`alpine/t3code.yaml`](alpine/t3code.yaml).

The version and source settings can be overridden through the environment or
on the `make` command line. Dynamic builds must supply a full commit SHA. An
empty `SOURCE_SHA256` is supported for exploratory builds that resolve an
immutable commit dynamically; the downloaded archive's digest is still logged.
Automated builds resolve the digest before starting the architecture matrix and
verify every download against it.

```sh
make packages \
  VERSION=2026.8.8 \
  RELEASE=42 \
  PACKAGE_DATE=2026-08-08 \
  SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567 \
  SOURCE_SHA256=
```

## Automated builds

- `Daily main packages` runs every day and on demand. It builds the current
  `pingdotgg/t3code` `main` commit with the calendar version `YYYY.M.D` and uses
  the workflow run number as the package release.
- `Latest stable packages` runs every day and on demand. It resolves the latest
  non-prerelease from `pingdotgg/t3code` and builds that exact release commit.

Both workflows build on native x86-64 and ARM64 Ubuntu runners, form DEB, RPM,
and Melange APK packages from the same per-architecture payload, add an Arch
package on x86-64, and retain the results as workflow artifacts. Every workflow
run is a distinct package release, even when the upstream stable version has
not changed. The workflows lint the packages, install them in Debian, Fedora,
Alpine, and Arch containers as applicable, smoke-test both launchers, and
publish a `SHA256SUMS` file. They do not publish or replace GitHub releases.

## Installed layout

```text
/usr/bin/t3code                         graphical launcher
/usr/bin/t3                             bundled headless server launcher
/usr/lib/t3code/                        Electron application payload
/usr/share/applications/t3code.desktop  desktop and URL-scheme registration
/usr/share/metainfo/                    AppStream metadata
/usr/share/icons/hicolor/               application icon
```

The headless launcher uses Electron's bundled Node mode and loads
`apps/server/dist/bin.mjs` directly from `resources/app.asar`. Electron's Node
APIs treat ASAR archives as virtual directories. This is intentional: the
upstream Linux build only guarantees native modules in `app.asar.unpacked`, not
the server JavaScript entrypoint.

## Updating

For a new T3 Code version:

1. Update `VERSION`, `SOURCE_COMMIT`, `SOURCE_SHA256`, and
   `SOURCE_DATE_EPOCH` in `Makefile`.
2. Update `debian/changelog`, the defaults in `rpm/t3code.spec`,
   `arch/PKGBUILD`, and `alpine/t3code.yaml`, and the AppStream release in
   `packaging/t3code.metainfo.xml`.
3. Rebuild with `make clean packages check` on both supported architectures.
4. Inspect every output and install it in clean target-distribution systems.

The patch in `patches/` only teaches the upstream artifact builder to copy the
directory emitted by electron-builder's `dir` target. It does not delegate DEB
or RPM creation to electron-builder.
