# snmpd package

SNMPD_VERSION = 5.7.3+dfsg
SNMPD_VERSION_FULL = $(SNMPD_VERSION)-1.5

export SNMPD_VERSION SNMPD_VERSION_FULL

LIBSNMP_BASE = libsnmp-base_$(SNMPD_VERSION_FULL)_all.deb
$(LIBSNMP_BASE)_SRC_PATH = $(SRC_PATH)/snmpd
SONIC_MAKE_DEBS += $(LIBSNMP_BASE)

SNMPTRAPD = snmptrapd_$(SNMPD_VERSION_FULL)_amd64.deb
$(SNMPTRAPD)_DEPENDS += $(LIBSNMP) $(SNMPD)
$(SNMPTRAPD)_RDEPENDS += $(LIBSNMP) $(SNMPD)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(SNMPTRAPD)))

SNMP = snmp_$(SNMPD_VERSION_FULL)_amd64.deb
$(SNMP)_DEPENDS += $(LIBSNMP)
$(SNMP)_RDEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(SNMP)))

SNMPD = snmpd_$(SNMPD_VERSION_FULL)_amd64.deb
$(SNMPD)_DEPENDS += $(LIBSNMP)
$(SNMPD)_RDEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(SNMPD)))

LIBSNMP = libsnmp30_$(SNMPD_VERSION_FULL)_amd64.deb
$(LIBSNMP)_DEPENDS += $(LIBNL3_DEV)
$(LIBSNMP)_RDEPENDS += $(LIBSNMP_BASE) $(LIBNL3)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(LIBSNMP)))

LIBSNMP_DBG = libsnmp30-dbg_$(SNMPD_VERSION_FULL)_amd64.deb
$(LIBSNMP_DBG)_DEPENDS += $(LIBSNMP)
$(LIBSNMP_DBG)_RDEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(LIBSNMP_DBG)))

LIBSNMP_DEV = libsnmp-dev_$(SNMPD_VERSION_FULL)_amd64.deb
$(LIBSNMP_DEV)_DEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(LIBSNMP_DEV)))

LIBSNMP_PERL = libsnmp-perl_$(SNMPD_VERSION_FULL)_amd64.deb
$(LIBSNMP_PERL)_DEPENDS += $(LIBSNMP)
$(LIBSNMP_PERL)_RDEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(LIBSNMP_PERL)))

PYTHON_NETSNMP = python-netsnmp_$(SNMPD_VERSION_FULL)_amd64.deb
$(PYTHON_NETSNMP)_DEPENDS += $(LIBSNMP)
$(PYTHON_NETSNMP)_RDEPENDS += $(LIBSNMP)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(PYTHON_NETSNMP)))

TKMIB = tkmib_$(SNMPD_VERSION_FULL)_all.deb
$(TKMIB)_DEPENDS += $(LIBSNMP_PERL)
$(TKMIB)_RDEPENDS += $(LIBSNMP_PERL)
$(eval $(call add_derived_package,$(LIBSNMP_BASE),$(TKMIB)))
