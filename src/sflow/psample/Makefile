.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = $(PSAMPLE)
DERIVED_TARGETS = $(PSAMPLE_DBG)

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :

	rm -fr ./libpsample
	git clone https://github.com/Mellanox/libpsample.git
	cp -r debian libpsample

	pushd ./libpsample
	git checkout -b libpsample -f e48fad2

	# resolute: cmake 4.x dropped compat with cmake_minimum_required < 3.5;
	# upstream libpsample CMakeLists.txt:1 says VERSION 3.3 -> CMake Error.
	# Bump to 3.5 (cmake 4.2 minimum compatible).
	sed -i 's/cmake_minimum_required(VERSION 3.3)/cmake_minimum_required(VERSION 3.5)/' CMakeLists.txt

ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif
	popd

	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)
