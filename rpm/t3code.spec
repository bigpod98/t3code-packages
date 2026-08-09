%global debug_package %{nil}
%global __strip /bin/true
%{!?package_version:%global package_version 0.0.32}
%{!?package_release:%global package_release 1}

Name:           t3code
Version:        %{package_version}
Release:        %{package_release}%{?dist}
Summary:        Desktop interface for AI coding agents

%{!?_metainfodir:%global _metainfodir %{_datadir}/metainfo}
%global t3code_appdir %{_prefix}/lib/t3code

License:        MIT
URL:            https://t3.codes/
Source0:        %{name}-payload-%{version}-%{_arch}.tar.gz
Source1:        t3code
Source2:        t3
Source3:        t3code.desktop
Source4:        t3code.metainfo.xml

ExclusiveArch:  x86_64 aarch64
BuildRequires:  desktop-file-utils
BuildRequires:  libappstream-glib

Requires:       alsa-lib
Requires:       at-spi2-core
Requires:       gtk3
Requires:       libnotify
Requires:       libsecret
Requires:       libuuid
Requires:       libXScrnSaver
Requires:       libXtst
Requires:       mesa-libgbm
Requires:       nss
Requires:       xdg-utils

# T3 Code's upstream build has no supported system-library mode for its
# Electron and npm dependency graph. Keep the bundling visible to RPM tooling.
Provides:       bundled(electron) = 41.5.0

%description
T3 Code controls coding agents installed on the local machine, including
Codex, Claude, Cursor, Grok Build, and OpenCode. This package contains both
the graphical t3code command and the bundled headless t3 server command.

%prep
%setup -q -c -T
tar --extract --gzip --file %{SOURCE0}

%build

%install
install -d %{buildroot}%{t3code_appdir}
cp -a . %{buildroot}%{t3code_appdir}/
install -D -m 0755 %{SOURCE1} %{buildroot}%{_bindir}/t3code
install -D -m 0755 %{SOURCE2} %{buildroot}%{_bindir}/t3
desktop-file-install --dir=%{buildroot}%{_datadir}/applications %{SOURCE3}
install -D -m 0644 %{SOURCE4} \
  %{buildroot}%{_metainfodir}/com.t3tools.t3code.metainfo.xml
install -D -m 0644 t3code.png \
  %{buildroot}%{_datadir}/icons/hicolor/1024x1024/apps/t3code.png
install -D -m 0644 LICENSE.t3code \
  %{buildroot}%{_licensedir}/%{name}/LICENSE
rm -f %{buildroot}%{t3code_appdir}/t3code.png
rm -f %{buildroot}%{t3code_appdir}/LICENSE.t3code
chmod 4755 %{buildroot}%{t3code_appdir}/chrome-sandbox

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/t3code.desktop
appstream-util validate-relax --nonet \
  %{buildroot}%{_metainfodir}/com.t3tools.t3code.metainfo.xml
test -x %{buildroot}%{t3code_appdir}/t3code
test -f %{buildroot}%{t3code_appdir}/resources/app.asar
test -x %{buildroot}%{t3code_appdir}/resources/resource-monitor/t3-resource-monitor
test -u %{buildroot}%{t3code_appdir}/chrome-sandbox
ELECTRON_RUN_AS_NODE=1 %{buildroot}%{t3code_appdir}/t3code -e \
  'const fs = require("node:fs"); const entry = process.argv[1]; if (!fs.statSync(entry).isFile()) process.exit(1);' \
  %{buildroot}%{t3code_appdir}/resources/app.asar/apps/server/dist/bin.mjs

%files
%license %{_licensedir}/%{name}/LICENSE
%{_bindir}/t3
%{_bindir}/t3code
%{t3code_appdir}/
%{_datadir}/applications/t3code.desktop
%{_datadir}/icons/hicolor/1024x1024/apps/t3code.png
%{_metainfodir}/com.t3tools.t3code.metainfo.xml

%changelog
* Fri Aug 07 2026 Primoz Ajdisek <bigpod@bigpod.si> - 0.0.32-1
- Initial native RPM recipe based on the upstream Linux payload.
