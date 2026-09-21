# chisel-releases coverage of SONiC resolute container packages

Generated 2026-09-17. Sources: 30 SONiC-base containers (dash-engine excluded: external Ubuntu 20.04 image); Ubuntu resolute(+updates,+security) main+universe amd64 Packages index (74340 pkgs); chisel-releases `origin/ubuntu-26.04`@70d32b4 (694 SDFs), 25.10 (637), 24.04 (624).

## Origin of every deb found in the containers

| origin | count | meaning |
|---|--:|---|
| ARCHIVE | 399 | name+version present in Ubuntu resolute archive → chisel can cut it, given an SDF |
| ARCHIVE(ver-diff) | 17 | name in archive but installed version differs (pinned/PPA) → SDF may apply, source must be checked |
| SELF | 53 | built from source in sonic-buildimage (`target/debs/resolute/`) → not in any chisel archive |
| THIRD-PARTY | 6 | downloaded binary deb (vendor SAI, otelcol) → not in any chisel archive |

### THIRD-PARTY debs

| package | version | MB | containers |
|---|---|--:|---|
| otelcol-contrib | 0.144.0 | 325 | docker-sonic-otel |
| saicredo-blackhawk | 1.2.6 | 0 | docker-gbsyncd-credo |
| saicredo-crt88322 | 1.2.6 | 0 | docker-gbsyncd-credo |
| saicredo-owl | 1.2.6 | 1 | docker-gbsyncd-credo |
| saicredo-saicredo | 1.2.6 | 13 | docker-gbsyncd-credo |
| sonic-build-hooks | 1.0 | 0 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |

### ARCHIVE(ver-diff)

| package | installed | archive has |
|---|---|---|
| base-files | 14ubuntu6.1 | 14ubuntu6, 14ubuntu6.2 |
| curl | 8.18.0-1ubuntu2.4 | 8.18.0-1ubuntu2, 8.18.0-1ubuntu2.5 |
| libcurl4t64 | 8.18.0-1ubuntu2.4 | 8.18.0-1ubuntu2, 8.18.0-1ubuntu2.5 |
| libgcrypt20 | 1.12.0-2ubuntu1 | 1.12.0-2, 1.12.0-2ubuntu1.1 |
| libpam-modules | 1.7.0-5ubuntu3.1 | 1.7.0-5ubuntu3, 1.7.0-5ubuntu3.2 |
| libpam-modules-bin | 1.7.0-5ubuntu3.1 | 1.7.0-5ubuntu3, 1.7.0-5ubuntu3.2 |
| libpam-runtime | 1.7.0-5ubuntu3.1 | 1.7.0-5ubuntu3, 1.7.0-5ubuntu3.2 |
| libpam0g | 1.7.0-5ubuntu3.1 | 1.7.0-5ubuntu3, 1.7.0-5ubuntu3.2 |
| libperl5.40 | 5.40.1-7ubuntu0.1 | 5.40.1-7build1, 5.40.1-7ubuntu0.3 |
| libsqlite3-0 | 3.46.1-9ubuntu0.2 | 3.46.1-9, 3.46.1-9ubuntu0.3 |
| libssh2-1t64 | 1.11.1-1ubuntu0.26.04.3 | 1.11.1-1build2, 1.11.1-1ubuntu0.26.04.4 |
| libssl-dev | 3.5.5-1ubuntu3.4 | 3.5.5-1ubuntu3, 3.5.5-1ubuntu3.5 |
| perl | 5.40.1-7ubuntu0.1 | 5.40.1-7build1, 5.40.1-7ubuntu0.3 |
| perl-base | 5.40.1-7ubuntu0.1 | 5.40.1-7build1, 5.40.1-7ubuntu0.3 |
| perl-modules-5.40 | 5.40.1-7ubuntu0.1 | 5.40.1-7build1, 5.40.1-7ubuntu0.3 |
| vim-common | 2:9.1.2141-1ubuntu4.8 | 2:9.1.2141-1ubuntu4, 2:9.1.2141-1ubuntu4.9 |
| vim-tiny | 2:9.1.2141-1ubuntu4.8 | 2:9.1.2141-1ubuntu4, 2:9.1.2141-1ubuntu4.9 |

## chisel-releases SDF coverage (ARCHIVE + ver-diff packages only)

Status: **26.04** = SDF exists on ubuntu-26.04 · **port<-24.04** = only on 24.04 (forward-port = adaptation) · **NEW** = no SDF on 26.04/25.10/24.04. 25.10 adds nothing over 26.04 for our set.

Class (heuristic): runtime · perl · pkg-mgmt (apt/dpkg/pip tooling; a chiselled rock normally drops these) · build-only (-dev, compilers, autotools; should never be in a runtime image).

| class | 26.04 | port<-24.04 | NEW | total |
|---|--:|--:|--:|--:|
| runtime | 202 | 3 | 113 | 318 |
| perl | 4 | 0 | 2 | 6 |
| pkg-mgmt | 10 | 0 | 3 | 13 |
| build-only | 20 | 0 | 59 | 79 |

### runtime class, by layer

| layer | 26.04 | port<-24.04 | NEW |
|---|--:|--:|--:|
| base | 136 | 3 | 26 |
| config-engine | 3 | 0 | 6 |
| swss-layer | 1 | 0 | 1 |
| leaf | 62 | 0 | 80 |

## Runtime ARCHIVE packages with no 26.04 SDF (the SDF-authoring backlog), sorted by #containers desc

| package | version | section | KB | layer | containers | status |
|---|---|---|--:|---|--:|---|
| adduser | 3.153ubuntu1 | admin | 437 | base | 30 | NEW |
| bsdutils | 1:2.41.3-3ubuntu2 | utils | 250 | base | 30 | NEW |
| coreutils-from-uutils | 0.0.0~ubuntu25 | utils | 237 | base | 30 | NEW |
| e2fsprogs | 1.47.2-3ubuntu4 | admin | 1530 | base | 30 | NEW |
| libc-gconv-modules-extra | 2.43-2ubuntu2.4 | libs | 8079 | base | 30 | NEW |
| libdaemon0 | 0.14-7.1ubuntu5 | libs | 51 | base | 30 | NEW |
| libestr0 | 0.1.11-2build1 | libs | 34 | base | 30 | port<-24.04 |
| libext2fs2t64 | 1.47.2-3ubuntu4 | libs | 551 | base | 30 | NEW |
| libfastjson4 | 1.2304.0-2build1 | libs | 69 | base | 30 | port<-24.04 |
| libpopt0 | 1.19+dfsg-2build1 | libs | 124 | base | 30 | NEW |
| librelp0 | 1.12.0-1 | libs | 114 | base | 30 | NEW |
| libss2 | 1.47.2-3ubuntu4 | libs | 78 | base | 30 | NEW |
| login.defs | 1:4.17.4-2ubuntu3 | admin | 103 | base | 30 | NEW |
| net-tools | 2.10-2ubuntu1 | net | 664 | base | 30 | NEW |
| python-is-python3 | 3.13.3-1+build1 | python | 16 | base | 30 | NEW |
| python3-autocommand | 2.2.2-4 | python | 61 | base | 30 | NEW |
| python3-inflect | 7.5.0-1build1 | python | 148 | base | 30 | NEW |
| python3-jaraco.context | 6.0.1-2 | python | 34 | base | 30 | NEW |
| python3-jaraco.functools | 4.1.0-1build1 | python | 47 | base | 30 | NEW |
| python3-jaraco.text | 4.0.0-1build1 | python | 47 | base | 30 | NEW |
| python3-more-itertools | 10.8.0-1build1 | python | 308 | base | 30 | NEW |
| python3-packaging | 26.0-1 | python | 288 | base | 30 | NEW |
| python3-typeguard | 4.4.4-2 | python | 165 | base | 30 | NEW |
| python3-typing-extensions | 4.15.0-2 | python | 511 | base | 30 | NEW |
| python3-zipp | 3.23.0-1build1 | python | 45 | base | 30 | NEW |
| rsync | 3.4.1+ds1-7ubuntu0.3 | net | 829 | base | 30 | NEW |
| rsyslog | 8.2512.0-1ubuntu4.1 | admin | 1840 | base | 30 | port<-24.04 |
| rsyslog-relp | 8.2512.0-1ubuntu4.1 | admin | 87 | base | 30 | NEW |
| rust-coreutils | 0.8.0-0ubuntu3 | utils | 15617 | base | 30 | NEW |
| libpython3.14 | 3.14.4-1ubuntu0.2 | libs | 8131 | config-engine | 30 | NEW |
| python3-cffi | 2.0.0-3build1 | python | 417 | config-engine | 30 | NEW |
| python3-cffi-backend | 2.0.0-3build1 | python | 242 | config-engine | 30 | NEW |
| python3-pycparser | 3.0-1 | python | 432 | config-engine | 30 | NEW |
| python3-redis | 6.4.0-1 | python | 1429 | config-engine | 30 | NEW |
| python3-yaml | 6.0.3-1build1 | python | 561 | config-engine | 30 | NEW |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | libs | 3107 | swss-layer | 14 | NEW |
| libpci3 | 1:3.14.0-1build2 | libs | 117 | leaf | 5 | NEW |
| pci.ids | 0.0~2026.02.12-1 | admin | 1561 | leaf | 5 | NEW |
| libibverbs1 | 61.0-2ubuntu3 | libs | 206 | leaf | 4 | NEW |
| libpcap0.8t64 | 1.10.6-1ubuntu1 | libs | 407 | leaf | 4 | NEW |
| libprotobuf-lite32t64 | 3.21.12-15ubuntu1 | libs | 890 | leaf | 4 | NEW |
| ibverbs-providers | 61.0-2ubuntu3 | net | 1378 | leaf | 3 | NEW |
| libsnmp-base | 5.9.4+dfsg-2ubuntu3 | libs | 655 | leaf | 3 | NEW |
| libsnmp40t64 | 5.9.4+dfsg-2ubuntu3 | libs | 3734 | leaf | 3 | NEW |
| python3-protobuf | 3.21.12-15ubuntu1 | python | 699 | leaf | 3 | NEW |
| tcpdump | 4.99.6-1 | net | 1325 | leaf | 3 | NEW |
| bridge-utils | 1.7.1-4ubuntu3 | net | 112 | leaf | 2 | NEW |
| conntrack | 1:1.4.9-1 | net | 122 | leaf | 2 | NEW |
| dmidecode | 3.6-2ubuntu1 | utils | 227 | leaf | 2 | NEW |
| ethtool | 1:6.19-1 | net | 1080 | leaf | 2 | NEW |
| freeipmi-common | 1.6.16-1ubuntu0.1 | admin | 368 | leaf | 2 | NEW |
| ipmitool | 1.8.19-10ubuntu1 | utils | 6122 | leaf | 2 | NEW |
| libabsl20260107 | 20260107.0-4 | libs | 2794 | leaf | 2 | NEW |
| libc-ares2 | 1.34.6-1 | oldlibs | 32 | leaf | 2 | NEW |
| libdouble-conversion3 | 3.4.0-1 | libs | 106 | leaf | 2 | NEW |
| libfl2 | 2.6.4-8.2build2 | libs | 57 | leaf | 2 | NEW |
| libfreeipmi17 | 1.6.16-1ubuntu0.1 | libs | 5406 | leaf | 2 | NEW |
| libgc1 | 1:8.2.12-1 | libs | 409 | leaf | 2 | NEW |
| libgmpxx4ldbl | 2:6.3.0+dfsg-5ubuntu2 | libs | 54 | leaf | 2 | NEW |
| libgrpc++1.51t64 | 1.51.1-8ubuntu1 | libs | 2094 | leaf | 2 | NEW |
| libgrpc29t64 | 1.51.1-8ubuntu1 | libs | 10271 | leaf | 2 | NEW |
| libitm1 | 16-20260322-1ubuntu1 | libs | 119 | leaf | 2 | NEW |
| liblsof0 | 4.99.4+dfsg-2build2 | libs | 209 | leaf | 2 | NEW |
| libnanomsg5 | 1.1.5+dfsg-1.2 | libs | 288 | leaf | 2 | NEW |
| libobjc4 | 16-20260322-1ubuntu1 | libs | 214 | leaf | 2 | NEW |
| libpcre2-16-0 | 10.46-1build1 | libs | 651 | leaf | 2 | NEW |
| libpfm4 | 4.13.0+git106-g3e4031b-1 | libs | 3742 | leaf | 2 | NEW |
| libprotoc32t64 | 3.21.12-15ubuntu1 | libs | 2352 | leaf | 2 | NEW |
| libqt5core5t64 | 5.15.18+dfsg-1ubuntu1 | libs | 6188 | leaf | 2 | NEW |
| libqt5dbus5t64 | 5.15.18+dfsg-1ubuntu1 | libs | 765 | leaf | 2 | NEW |
| libqt5network5t64 | 5.15.18+dfsg-1ubuntu1 | libs | 2528 | leaf | 2 | NEW |
| libquadmath0 | 16-20260322-1ubuntu1 | libs | 304 | leaf | 2 | NEW |
| libre2-11 | 20250805-1build3 | libs | 424 | leaf | 2 | NEW |
| libthrift-0.22.0 | 0.22.0-3ubuntu1 | libs | 980 | leaf | 2 | NEW |
| lsof | 4.99.4+dfsg-2build2 | utils | 480 | leaf | 2 | NEW |
| pciutils | 1:3.14.0-1build2 | admin | 256 | leaf | 2 | NEW |
| python3-grpcio | 1.51.1-8ubuntu1 | python | 6448 | leaf | 2 | NEW |
| python3-netifaces | 0.11.0-2build7 | python | 56 | leaf | 2 | NEW |
| python3-ply | 3.11-10 | python | 249 | leaf | 2 | NEW |
| python3-psutil | 7.1.0-1ubuntu1 | python | 1109 | leaf | 2 | NEW |
| python3-pyroute2 | 0.8.1-4 | python | 1809 | leaf | 2 | NEW |
| python3-scapy | 2.7.0+dfsg1-1 | python | 9334 | leaf | 2 | NEW |
| python3-six | 1.17.0-2build1 | python | 59 | leaf | 2 | NEW |
| python3-thrift | 0.22.0-3ubuntu1 | python | 318 | leaf | 2 | NEW |
| arping | 2.28-1 | net | 85 | leaf | 1 | NEW |
| cron-daemon-common | 3.0pl1-200ubuntu1 | admin | 54 | leaf | 1 | NEW |
| i2c-tools | 4.4-2build3 | utils | 324 | leaf | 1 | NEW |
| ifupdown | 0.8.43ubuntu3 | admin | 206 | leaf | 1 | NEW |
| kmod | 34.2-2ubuntu2 | admin | 264 | leaf | 1 | NEW |
| libdbi1t64 | 0.9.0-6.1build2 | libs | 95 | leaf | 1 | NEW |
| libdbus-c++-1-0v5 | 0.9.0-16 | libs | 202 | leaf | 1 | NEW |
| libexplain51t64 | 1.4.D001-16 | libs | 1285 | leaf | 1 | NEW |
| libgoogle-perftools4t64 | 2.18.1-1 | libs | 798 | leaf | 1 | NEW |
| libi2c0 | 4.4-2build3 | libs | 31 | leaf | 1 | NEW |
| libjsoncpp26 | 1.9.6-5 | libs | 245 | leaf | 1 | NEW |
| libnet9 | 1.3+dfsg-3 | libs | 130 | leaf | 1 | NEW |
| libnvme1t64 | 1.16.1-4 | libs | 278 | leaf | 1 | NEW |
| libpcre2-posix3 | 10.46-1build1 | libs | 36 | leaf | 1 | NEW |
| librrd8t64 | 1.9.0-2build1 | libs | 434 | leaf | 1 | NEW |
| libtcmalloc-minimal4t64 | 2.18.1-1 | libs | 432 | leaf | 1 | NEW |
| logrotate | 3.22.0-1build1 | admin | 145 | leaf | 1 | NEW |
| lz4 | 1.10.0-8 | utils | 138 | leaf | 1 | NEW |
| ndisc6 | 1.0.8-1 | net | 276 | leaf | 1 | NEW |
| ndppd | 0.2.5-6build2 | net | 144 | leaf | 1 | NEW |
| nvme-cli | 2.16-1 | admin | 2254 | leaf | 1 | NEW |
| psmisc | 23.7-2ubuntu2 | admin | 604 | leaf | 1 | NEW |
| python3-bottle | 0.13.2-1.1 | python | 204 | leaf | 1 | NEW |
| python3-smbus | 4.4-2build3 | python | 46 | leaf | 1 | NEW |
| radvd | 1:2.20-1build1 | net | 167 | leaf | 1 | NEW |
| rrdtool | 1.9.0-2build1 | utils | 1116 | leaf | 1 | NEW |
| smartmontools | 7.5-2 | utils | 2250 | leaf | 1 | NEW |
| snmp | 5.9.4+dfsg-2ubuntu3 | net | 716 | leaf | 1 | NEW |
| snmpd | 5.9.4+dfsg-2ubuntu3 | net | 151 | leaf | 1 | NEW |
| udev | 259.5-0ubuntu3.4 | admin | 10382 | leaf | 1 | NEW |
| uuid-runtime | 2.41.3-3ubuntu2.2 | utils | 163 | leaf | 1 | NEW |
| xxd | 2:9.1.2141-1ubuntu4.9 | editors | 165 | leaf | 1 | NEW |

## Non-runtime ARCHIVE packages with no 26.04 SDF (expected to be dropped, not sliced)

| package | class | section | KB | layer | containers |
|---|---|---|--:|---|--:|
| libc-dev-bin | build-only | libdevel | 114 | leaf | 5 |
| rpcsvc-proto | build-only | libs | 249 | leaf | 5 |
| libprotobuf-dev | build-only | libdevel | 12067 | leaf | 4 |
| libdbus-1-dev | build-only | libdevel | 954 | leaf | 3 |
| libibverbs-dev | build-only | libdevel | 2514 | leaf | 3 |
| libpcap-dev | build-only | libdevel | 47 | leaf | 3 |
| libpcap0.8-dev | build-only | libdevel | 907 | leaf | 3 |
| libpkgconf7 | build-only | libs | 127 | leaf | 3 |
| libsystemd-dev | build-only | libdevel | 5743 | leaf | 3 |
| pkgconf | build-only | devel | 73 | leaf | 3 |
| pkgconf-bin | build-only | devel | 85 | leaf | 3 |
| sgml-base | build-only | text | 65 | leaf | 3 |
| xml-core | build-only | text | 114 | leaf | 3 |
| autoconf | build-only | devel | 2091 | leaf | 2 |
| automake | build-only | devel | 1640 | leaf | 2 |
| autotools-dev | build-only | devel | 147 | leaf | 2 |
| clang | build-only | devel | 21 | leaf | 2 |
| clang-21 | build-only | devel | 498 | leaf | 2 |
| cpp | build-only | interpreters | 37 | leaf | 2 |
| cpp-15 | build-only | interpreters | 11 | leaf | 2 |
| flex | build-only | devel | 932 | leaf | 2 |
| libabsl-dev | build-only | libdevel | 8532 | leaf | 2 |
| libbpf-dev | build-only | libdevel | 1136 | leaf | 2 |
| libc-ares-dev | build-only | libdevel | 879 | leaf | 2 |
| libclang-common-21-dev | build-only | libdevel | 14666 | leaf | 2 |
| libclang-cpp21 | build-only | libs | 58935 | leaf | 2 |
| libclang1-21 | build-only | libs | 31988 | leaf | 2 |
| libctf-nobfd0 | build-only | devel | 323 | leaf | 2 |
| libelf-dev | build-only | libdevel | 486 | leaf | 2 |
| libfl-dev | build-only | libdevel | 54 | leaf | 2 |
| libgc-dev | build-only | libdevel | 988 | leaf | 2 |
| libgmp-dev | build-only | libdevel | 1600 | leaf | 2 |
| libgprofng0 | build-only | devel | 4066 | leaf | 2 |
| libgrpc++-dev | build-only | libdevel | 7007 | leaf | 2 |
| libgrpc-dev | build-only | libdevel | 33596 | leaf | 2 |
| libhwasan0 | build-only | libs | 5144 | leaf | 2 |
| liblsan0 | build-only | libs | 4023 | leaf | 2 |
| libnanomsg-dev | build-only | libdevel | 1265 | leaf | 2 |
| libobjc-15-dev | build-only | libdevel | 1511 | leaf | 2 |
| libprotoc-dev | build-only | libdevel | 7115 | leaf | 2 |
| libre2-dev | build-only | libdevel | 1027 | leaf | 2 |
| libssl-dev | build-only | libdevel | 16030 | leaf | 2 |
| libstdc++-15-dev | build-only | libdevel | 25491 | leaf | 2 |
| libthrift-dev | build-only | libdevel | 4007 | leaf | 2 |
| libtool | build-only | devel | 881 | leaf | 2 |
| libtsan2 | build-only | libs | 9295 | leaf | 2 |
| libzstd-dev | build-only | libdevel | 1297 | leaf | 2 |
| llvm | build-only | devel | 156 | leaf | 2 |
| llvm-21 | build-only | devel | 86355 | leaf | 2 |
| llvm-21-linker-tools | build-only | devel | 4295 | leaf | 2 |
| llvm-21-runtime | build-only | devel | 1719 | leaf | 2 |
| llvm-runtime | build-only | devel | 16 | leaf | 2 |
| m4 | build-only | interpreters | 580 | leaf | 2 |
| pkg-config | build-only | oldlibs | 34 | leaf | 2 |
| protobuf-compiler | build-only | devel | 113 | leaf | 2 |
| protobuf-compiler-grpc | build-only | libs | 161 | leaf | 2 |
| thrift-compiler | build-only | devel | 4232 | leaf | 2 |
| libjsoncpp-dev | build-only | libdevel | 582 | leaf | 1 |
| librrd-dev | build-only | libdevel | 815 | leaf | 1 |
| libtext-charwidth-perl | perl | perl | 42 | base | 30 |
| libtext-wrapi18n-perl | perl | perl | 24 | base | 30 |
| apt-utils | pkg-mgmt | admin | 668 | config-engine | 30 |
| debconf | pkg-mgmt | admin | 507 | base | 30 |
| libdebconfclient0 | pkg-mgmt | libs | 39 | base | 30 |

## ARCHIVE packages already covered on 26.04

| package | class | layer | containers |
|---|---|---|--:|
| apt | pkg-mgmt | base | 30 |
| base-files | runtime | base | 30 |
| base-passwd | runtime | base | 30 |
| ca-certificates | runtime | base | 30 |
| coreutils | runtime | base | 30 |
| curl | runtime | base | 30 |
| dash | runtime | base | 30 |
| debianutils | runtime | base | 30 |
| diffutils | runtime | base | 30 |
| dpkg | pkg-mgmt | base | 30 |
| findutils | runtime | base | 30 |
| gcc-16-base | build-only | base | 30 |
| gnu-coreutils | runtime | base | 30 |
| gpgv | pkg-mgmt | base | 30 |
| grep | runtime | base | 30 |
| gzip | runtime | base | 30 |
| hostname | runtime | base | 30 |
| init-system-helpers | runtime | base | 30 |
| iproute2 | runtime | base | 30 |
| jq | runtime | base | 30 |
| less | runtime | base | 30 |
| libacl1 | runtime | base | 30 |
| libapt-pkg7.0 | pkg-mgmt | base | 30 |
| libatomic1 | runtime | base | 30 |
| libattr1 | runtime | base | 30 |
| libaudit-common | runtime | base | 30 |
| libaudit1 | runtime | base | 30 |
| libblkid1 | runtime | base | 30 |
| libbpf1 | runtime | base | 30 |
| libbrotli1 | runtime | base | 30 |
| libbsd0 | runtime | base | 30 |
| libbz2-1.0 | runtime | base | 30 |
| libc-bin | runtime | base | 30 |
| libc6 | runtime | base | 30 |
| libcap-ng0 | runtime | base | 30 |
| libcap2 | runtime | base | 30 |
| libcap2-bin | runtime | base | 30 |
| libcom-err2 | runtime | base | 30 |
| libcrypt1 | runtime | base | 30 |
| libcurl4t64 | runtime | base | 30 |
| libdb5.3t64 | runtime | base | 30 |
| libdbus-1-3 | runtime | base | 30 |
| libelf1t64 | runtime | base | 30 |
| libexpat1 | runtime | base | 30 |
| libffi8 | runtime | base | 30 |
| libgcc-s1 | build-only | base | 30 |
| libgcrypt20 | runtime | base | 30 |
| libgdbm-compat4t64 | runtime | base | 30 |
| libgdbm6t64 | runtime | base | 30 |
| libgmp10 | runtime | base | 30 |
| libgnutls30t64 | runtime | base | 30 |
| libgpg-error0 | runtime | base | 30 |
| libgssapi-krb5-2 | runtime | base | 30 |
| libhogweed6t64 | runtime | base | 30 |
| libidn2-0 | runtime | base | 30 |
| libjansson4 | runtime | base | 30 |
| libjemalloc2 | runtime | base | 30 |
| libjq1 | runtime | base | 30 |
| libk5crypto3 | runtime | base | 30 |
| libkeyutils1 | runtime | base | 30 |
| libkrb5-3 | runtime | base | 30 |
| libkrb5support0 | runtime | base | 30 |
| libldap-common | runtime | base | 30 |
| libldap2 | runtime | base | 30 |
| liblz4-1 | runtime | base | 30 |
| liblzf1 | runtime | base | 30 |
| liblzma5 | runtime | base | 30 |
| libmd0 | runtime | base | 30 |
| libmnl0 | runtime | base | 30 |
| libmount1 | runtime | base | 30 |
| libncursesw6 | runtime | base | 30 |
| libnettle8t64 | runtime | base | 30 |
| libnghttp2-14 | runtime | base | 30 |
| libnorm1t64 | runtime | base | 30 |
| libonig5 | runtime | base | 30 |
| libp11-kit0 | runtime | base | 30 |
| libpam-modules | runtime | base | 30 |
| libpam-modules-bin | runtime | base | 30 |
| libpam-runtime | runtime | base | 30 |
| libpam0g | runtime | base | 30 |
| libpcre2-8-0 | runtime | base | 30 |
| libperl5.40 | perl | base | 30 |
| libpgm-5.3-0t64 | runtime | base | 30 |
| libproc2-0 | runtime | base | 30 |
| libpsl5t64 | runtime | base | 30 |
| libpython3-stdlib | runtime | base | 30 |
| libpython3.14-minimal | runtime | base | 30 |
| libpython3.14-stdlib | runtime | base | 30 |
| libreadline8t64 | runtime | base | 30 |
| librtmp1 | runtime | base | 30 |
| libsasl2-2 | runtime | base | 30 |
| libsasl2-modules-db | runtime | base | 30 |
| libseccomp2 | runtime | base | 30 |
| libselinux1 | runtime | base | 30 |
| libsemanage-common | runtime | base | 30 |
| libsemanage2 | runtime | base | 30 |
| libsepol2 | runtime | base | 30 |
| libsmartcols1 | runtime | base | 30 |
| libsodium23 | runtime | base | 30 |
| libsqlite3-0 | runtime | base | 30 |
| libssh2-1t64 | runtime | base | 30 |
| libssl3t64 | runtime | base | 30 |
| libstdc++6 | runtime | base | 30 |
| libsystemd0 | runtime | base | 30 |
| libtasn1-6 | runtime | base | 30 |
| libtinfo6 | runtime | base | 30 |
| libtirpc-common | runtime | base | 30 |
| libtirpc3t64 | runtime | base | 30 |
| libudev1 | runtime | base | 30 |
| libunistring5 | runtime | base | 30 |
| libuuid1 | runtime | base | 30 |
| libwrap0 | runtime | base | 30 |
| libxtables12 | runtime | base | 30 |
| libxxhash0 | runtime | base | 30 |
| libzmq5 | runtime | base | 30 |
| libzstd1 | runtime | base | 30 |
| login | runtime | base | 30 |
| logsave | runtime | base | 30 |
| mawk | runtime | base | 30 |
| media-types | runtime | base | 30 |
| mount | runtime | base | 30 |
| ncurses-base | runtime | base | 30 |
| ncurses-bin | runtime | base | 30 |
| netbase | runtime | base | 30 |
| openssl | runtime | base | 30 |
| openssl-provider-legacy | runtime | base | 30 |
| passwd | runtime | base | 30 |
| perl | perl | base | 30 |
| perl-base | perl | base | 30 |
| perl-modules-5.40 | perl | base | 30 |
| procps | runtime | base | 30 |
| python3 | runtime | base | 30 |
| python3-minimal | runtime | base | 30 |
| python3-pip | pkg-mgmt | base | 30 |
| python3-pkg-resources | pkg-mgmt | base | 30 |
| python3-setuptools | pkg-mgmt | base | 30 |
| python3-wheel | pkg-mgmt | base | 30 |
| python3.14 | runtime | base | 30 |
| python3.14-minimal | runtime | base | 30 |
| readline-common | runtime | base | 30 |
| redis-tools | runtime | base | 30 |
| sed | runtime | base | 30 |
| sensible-utils | runtime | base | 30 |
| sysvinit-utils | runtime | base | 30 |
| tar | runtime | base | 30 |
| tzdata | runtime | base | 30 |
| ubuntu-keyring | pkg-mgmt | base | 30 |
| ucf | pkg-mgmt | base | 30 |
| util-linux | runtime | base | 30 |
| vim-common | runtime | base | 30 |
| vim-tiny | runtime | base | 30 |
| zlib1g | runtime | base | 30 |
| libboost-serialization1.83.0 | runtime | config-engine | 30 |
| libhiredis1.1.0 | runtime | config-engine | 30 |
| libyaml-0-2 | runtime | config-engine | 30 |
| iputils-ping | runtime | swss-layer | 8 |
| binutils | build-only | leaf | 2 |
| binutils-common | build-only | leaf | 2 |
| binutils-x86-64-linux-gnu | build-only | leaf | 2 |
| cpp-15-x86-64-linux-gnu | build-only | leaf | 2 |
| cpp-x86-64-linux-gnu | build-only | leaf | 2 |
| cron | runtime | leaf | 1 |
| file | runtime | leaf | 2 |
| fontconfig | runtime | leaf | 1 |
| fontconfig-config | runtime | leaf | 1 |
| fonts-dejavu-core | runtime | leaf | 1 |
| fonts-dejavu-mono | runtime | leaf | 1 |
| gcc-15-base | build-only | leaf | 2 |
| iptables | runtime | leaf | 1 |
| libasan8 | build-only | leaf | 2 |
| libbinutils | build-only | leaf | 2 |
| libboost-filesystem1.83.0 | runtime | leaf | 1 |
| libboost-log1.83.0 | runtime | leaf | 1 |
| libboost-program-options1.83.0 | runtime | leaf | 1 |
| libboost-thread1.83.0 | runtime | leaf | 2 |
| libc6-dev | build-only | leaf | 5 |
| libcairo2 | runtime | leaf | 1 |
| libcares2 | runtime | leaf | 3 |
| libcjson1 | runtime | leaf | 1 |
| libctf0 | build-only | leaf | 2 |
| libdatrie1 | runtime | leaf | 1 |
| libedit2 | runtime | leaf | 2 |
| libevent-2.1-7t64 | runtime | leaf | 2 |
| libevent-core-2.1-7t64 | runtime | leaf | 1 |
| libevent-pthreads-2.1-7t64 | runtime | leaf | 1 |
| libfontconfig1 | runtime | leaf | 1 |
| libfreetype6 | runtime | leaf | 1 |
| libfribidi0 | runtime | leaf | 1 |
| libgcc-15-dev | build-only | leaf | 2 |
| libglib2.0-0t64 | runtime | leaf | 3 |
| libgomp1 | runtime | leaf | 2 |
| libgraphite2-3 | runtime | leaf | 1 |
| libharfbuzz0b | runtime | leaf | 1 |
| libicu78 | runtime | leaf | 2 |
| libip4tc2 | runtime | leaf | 1 |
| libip6tc2 | runtime | leaf | 1 |
| libisl23 | build-only | leaf | 2 |
| libjson-c5 | runtime | leaf | 2 |
| libkmod2 | runtime | leaf | 3 |
| libllvm21 | runtime | leaf | 2 |
| libmagic-mgc | runtime | leaf | 2 |
| libmagic1t64 | runtime | leaf | 2 |
| libmpc3 | build-only | leaf | 2 |
| libmpfr6 | build-only | leaf | 2 |
| libnetfilter-conntrack3 | runtime | leaf | 2 |
| libnfnetlink0 | runtime | leaf | 2 |
| libnftnl11 | runtime | leaf | 1 |
| libpango-1.0-0 | runtime | leaf | 1 |
| libpangocairo-1.0-0 | runtime | leaf | 1 |
| libpangoft2-1.0-0 | runtime | leaf | 1 |
| libpcsclite1 | runtime | leaf | 1 |
| libpixman-1-0 | runtime | leaf | 1 |
| libpng16-16t64 | runtime | leaf | 1 |
| libsensors-config | runtime | leaf | 4 |
| libsframe3 | build-only | leaf | 2 |
| libsystemd-shared | runtime | leaf | 5 |
| libthai-data | runtime | leaf | 1 |
| libthai0 | runtime | leaf | 1 |
| libubsan1 | build-only | leaf | 2 |
| libunwind8 | runtime | leaf | 1 |
| libx11-6 | runtime | leaf | 1 |
| libx11-data | runtime | leaf | 1 |
| libxau6 | runtime | leaf | 1 |
| libxcb-render0 | runtime | leaf | 1 |
| libxcb-shm0 | runtime | leaf | 1 |
| libxcb1 | runtime | leaf | 1 |
| libxdmcp6 | runtime | leaf | 1 |
| libxext6 | runtime | leaf | 1 |
| libxml2-16 | runtime | leaf | 5 |
| libxrender1 | runtime | leaf | 1 |
| linux-libc-dev | build-only | leaf | 5 |
| redis-server | runtime | leaf | 1 |
| shared-mime-info | runtime | leaf | 2 |
| systemd | runtime | leaf | 5 |
| wget | runtime | leaf | 1 |
| zlib1g-dev | build-only | leaf | 4 |

## Per container: runtime ARCHIVE packages lacking a 26.04 SDF

| container | runtime-missing total | leaf-specific | leaf-specific names |
|---|--:|--:|---|
| docker-bmp-watchdog | 35 | 0 |  |
| docker-dash-ha | 36 | 0 |  |
| docker-database | 36 | 0 |  |
| docker-dhcp-relay | 42 | 7 | ibverbs-providers, libexplain51t64, libibverbs1, libjsoncpp26, liblsof0, libpcap0.8t64, lsof |
| docker-eventd | 35 | 0 |  |
| docker-fpm-frr | 47 | 11 | cron-daemon-common, libgoogle-perftools4t64, liblsof0, libpci3, libpcre2-posix3, libsnmp-base, libsnmp40t64, libtcmalloc-minimal4t64, logrotate, lsof, pci.ids |
| docker-gbsyncd-agera2 | 37 | 1 | libprotobuf-lite32t64 |
| docker-gbsyncd-broncos | 37 | 1 | libprotobuf-lite32t64 |
| docker-gbsyncd-credo | 35 | 0 |  |
| docker-gbsyncd-vs | 69 | 33 | ibverbs-providers, libabsl20260107, libc-ares2, libdouble-conversion3, libfl2, libgc1, libgmpxx4ldbl, libgrpc++1.51t64, libgrpc29t64, libibverbs1, libitm1, libnanomsg5, libobjc4, libpcap0.8t64, libpcre2-16-0, libpfm4, libprotobuf-lite32t64, libprotoc32t64, libqt5core5t64, libqt5dbus5t64, libqt5network5t64, libquadmath0, libre2-11, libthrift-0.22.0, python3-grpcio, python3-ply, python3-protobuf, python3-psutil, python3-pyroute2, python3-scapy, python3-six, python3-thrift, tcpdump |
| docker-gnmi-sidecar | 35 | 0 |  |
| docker-gnmi-watchdog | 35 | 0 |  |
| docker-lldp | 39 | 4 | libpci3, libsnmp-base, libsnmp40t64, pci.ids |
| docker-macsec | 36 | 0 |  |
| docker-mux | 35 | 0 |  |
| docker-nat | 38 | 2 | bridge-utils, conntrack |
| docker-orchagent | 51 | 15 | arping, bridge-utils, conntrack, ifupdown, libibverbs1, libnet9, libpcap0.8t64, libpci3, ndisc6, ndppd, pci.ids, pciutils, python3-netifaces, python3-protobuf, tcpdump |
| docker-platform-monitor | 58 | 23 | dmidecode, ethtool, freeipmi-common, i2c-tools, ipmitool, libdbi1t64, libfreeipmi17, libi2c0, libnvme1t64, libpci3, librrd8t64, nvme-cli, pci.ids, pciutils, psmisc, python3-bottle, python3-netifaces, python3-smbus, rrdtool, smartmontools, udev, uuid-runtime, xxd |
| docker-restapi-sidecar | 35 | 0 |  |
| docker-router-advertiser | 36 | 1 | radvd |
| docker-sflow | 37 | 1 | dmidecode |
| docker-snmp | 44 | 9 | freeipmi-common, ipmitool, libfreeipmi17, libpci3, libsnmp-base, libsnmp40t64, pci.ids, snmp, snmpd |
| docker-sonic-bmp | 35 | 0 |  |
| docker-sonic-gnmi | 35 | 0 |  |
| docker-sonic-mgmt-framework | 35 | 0 |  |
| docker-sonic-otel | 35 | 0 |  |
| docker-syncd-brcm | 39 | 3 | ethtool, kmod, lz4 |
| docker-syncd-vs | 69 | 33 | ibverbs-providers, libabsl20260107, libc-ares2, libdouble-conversion3, libfl2, libgc1, libgmpxx4ldbl, libgrpc++1.51t64, libgrpc29t64, libibverbs1, libitm1, libnanomsg5, libobjc4, libpcap0.8t64, libpcre2-16-0, libpfm4, libprotobuf-lite32t64, libprotoc32t64, libqt5core5t64, libqt5dbus5t64, libqt5network5t64, libquadmath0, libre2-11, libthrift-0.22.0, python3-grpcio, python3-ply, python3-protobuf, python3-psutil, python3-pyroute2, python3-scapy, python3-six, python3-thrift, tcpdump |
| docker-sysmgr | 37 | 1 | libdbus-c++-1-0v5 |
| docker-teamd | 36 | 0 |  |

Shared-layer (base/config-engine/swss-layer) runtime packages lacking a 26.04 SDF — these hit every container: 36

- base: adduser, bsdutils, coreutils-from-uutils, e2fsprogs, libc-gconv-modules-extra, libdaemon0, libestr0, libext2fs2t64, libfastjson4, libpopt0, librelp0, libss2, login.defs, net-tools, python-is-python3, python3-autocommand, python3-inflect, python3-jaraco.context, python3-jaraco.functools, python3-jaraco.text, python3-more-itertools, python3-packaging, python3-typeguard, python3-typing-extensions, python3-zipp, rsync, rsyslog, rsyslog-relp, rust-coreutils
- config-engine: libpython3.14, python3-cffi, python3-cffi-backend, python3-pycparser, python3-redis, python3-yaml
- swss-layer: libprotobuf32t64
