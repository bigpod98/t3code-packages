# T3 Code packages for Debian, Fedora, and Arch Linux

The daily and stable workflows publish unofficial Linux packages to the
[stable registry](https://git.tuxbase.com/t3code-stable/-/packages) and the
[daily registry](https://git.tuxbase.com/t3code-daily/-/packages).

The recipes build from the canonical `pingdotgg/t3code` repository using
each distribution’s native packaging tools.

- Debian/Ubuntu: `dpkg-buildpackage` plus a small, explicit `debhelper` ruleset.
- Fedora RPMs use `rpmbuild`.
- Arch Linux packages use `makepkg` and a PKGBUILD.

Each runner builds the Electron payload once and shares it across its package formats.

## Supported targets

| CPU | Packages | Installation tests |
| --- | --- | --- |
| x86-64 | DEB, RPM, Arch (`.pkg.tar.zst`) | Debian 13, Fedora 44 and 45, Arch Linux |
| ARM64 | DEB, RPM | Debian 13, Fedora 44 and 45 |

The DEB targets Debian 13 and Ubuntu 24.04 or newer. Fedora 45 is the RPM
build environment.

## Build requirements

Building the payload requires Node.js 26.13.1, pnpm 12.14.0, Rust 1.100.0 with the
matching GNU Linux target, ImageMagick, a C/C++ toolchain, and normal Electron
native-module build prerequisites. The source commit and archive SHA-256 are
pinned in `Makefile`.

Package formation additionally requires:

- DEB: `dpkg-dev`, `debhelper`, and `fakeroot`
- RPM: Docker; `make rpm` installs `rpm-build`, `desktop-file-utils`, and
  `libappstream-glib` in the Fedora 45 container
- Arch Linux (x86-64) uses Docker and the official `archlinux:base-devel` image.
  The recipe packages the local payload and installs both launchers.

Full package validation also uses `lintian`, `rpmlint`, GNU tar with `zstd`,
and Docker.
The Docker checks install each package on the distributions listed above and
exercise the bundled runtime and headless launcher.

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
make arch   # x86-64
```

`make packages` reuses the same input-keyed `build/payload/<arch>/` directory
for all supported formats. Changing the source, version, timestamp, or toolchain selects
a fresh payload rather than silently reusing incompatible output. Changes to
the Makefile also invalidate an existing payload stamp so recipe edits cannot
silently reuse old output. The Makefile is orchestration only; the actual
native recipes are
[`debian/rules`](debian/rules), [`rpm/t3code.spec`](rpm/t3code.spec), and
[`arch/PKGBUILD`](arch/PKGBUILD).

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

Each architecture job adds 32 GiB of swap, limits the Node heap to 4 GiB,
and limits native Rayon transforms to one thread with two glibc allocator
arenas, leaving headroom for native bundler allocations and the Actions runner.
Web source maps are disabled
with upstream's `T3CODE_WEB_SOURCEMAP=false` setting to reduce build memory and
package size. Manual runs on other branches build and validate artifacts;
Forgejo publication runs only from the default branch.

Both workflows resolve the exact Node.js and pnpm versions from the selected
upstream commit, so upstream toolchain changes do not leave CI on old pins.
Native Ubuntu 24.04 runners build both CPU architectures to preserve the glibc
baseline. The DEB is formed on the host. Fedora and Arch packages are formed
in native containers. Ubuntu 26.04 runs the resolution and publication jobs.
The workflows retain the results as artifacts and publish the validated packages
to `git.tuxbase.com`. Daily packages belong to the
`t3code-daily` organization; stable packages belong to `t3code-stable`. Every
workflow run is a distinct package release, even when the upstream stable
version has not changed. The workflows lint the packages, install them in
target distro containers, smoke-test both launchers, and include a
`SHA256SUMS-<arch>` file in each artifact. The publish job verifies both
manifests before uploading to Forgejo.

Forgejo publication requires a GitHub Actions secret named `FORGEJO_TOKEN`.
Its Forgejo user must have package write access to both organizations, and the
token must have the `write:package` scope. Package uploads begin only after both
architecture jobs succeed. Publication fails closed if an identical package
identity already exists because Forgejo's conflict response does not prove that
the existing and newly built files have the same contents. Delete packages from
a partial publication before rerunning the same workflow run.

RPM uploads request Forgejo's server-side signing. Forgejo signs each stored RPM
with the package owner's registry key, matching the `gpgkey` in its generated
`.repo` file. The locally built workflow artifacts remain unsigned. Forgejo
signs Debian repository metadata itself, so DEB uploads do not request package
signing; APT clients trust the owner key from the registry's `repository.key`
endpoint.

Package managers can use the following stable repository endpoints.

```text
APT: https://git.tuxbase.com/api/packages/t3code-stable/debian stable main
RPM: https://git.tuxbase.com/api/packages/t3code-stable/rpm.repo
```

The daily equivalents use owner `t3code-daily`, APT distribution `daily`, and
`https://git.tuxbase.com/api/packages/t3code-daily/rpm.repo`.

Arch packages use the Forgejo group matching the channel. Add the following
entry to `/etc/pacman.conf` for stable builds.

```ini
[t3code-stable.stable.git.tuxbase.com]
SigLevel = Required
Server = https://git.tuxbase.com/api/packages/t3code-stable/arch/stable/$arch
```

For daily builds, replace `stable` with `daily` in the entry. Import and trust the package owner's key from
`https://git.tuxbase.com/api/packages/<owner>/arch/repository.key` using the
instructions on the package's Forgejo page, then run `pacman -Syu t3code`.

## Installed layout

```text
/usr/bin/t3code                         graphical launcher
/usr/bin/t3                             bundled headless server launcher
/usr/lib/t3code/                        Electron application payload
/usr/share/applications/t3code.desktop  desktop and URL-scheme registration
/usr/share/metainfo/                    AppStream metadata
/usr/share/icons/hicolor/               application icon
```

The packages install the upstream MIT license together with the Electron and
Chromium notices, a generated inventory of production dependency licenses, and
a third-party licensing guide. License files for bundled npm dependencies are
retained inside the Electron application archive and its unpacked native-module
tree.

The headless launcher uses Electron's bundled Node mode and loads
`apps/server/dist/bin.mjs` directly from `resources/app.asar`. Electron's Node
APIs treat ASAR archives as virtual directories. This is intentional: the
upstream Linux build only guarantees native modules in `app.asar.unpacked`, not
the server JavaScript entrypoint.

## Updating

For a new T3 Code version:

1. Update `VERSION`, `PACKAGE_DATE`, `SOURCE_COMMIT`, `SOURCE_SHA256`, and
   `SOURCE_DATE_EPOCH` in `Makefile`.
2. Update `debian/changelog`, the defaults in `rpm/t3code.spec` and `arch/PKGBUILD`, and the
   AppStream release in `packaging/t3code.metainfo.xml`. Update the spec's fallback
   Electron version for standalone builds. The Makefile reads the version directly from the staged runtime.
3. Rebuild with `make clean packages check` on both supported architectures.
4. Inspect contents with `dpkg-deb --contents`, `rpm -qlp`, and `tar -tf`.
   Run `make install-test` for the supported target distributions.

The packaging patches disable the memory-intensive React Compiler optimization
and exclude unused `node-pty` Linux prebuilds. Upstream
now copies directory artifacts from electron-builder's `dir` target itself.
Linux uses the module rebuilt in `build/Release`;
shipping prebuilds for other architectures breaks native dependency scanning.
DEB dependency scanning excludes only the private `ffi-rs`, `fff`, and `koffi`
musl fallbacks, which are not loaded on glibc systems. RPM already excludes private musl
fallbacks from automatic dependency generation.
