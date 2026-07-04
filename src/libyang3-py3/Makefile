SHELL = /bin/bash
.ONESHELL:
.SHELLFLAGS += -e

MAIN_TARGET = $(LIBYANG3_PY3)

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	rm -rf ./libyang-python
	# Obtain libyang-python
	git clone --depth 1 -b v3.1.0 https://github.com/CESNET/libyang-python.git libyang-python
	pushd ./libyang-python

	# Apply patch series
	QUILT_PATCHES=../patch quilt push -a

	# resolute: stdeb-generated changelog has maintainer trailer 'None <None>'
	# (CESNET upstream didn't set DEBFULLNAME/DEBEMAIL when generating). resolute
	# dpkg rejects it ('cannot parse maintainer email address "None <None>" from
	# changelog entry' and 'cannot parse Maintainer field value "None <None>"');
	# trixie was lenient. Fix both the changelog trailer and the control
	# Maintainer field to a valid address.
	sed -i 's/None <None>/SONiC Build <sonic-build@local>/g' debian/changelog debian/control

	# Build package
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -d -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $* $(DEST)/
