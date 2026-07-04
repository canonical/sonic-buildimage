.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

# resolute: src:grub2-unsigned produces grub-efi-amd64 / -bin / -dbg / -unsigned
# (Ubuntu splits these out of src:grub2; debian/rules sets SB_SUBMIT=yes only
# when DEB_SOURCE=grub2-unsigned). See rules/grub2.mk.
GRUB2_UNSIGNED_UPSTREAM = 2.14

ifeq ($(CONFIGURED_ARCH),amd64)
MAIN_TARGET = grub-efi-amd64_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = grub-efi-amd64-bin_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
else ifeq ($(CONFIGURED_ARCH),arm64)
MAIN_TARGET = grub-efi-arm64_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = grub-efi-arm64-bin_$(GRUB2_UNSIGNED_VERSION)_$(CONFIGURED_ARCH).deb
endif

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Get grub2-unsigned debian packaging (Ubuntu pool via dget)
	export
	rm -rf ./grub2-unsigned-$(GRUB2_UNSIGNED_UPSTREAM)
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/g/grub2-unsigned/grub2-unsigned_$(GRUB2_UNSIGNED_VERSION).dsc

	pushd ./grub2-unsigned-$(GRUB2_UNSIGNED_UPSTREAM)

	# resolute: 2.14 debian/rules uses 'ln obj/monolithic/* <version>/' to
	# hardlink files into a staging dir for tar; overlayfs disallows directory
	# hard links. Reuse the grub2 patch script (ln -> per-file cp -al).
	chmod +x ../grub2/patch-overlayfs-ln.sh && ../grub2/patch-overlayfs-ln.sh

	# Build packages (DEB_SOURCE=grub2-unsigned -> SB_SUBMIT=yes -> builds
	# grub-efi-amd64-bin etc.)
	unset MAKEFLAGS MFLAGS
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif

	popd

	# Move the newly-built .deb packages to the destination directory
	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
