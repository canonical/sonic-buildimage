.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = $(ISC_DHCP_RELAY)
DERIVED_TARGETS = $(ISC_DHCP_RELAY_DBG)

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./isc-dhcp-$(ISC_DHCP_VERSION)

	# Get isc-dhcp release, debian files
	dget -u http://archive.ubuntu.com/ubuntu/pool/universe/i/isc-dhcp/isc-dhcp_$(ISC_DHCP_VERSION_FULL).dsc
	pushd ./isc-dhcp-$(ISC_DHCP_VERSION)

	# Create a git repository here for stg to apply patches
	git init
	git add -f *
	git commit -qm "initial commit"

	# Revert Ubuntu patches that conflict with SONiC patches or fail
	# to compile on resolute (glibc 2.41 / kernel 7.0 / GCC 15):
	#
	# multi-ip-addr-per-if: restructures discover_interfaces() with
	#   getifaddrs() loop, breaking SONiC patches 0007/0008/0015.
	#
	# dhcp-lpf-ib: adds Infiniband support that fails to compile
	#   ("struct sockaddr_ll incomplete") on resolute headers.
	#   Not needed for SONiC dhcrelay.
	#
	# Use --force (-f) for dhcp-lpf-ib: later Ubuntu patches
	# (dhcp-gpxe-cid, dhcp-improved-xid-*) modify client/dhclient.c
	# so some hunks may fail to revert. This is ok — the remaining
	# changes are client-side and don't affect dhcrelay build.
	# NOTE: revert multi-ip-addr-per-if FIRST (out of order) so its
	# discover.c context isn't broken by the dhcp-lpf-ib revert.
	patch -R -p1 -s < debian/patches/multi-ip-addr-per-if 2>/dev/null || true
	patch -R -p1 --force -s < debian/patches/dhcp-lpf-ib.patch 2>/dev/null || true
	# Commit the reverts so stg sees a clean tree
	git add -f .
	git commit -qm "revert Ubuntu dhcp-lpf-ib + multi-ip-addr-per-if for SONiC compat"

	# Apply patches
	stg init
	stg import -s ../patch/series

	# resolute: dh_install in Ubuntu does not always create udeb sbin dir.
	mkdir -p debian/isc-dhcp-client-udeb/sbin

	# resolute: bind 9.11.36 (vendored in isc-dhcp) link error with -flto=auto:
	export DEB_CFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"
	export DEB_LDFLAGS_MAINT_STRIP="-flto=auto -ffat-lto-objects"

	# Build source and Debian packages
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	# Move the newly-built .deb packages to the destination directory
	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)