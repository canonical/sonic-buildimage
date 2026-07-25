.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

MAIN_TARGET = flashrom_$(FLASHROM_VERSION)_$(CONFIGURED_ARCH).deb
DERIVED_TARGETS = flashrom-dbgsym_$(FLASHROM_VERSION)_$(CONFIGURED_ARCH).deb

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	rm -rf ./flashrom-*
	dget -u http://archive.ubuntu.com/ubuntu/pool/main/f/flashrom/flashrom_$(FLASHROM_VERSION).dsc
	pushd flashrom-*
	for p in $$(grep -v '^#' ../patch/series 2>/dev/null | grep -v '^$$'); do patch -p1 < "../patch/$$p"; done
	dpkg-buildpackage -rfakeroot -b -us -uc -j$(SONIC_CONFIG_MAKE_JOBS) --admindir $(SONIC_DPKG_ADMINDIR)
	popd
	mv $(DERIVED_TARGETS) $* $(DEST)/

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)