SHELL := /bin/bash
.DEFAULT_GOAL := help
.DELETE_ON_ERROR:

NAME := t3code
VERSION ?= 0.0.32
RELEASE ?= 1
PACKAGE_DATE ?= 2026-08-07
NODE_VERSION ?= 24.13.1
PNPM_VERSION ?= 11.10.0
RUST_VERSION ?= 1.97.1
FEDORA_IMAGE ?= fedora:43

SOURCE_REPOSITORY ?= https://github.com/pingdotgg/t3code
SOURCE_COMMIT ?= 239ef1c54df2f657912ccb5b8e25193d49d90417
SOURCE_SHA256 ?= d2c4dc5f25df63b399a3fea454ea5bbb0bab367c17498fce8b3cac549fff5082
SOURCE_DATE_EPOCH ?= 1786100076

BUILD_DIR := $(CURDIR)/build
DIST_DIR := $(CURDIR)/dist
DOWNLOAD_DIR := $(BUILD_DIR)/downloads
SOURCE_DIR := $(BUILD_DIR)/source/$(NAME)-$(SOURCE_COMMIT)
SOURCE_ARCHIVE := $(DOWNLOAD_DIR)/$(NAME)-$(SOURCE_COMMIT).tar.gz
SOURCE_STAMP := $(SOURCE_DIR)/.packaging-source-ready

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),x86_64)
  ELECTRON_ARCH := x64
  DEB_ARCH := amd64
  RPM_ARCH := x86_64
  UNPACKED_DIR := linux-unpacked
else ifeq ($(HOST_ARCH),aarch64)
  ELECTRON_ARCH := arm64
  DEB_ARCH := arm64
  RPM_ARCH := aarch64
  UNPACKED_DIR := linux-arm64-unpacked
else
  $(error Unsupported host architecture '$(HOST_ARCH)'; supported: x86_64, aarch64)
endif

TOOLCHAIN_KEY := node$(NODE_VERSION)-pnpm$(PNPM_VERSION)-rust$(RUST_VERSION)
BUILD_KEY := $(VERSION)-$(RELEASE)-$(PACKAGE_DATE)-$(SOURCE_DATE_EPOCH)-$(SOURCE_COMMIT)
PAYLOAD_KEY := $(VERSION)-$(SOURCE_DATE_EPOCH)-$(SOURCE_COMMIT)-$(TOOLCHAIN_KEY)
PAYLOAD_DIR := $(BUILD_DIR)/payload/$(RPM_ARCH)/$(PAYLOAD_KEY)
PAYLOAD_STAMP := $(PAYLOAD_DIR)/.payload-ready
DEB_TOPDIR := $(BUILD_DIR)/debian/$(RPM_ARCH)/$(BUILD_KEY)
DEB_SOURCE_DIR := $(DEB_TOPDIR)/$(NAME)-$(VERSION)
DEB_STAGE_STAMP := $(DEB_SOURCE_DIR)/.packaging-stage-ready
RPM_TOPDIR := $(BUILD_DIR)/rpm/$(RPM_ARCH)/$(BUILD_KEY)
RPM_PAYLOAD := $(RPM_TOPDIR)/SOURCES/$(NAME)-payload-$(VERSION)-$(RPM_ARCH).tar.gz

.PHONY: help source verify-source payload check-payload deb rpm rpm-native packages check \
	check-config check-recipes check-packages install-test clean

help:
	@echo "T3 Code native Linux packaging"
	@echo
	@echo "  make payload       build one unpacked Electron payload from pinned upstream"
	@echo "  make deb           build a DEB with dpkg-buildpackage"
	@echo "  make rpm           build an RPM in a Fedora container"
	@echo "  make packages      build both packages from the same payload"
	@echo "  make check         validate recipes and any existing payload/packages"
	@echo "  make install-test  install packages in Debian and Fedora containers"
	@echo "  make clean         remove only ./build and ./dist"

check-config:
	@case "$(VERSION)" in ""|*[!0-9A-Za-z._+~]*) echo "Invalid package version: $(VERSION)" >&2; exit 1;; esac
	@case "$(RELEASE)" in ""|*[!0-9A-Za-z._+~]*) echo "Invalid package release: $(RELEASE)" >&2; exit 1;; esac
	@printf '%s\n' "$(PACKAGE_DATE)" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$$' || \
		{ echo "Invalid package date: $(PACKAGE_DATE)" >&2; exit 1; }
	@printf '%s\n' "$(SOURCE_COMMIT)" | grep -Eq '^[0-9a-fA-F]{40}$$' || \
		{ echo "SOURCE_COMMIT must be a full 40-character commit SHA" >&2; exit 1; }
	@printf '%s\n' "$(SOURCE_DATE_EPOCH)" | grep -Eq '^[0-9]+$$' || \
		{ echo "SOURCE_DATE_EPOCH must be a Unix timestamp" >&2; exit 1; }
	@printf '%s\n' "$(NODE_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "NODE_VERSION must be an exact Node.js version" >&2; exit 1; }
	@printf '%s\n' "$(PNPM_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "PNPM_VERSION must be an exact pnpm version" >&2; exit 1; }
	@printf '%s\n' "$(RUST_VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "RUST_VERSION must be an exact stable Rust version" >&2; exit 1; }
	@if test -n "$(SOURCE_SHA256)"; then \
		printf '%s\n' "$(SOURCE_SHA256)" | grep -Eq '^[0-9a-fA-F]{64}$$' || \
			{ echo "SOURCE_SHA256 must be empty or a 64-character SHA-256" >&2; exit 1; }; \
	fi

$(SOURCE_ARCHIVE): | check-config
	install -d "$(DOWNLOAD_DIR)"
	curl --fail --location --output "$@" \
		"$(SOURCE_REPOSITORY)/archive/$(SOURCE_COMMIT).tar.gz"

verify-source: $(SOURCE_ARCHIVE) | check-config
	@if test -n "$(SOURCE_SHA256)"; then \
		printf '%s  %s\n' "$(SOURCE_SHA256)" "$(SOURCE_ARCHIVE)" | \
			sha256sum --check --status; \
	else \
		echo "No predeclared archive digest; resolved immutable commit $(SOURCE_COMMIT):"; \
		sha256sum "$(SOURCE_ARCHIVE)"; \
	fi

$(SOURCE_STAMP): $(SOURCE_ARCHIVE) patches/0001-copy-directory-build-output.patch | verify-source
	test "$(BUILD_DIR)" != / && test -n "$(SOURCE_COMMIT)"
	rm -rf "$(SOURCE_DIR)"
	install -d "$(SOURCE_DIR)"
	tar --extract --gzip --file "$(SOURCE_ARCHIVE)" \
		--strip-components=1 --directory "$(SOURCE_DIR)"
	@if patch --directory "$(SOURCE_DIR)" --strip=1 --dry-run \
			< patches/0001-copy-directory-build-output.patch >/dev/null; then \
		patch --directory "$(SOURCE_DIR)" --strip=1 \
			< patches/0001-copy-directory-build-output.patch; \
	elif grep -Fq '(stat.type !== "File" && stat.type !== "Directory")' \
			"$(SOURCE_DIR)/scripts/build-desktop-artifact.ts" && \
		grep -Fq 'yield* fs.copy(from, to);' \
			"$(SOURCE_DIR)/scripts/build-desktop-artifact.ts"; then \
		echo "Directory artifact support is already present upstream"; \
	else \
		echo "The directory-artifact patch no longer applies and is not upstream" >&2; \
		exit 1; \
	fi
	touch "$@"

source: verify-source $(SOURCE_STAMP)

$(PAYLOAD_STAMP): $(SOURCE_STAMP)
	command -v node >/dev/null
	command -v pnpm >/dev/null
	command -v cargo >/dev/null
	(command -v magick >/dev/null || command -v convert >/dev/null)
	test "$$(node --version)" = "v$(NODE_VERSION)"
	test "$$(pnpm --version)" = "$(PNPM_VERSION)"
	test "$$(rustc --version | awk '{ print $$2 }')" = "$(RUST_VERSION)"
	cd "$(SOURCE_DIR)" && pnpm install --frozen-lockfile
	test "$(BUILD_DIR)" != /
	rm -rf "$(BUILD_DIR)/electron-output"
	cd "$(SOURCE_DIR)" && SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)" \
		pnpm exec node scripts/build-desktop-artifact.ts \
		--platform linux \
		--target dir \
		--arch "$(ELECTRON_ARCH)" \
		--build-version "$(VERSION)" \
		--output-dir "$(BUILD_DIR)/electron-output" \
		--verbose
	test "$(BUILD_DIR)" != /
	rm -rf "$(PAYLOAD_DIR)"
	install -d "$(PAYLOAD_DIR)"
	cp -a "$(BUILD_DIR)/electron-output/$(UNPACKED_DIR)/." "$(PAYLOAD_DIR)/"
	cp "$(SOURCE_DIR)/LICENSE" "$(PAYLOAD_DIR)/LICENSE.t3code"
	cp "$(SOURCE_DIR)/assets/prod/black-universal-1024.png" "$(PAYLOAD_DIR)/t3code.png"
	touch "$@"
	$(MAKE) check-payload

payload: $(PAYLOAD_STAMP)

check-payload:
	test -x "$(PAYLOAD_DIR)/t3code"
	test -x "$(PAYLOAD_DIR)/chrome-sandbox"
	test -f "$(PAYLOAD_DIR)/resources/app.asar"
	test -x "$(PAYLOAD_DIR)/resources/resource-monitor/t3-resource-monitor"
	test -f "$(PAYLOAD_DIR)/LICENSE.t3code"
	test -f "$(PAYLOAD_DIR)/t3code.png"
	ELECTRON_RUN_AS_NODE=1 "$(PAYLOAD_DIR)/t3code" -e \
		'const fs = require("node:fs"); const entry = process.argv[1]; if (!fs.statSync(entry).isFile()) throw new Error(`Missing server entry: $${entry}`);' \
		"$(PAYLOAD_DIR)/resources/app.asar/apps/server/dist/bin.mjs"
	sh -n packaging/t3 packaging/t3code

$(DEB_STAGE_STAMP): $(PAYLOAD_STAMP) $(shell find debian packaging -type f | sort) | check-config
	test "$(BUILD_DIR)" != /
	rm -rf "$(DEB_SOURCE_DIR)"
	install -d "$(DEB_SOURCE_DIR)/payload"
	cp -a "$(PAYLOAD_DIR)/." "$(DEB_SOURCE_DIR)/payload/"
	cp -a debian "$(DEB_SOURCE_DIR)/"
	install -d "$(DEB_SOURCE_DIR)/packaging"
	cp packaging/t3 packaging/t3code packaging/t3code.desktop \
		packaging/t3code.metainfo.xml "$(DEB_SOURCE_DIR)/packaging/"
	sed -i -E '1s/^t3code \([^)]*\)/t3code ($(VERSION)-$(RELEASE))/' \
		"$(DEB_SOURCE_DIR)/debian/changelog"
	sed -i -E 's#<release version="[^"]+" date="[^"]+"/>#<release version="$(VERSION)" date="$(PACKAGE_DATE)"/>#' \
		"$(DEB_SOURCE_DIR)/packaging/t3code.metainfo.xml"
	touch "$@"

deb: $(DEB_STAGE_STAMP)
	test "$$(dpkg-architecture -qDEB_HOST_ARCH)" = "$(DEB_ARCH)"
	test "$$(dpkg-parsechangelog -l"$(DEB_SOURCE_DIR)/debian/changelog" -S Version)" = "$(VERSION)-$(RELEASE)"
	cd "$(DEB_SOURCE_DIR)" && SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)" \
		dpkg-buildpackage --build=binary --no-sign
	install -d "$(DIST_DIR)"
	find "$(DEB_TOPDIR)" -maxdepth 1 -type f -name '$(NAME)_*.deb' \
		-exec cp -f {} "$(DIST_DIR)/" \;

$(RPM_PAYLOAD): $(PAYLOAD_STAMP) rpm/t3code.spec packaging/t3 packaging/t3code \
		packaging/t3code.desktop packaging/t3code.metainfo.xml | check-config
	install -d "$(RPM_TOPDIR)"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	tar --create --gzip --file "$@" --directory "$(PAYLOAD_DIR)" \
		--sort=name --mtime="@$(SOURCE_DATE_EPOCH)" --owner=0 --group=0 \
		--numeric-owner --exclude=.payload-ready .
	cp rpm/t3code.spec "$(RPM_TOPDIR)/SPECS/"
	cp packaging/t3 packaging/t3code packaging/t3code.desktop "$(RPM_TOPDIR)/SOURCES/"
	sed -E 's#<release version="[^"]+" date="[^"]+"/>#<release version="$(VERSION)" date="$(PACKAGE_DATE)"/>#' \
		packaging/t3code.metainfo.xml > "$(RPM_TOPDIR)/SOURCES/t3code.metainfo.xml"

rpm-native: $(RPM_PAYLOAD)
	command -v desktop-file-install >/dev/null
	command -v desktop-file-validate >/dev/null
	command -v appstream-util >/dev/null
	rpmbuild --define "_topdir $(RPM_TOPDIR)" \
		--define "_source_date_epoch $(SOURCE_DATE_EPOCH)" \
		--define "package_version $(VERSION)" \
		--define "package_release $(RELEASE)" \
		--target "$(RPM_ARCH)" -bb "$(RPM_TOPDIR)/SPECS/t3code.spec"
	install -d "$(DIST_DIR)"
	find "$(RPM_TOPDIR)/RPMS" -type f -name '*.rpm' -exec cp -f {} "$(DIST_DIR)/" \;

rpm: $(RPM_PAYLOAD) packaging/build-rpm-container
	FEDORA_IMAGE="$(FEDORA_IMAGE)" \
		VERSION="$(VERSION)" RELEASE="$(RELEASE)" PACKAGE_DATE="$(PACKAGE_DATE)" \
		NODE_VERSION="$(NODE_VERSION)" PNPM_VERSION="$(PNPM_VERSION)" \
		RUST_VERSION="$(RUST_VERSION)" SOURCE_REPOSITORY="$(SOURCE_REPOSITORY)" \
		SOURCE_COMMIT="$(SOURCE_COMMIT)" SOURCE_SHA256="$(SOURCE_SHA256)" \
		SOURCE_DATE_EPOCH="$(SOURCE_DATE_EPOCH)" \
		sh packaging/build-rpm-container "$(CURDIR)"

packages: deb rpm

check-recipes:
	dpkg-parsechangelog -ldebian/changelog >/dev/null
	rpmspec --parse rpm/t3code.spec >/dev/null
	sh -n packaging/build-rpm-container packaging/check-packages \
		packaging/install-test packaging/publish-forgejo packaging/t3 packaging/t3code
	grep -Fq 'Exec=t3code %U' packaging/t3code.desktop
	grep -Fq 'x-scheme-handler/t3code;' packaging/t3code.desktop
	grep -Fq '<launchable type="desktop-id">t3code.desktop</launchable>' packaging/t3code.metainfo.xml

check-packages:
	sh packaging/check-packages "$(DIST_DIR)" "$(REQUIRE_PACKAGES)"

install-test:
	FEDORA_IMAGE="$(FEDORA_IMAGE)" sh packaging/install-test "$(DIST_DIR)"

check: check-config check-recipes check-packages
	@if test -f "$(PAYLOAD_STAMP)"; then $(MAKE) check-payload; fi
	@if command -v desktop-file-validate >/dev/null; then \
		desktop-file-validate packaging/t3code.desktop; \
	fi
	@if command -v appstreamcli >/dev/null; then \
		appstreamcli validate --no-net packaging/t3code.metainfo.xml; \
	fi
	@if test "$(REQUIRE_PACKAGES)" = 1; then \
		command -v lintian >/dev/null; \
		command -v rpmlint >/dev/null; \
	fi
	@if command -v lintian >/dev/null; then \
		for package in "$(DIST_DIR)"/*.deb; do \
			test -e "$$package" || continue; lintian --fail-on error "$$package"; \
		done; \
	fi
	@if command -v rpmlint >/dev/null; then \
		for package in "$(DIST_DIR)"/*.rpm; do \
			test -e "$$package" || continue; \
			rpmlint --rpmlintrc rpm/t3code.rpmlintrc "$$package"; \
		done; \
	fi

clean:
	test "$(BUILD_DIR)" != / && test "$(DIST_DIR)" != /
	rm -rf "$(BUILD_DIR)" "$(DIST_DIR)"
