.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = sonic-device-data_$(SONIC_DEVICE_DATA_VERSION_FULL)_all.deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	pushd ./src

	# Remove any stale data
	rm -rf ./device

	# set asic type for virtual switch
	if [ "$(CONFIGURED_PLATFORM)" = "vpp" ]; then \
		echo "vpp" > ../../../device/virtual/x86_64-kvm_x86_64-r0/platform_asic; \
	else \
		echo "vs" > ../../../device/virtual/x86_64-kvm_x86_64-r0/platform_asic; \
	fi;

	# Create a new dir and copy all ONIE-platform-string-named dirs into it
	mkdir ./device
	cp -r -L ../../../device/*/* ./device/

	if [ "$(CONFIGURED_PLATFORM)" = "mellanox" ]; then \
		for sai_profile in `find device/ -name sai.profile | grep simx`; do \
			echo SAI_KEY_IS_SIMX=1 >> $$sai_profile; \
		done; \
	fi;

	# Generate VS HwSKU data (lanemap.ini, coreportindexmap.ini, profiles)
	# Uses Python for ~200x faster processing than the equivalent bash loop
	python3 ./generate_vs_hwsku.py ../../../device

	# arm64 vs installs from ONIE's qemu_armv8a platform; alias it to the vs data
	if [ "$(CONFIGURED_PLATFORM)" = "vs" ] && [ "$(CONFIGURED_ARCH)" = "arm64" ]; then \
		ln -s x86_64-kvm_x86_64-r0 ./device/arm64-qemu_armv8a-r0; \
	fi;

	# Build the package
ifeq ($(CROSS_BUILD_ENVIRON), y)
	dpkg-buildpackage -rfakeroot -b -us -uc -a$(CONFIGURED_ARCH) -Pcross,nocheck -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
else
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
endif

	popd

	mv $* $(DEST)/
