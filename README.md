# T3 Code native DEB and RPM packaging

This repository provides unofficial Linux packages for T3 Code. It builds from
the canonical `pingdotgg/t3code` repository and forms packages with the
distribution tools themselves:

- Debian/Ubuntu: `dpkg-buildpackage` plus a small, explicit `debhelper` ruleset.
- Fedora/RHEL-family: `rpmbuild` plus a conventional spec file.

The Electron application is built once as an unpacked payload. Both package
formats consume that exact payload, so building DEB and RPM does not compile
the application twice. Neither package is created by electron-builder, fpm,
npm packaging wrappers, or a package-conversion tool.

## Supported targets

- x86-64: Debian `amd64`, RPM `x86_64`, Electron `x64`
- ARM64: Debian/RPM `arm64`/`aarch64`, Electron `arm64`

The DEB dependency names target Debian 13 and Ubuntu 24.04 or newer. The RPM
dependency names target current Fedora and RHEL-family distributions.

## Build requirements

Building the payload requires Node.js 24.13.1, pnpm 11.10.0, Rust 1.97.1 with the
matching GNU Linux target, ImageMagick, a C/C++ toolchain, and normal Electron
native-module build prerequisites. The source commit and archive SHA-256 are
pinned in `Makefile`.

Package formation additionally requires:

- DEB: `dpkg-dev`, `debhelper`, and `fakeroot`
- RPM: Docker; `make rpm` installs `rpm-build`, `desktop-file-utils`, and
  `libappstream-glib` in the pinned Fedora container

Full package validation additionally uses `lintian`, `rpmlint`, and Docker.
The Docker checks install and smoke-test the packages in Debian 13 and Fedora
43 containers on the native build architecture.

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
```

`make packages` reuses the same input-keyed `build/payload/<arch>/` directory
for both formats. Changing the source, version, timestamp, or toolchain selects
a fresh payload rather than silently reusing incompatible output. The Makefile
is orchestration only; the actual native recipes are
[`debian/rules`](debian/rules) and [`rpm/t3code.spec`](rpm/t3code.spec).

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

Both workflows build on native x86-64 and ARM64 Ubuntu runners. They form the
DEB on the host and the RPM in a native Fedora container, both from the same
per-architecture payload, and retain the results as workflow artifacts. Every
workflow run is a distinct package release, even when the upstream stable
version has not changed. The workflows lint the packages, install them in
Debian and Fedora containers, smoke-test both launchers, and publish a
`SHA256SUMS` file. They do not publish or replace GitHub releases.

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
2. Update `debian/changelog`, the version/release in `rpm/t3code.spec`, and the
   AppStream release in `packaging/t3code.metainfo.xml`.
3. Rebuild with `make clean packages check` on both supported architectures.
4. Inspect contents with `dpkg-deb --contents` and `rpm -qlp`, then install in
   clean Debian/Ubuntu and Fedora/RHEL-family test systems.

The patch in `patches/` only teaches the upstream artifact builder to copy the
directory emitted by electron-builder's `dir` target. It does not delegate DEB
or RPM creation to electron-builder.
