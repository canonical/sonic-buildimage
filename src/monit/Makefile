.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = monit_$(MONIT_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = monit-dbgsym_$(MONIT_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Remove any stale files
	rm -rf ./monit-*

	# Get monit from Ubuntu
	dget -u http://archive.ubuntu.com/ubuntu/pool/universe/m/monit/monit_$(MONIT_VERSION).dsc
	pushd ./monit-*

	# Create a git repository here for stg to apply patches.
	git init
	git add -f *
	git commit -qm "initial commit"

	# Apply SONiC patches in explicit series order.
	if grep -q '[^[:space:]]' ../patch/series; then
		stg init
		stg import -s ../patch/series
	fi

ifeq ($(CROSS_BUILD_ENVIRON), y)
	patch -p1 < ../patch/cross-compile-changes.patch
	dpkg-buildpackage -rfakeroot -b -us -uc --host-arch $(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
