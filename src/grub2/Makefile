.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = grub2-common_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = grub-efi_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS += grub-common_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb

ifeq ($(CONFIGURED_ARCH),amd64)
DERIVED_TARGETS += grub-pc-bin_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS += grub-efi-amd64_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS += grub-efi-amd64-bin_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
else ifeq ($(CONFIGURED_ARCH),arm64)
DERIVED_TARGETS += grub-efi-arm64_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS += grub-efi-arm64-bin_$(GRUB2_VERSION)_$(CONFIGURED_ARCH).deb
endif

SUFFIX := $(shell date +%Y%m%d\.%H%M%S)
STG_BRANCH := stg_temp.$(SUFFIX)

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Get grub2 debian packaging (resolute base swap: Ubuntu pool via dget,
	# replaces salsa.debian.org git clone which had no resolute 2.14 tag)
	export
	rm -rf ./grub2 ./grub2-$(GRUB2_UPSTREAM_VERSION)
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/g/grub2/grub2_$(GRUB2_VERSION).dsc

	pushd ./grub2-$(GRUB2_UPSTREAM_VERSION)

	# resolute base swap: SONiC grub2 patches (adjust-build-rules-for-debian,
	# large-uid-skip-cpio-ustar) not yet ported to 2.14. Skipped to verify main
	# path. TODO: port these patches to 2.14 (were applied via stg on the old
	# salsa git checkout; need dget/dpkg-source-compatible apply on 2.14).
	# stg init
	# stg import -s ../patch/series

	# Build packages
	# Unset the MAKEFLAGS and MFLAGS variables to remove the jobserver information
	# from the environment variable. Without this, the GRUB targets that Debian
	# tries to build will get built in parallel, which will cause issues.
	# (Parallelism is limited to compilation within a target, but not multiple
	# targets being built at the same time.)
	unset MAKEFLAGS MFLAGS
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
