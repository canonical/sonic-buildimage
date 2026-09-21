# SONiC resolute 容器包清单 / Container package inventory (vs + broadcom)

Generated 2026-09-17 from `sonic-buildimage-resolute/target/docker-*.gz` (34 images) by streaming `var/lib/dpkg/status` + python `*.dist-info` out of the OCI layers. No image was loaded or run.

Tags: **SELF** = built from source in this repo (`target/debs/resolute/`), **STOCK** = Ubuntu 26.04 archive package (chisel-releases slice candidate). Python: `pip` = installed under `/usr/local` from a wheel, `deb` = shipped by a Debian package.

## 1. Summary

| image | vs | bcm | parent | debs | +over parent | SELF | STOCK | inst. size MB | py dists (pip/deb) |
|---|:-:|:-:|---|--:|--:|--:|--:|--:|---|
| docker-base-resolute |  |  | - | 188 | 188 | 2 | 186 | 242 | 24 (11/13) |
| docker-config-engine-resolute |  |  | docker-base-resolute | 210 | 22 | 14 | 196 | 266 | 47 (29/18) |
| docker-swss-layer-resolute |  |  | docker-config-engine-resolute | 219 | 9 | 21 | 198 | 296 | 47 (29/18) |
| docker-bmp-watchdog | ✓ | ✓ | docker-config-engine-resolute | 210 | 0 | 14 | 196 | 266 | 47 (29/18) |
| docker-dash-engine | ✓ |  | EXTERNAL | 232 | 232 | 0 | 232 | 434 | 19 (15/4) |
| docker-dash-ha | ✓ | ✓ | docker-swss-layer-resolute | 220 | 1 | 22 | 198 | 314 | 47 (29/18) |
| docker-database | ✓ | ✓ | docker-config-engine-resolute | 213 | 3 | 15 | 198 | 272 | 48 (30/18) |
| docker-dhcp-relay | ✓ | ✓ | docker-config-engine-resolute | 242 | 32 | 20 | 222 | 311 | 52 (34/18) |
| docker-eventd | ✓ | ✓ | docker-config-engine-resolute | 210 | 0 | 14 | 196 | 266 | 47 (29/18) |
| docker-fpm-frr | ✓ | ✓ | docker-swss-layer-resolute | 240 | 21 | 24 | 216 | 361 | 49 (31/18) |
| docker-gbsyncd-agera2 |  | ✓ | docker-config-engine-resolute | 223 | 13 | 19 | 204 | 318 | 47 (29/18) |
| docker-gbsyncd-broncos |  | ✓ | docker-config-engine-resolute | 223 | 13 | 19 | 204 | 318 | 47 (29/18) |
| docker-gbsyncd-credo |  | ✓ | docker-config-engine-resolute | 217 | 7 | 17 | 200 | 297 | 47 (29/18) |
| docker-gbsyncd-vs | ✓ |  | docker-config-engine-resolute | 338 | 128 | 20 | 318 | 1016 | 55 (29/26) |
| docker-gnmi-sidecar | ✓ | ✓ | docker-config-engine-resolute | 210 | 0 | 14 | 196 | 266 | 47 (29/18) |
| docker-gnmi-watchdog | ✓ | ✓ | docker-config-engine-resolute | 210 | 0 | 14 | 196 | 266 | 47 (29/18) |
| docker-lldp | ✓ | ✓ | docker-config-engine-resolute | 219 | 9 | 16 | 203 | 274 | 48 (30/18) |
| docker-macsec | ✓ | ✓ | docker-swss-layer-resolute | 221 | 2 | 22 | 199 | 299 | 47 (29/18) |
| docker-mux | ✓ | ✓ | docker-config-engine-resolute | 215 | 5 | 15 | 200 | 277 | 47 (29/18) |
| docker-nat | ✓ | ✓ | docker-swss-layer-resolute | 227 | 8 | 21 | 206 | 299 | 47 (29/18) |
| docker-orchagent | ✓ | ✓ | docker-swss-layer-resolute | 239 | 20 | 21 | 218 | 319 | 51 (31/20) |
| docker-platform-monitor | ✓ | ✓ | docker-config-engine-resolute | 273 | 63 | 18 | 255 | 338 | 81 (60/21) |
| docker-restapi-sidecar | ✓ | ✓ | docker-config-engine-resolute | 210 | 0 | 14 | 196 | 266 | 47 (29/18) |
| docker-router-advertiser | ✓ | ✓ | docker-config-engine-resolute | 211 | 1 | 14 | 197 | 266 | 47 (29/18) |
| docker-sflow | ✓ | ✓ | docker-swss-layer-resolute | 223 | 4 | 24 | 199 | 297 | 47 (29/18) |
| docker-snmp | ✓ | ✓ | docker-config-engine-resolute | 221 | 11 | 15 | 206 | 284 | 53 (35/18) |
| docker-sonic-bmp | ✓ | ✓ | docker-config-engine-resolute | 211 | 1 | 15 | 196 | 266 | 48 (30/18) |
| docker-sonic-gnmi | ✓ | ✓ | docker-config-engine-resolute | 212 | 2 | 16 | 196 | 402 | 47 (29/18) |
| docker-sonic-mgmt-framework | ✓ | ✓ | docker-config-engine-resolute | 214 | 4 | 16 | 198 | 324 | 52 (34/18) |
| docker-sonic-otel | ✓ | ✓ | docker-config-engine-resolute | 212 | 2 | 14 | 198 | 592 | 47 (29/18) |
| docker-syncd-brcm |  | ✓ | docker-config-engine-resolute | 220 | 10 | 19 | 201 | 829 | 47 (29/18) |
| docker-syncd-vs | ✓ |  | docker-config-engine-resolute | 338 | 128 | 20 | 318 | 1016 | 55 (29/26) |
| docker-sysmgr | ✓ | ✓ | docker-config-engine-resolute | 213 | 3 | 15 | 198 | 270 | 47 (29/18) |
| docker-teamd | ✓ | ✓ | docker-swss-layer-resolute | 220 | 1 | 22 | 198 | 296 | 47 (29/18) |

## 2. Layer 0: docker-base-resolute (inherited by every SONiC container except dash-engine)


### debs (188, 242 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| bash | 5.3-2ubuntu1 | SELF | required/shells | 2020 |
| socat | 1.8.1.1-1 | SELF | optional/net | 1728 |
| adduser | 3.153ubuntu1 | STOCK | important/admin | 437 |
| apt | 3.2.0 | STOCK | required/admin | 4398 |
| base-files | 14ubuntu6.1 | STOCK | required/admin | 440 |
| base-passwd | 3.6.8 | STOCK | required/admin | 277 |
| bsdutils | 1:2.41.3-3ubuntu2 | STOCK | standard/utils | 250 |
| ca-certificates | 20260601~26.04.1 | STOCK | standard/misc | 333 |
| coreutils | 9.5-1ubuntu2+0.0.0~ubuntu25 | STOCK | optional/utils | 10 |
| coreutils-from-uutils | 0.0.0~ubuntu25 | STOCK | optional/utils | 237 |
| curl | 8.18.0-1ubuntu2.4 | STOCK | optional/web | 510 |
| dash | 0.5.12-12ubuntu3 | STOCK | required/shells | 200 |
| debconf | 1.5.92 | STOCK | important/admin | 507 |
| debianutils | 5.23.2build1 | STOCK | required/utils | 229 |
| diffutils | 1:3.12-1 | STOCK | required/utils | 448 |
| dpkg | 1.23.7ubuntu1 | STOCK | required/admin | 6206 |
| e2fsprogs | 1.47.2-3ubuntu4 | STOCK | important/admin | 1530 |
| findutils | 4.10.0-3build2 | STOCK | required/utils | 572 |
| gcc-16-base | 16-20260322-1ubuntu1 | STOCK | optional/libs | 105 |
| gnu-coreutils | 9.7-3ubuntu2 | STOCK | required/utils | 6920 |
| gpgv | 2.4.8-4ubuntu3 | STOCK | important/utils | 336 |
| grep | 3.12-1 | STOCK | required/utils | 364 |
| gzip | 1.14-1~exp2ubuntu1.1 | STOCK | required/utils | 212 |
| hostname | 3.25build1 | STOCK | required/admin | 50 |
| init-system-helpers | 1.69 | STOCK | required/admin | 133 |
| iproute2 | 6.19.0-1ubuntu1.1 | STOCK | important/net | 3257 |
| jq | 1.8.1-4ubuntu2 | STOCK | optional/utils | 122 |
| less | 668-1build1 | STOCK | important/text | 373 |
| libacl1 | 2.3.2-2 | STOCK | optional/libs | 74 |
| libapt-pkg7.0 | 3.2.0 | STOCK | optional/libs | 3699 |
| libatomic1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 49 |
| libattr1 | 1:2.5.2-4 | STOCK | optional/libs | 61 |
| libaudit-common | 1:4.1.2-1build1 | STOCK | optional/libs | 17 |
| libaudit1 | 1:4.1.2-1build1 | STOCK | optional/libs | 195 |
| libblkid1 | 2.41.3-3ubuntu2 | STOCK | optional/libs | 298 |
| libbpf1 | 1:1.6.3-1ubuntu1 | STOCK | optional/libs | 459 |
| libbrotli1 | 1.2.0-3build1 | STOCK | optional/libs | 886 |
| libbsd0 | 0.12.2-2build2 | STOCK | optional/libs | 129 |
| libbz2-1.0 | 1.0.8-6build2 | STOCK | important/libs | 99 |
| libc-bin | 2.43-2ubuntu2.3 | STOCK | required/libs | 2253 |
| libc-gconv-modules-extra | 2.43-2ubuntu2.3 | STOCK | optional/libs | 8079 |
| libc6 | 2.43-2ubuntu2.3 | STOCK | optional/libs | 5794 |
| libcap-ng0 | 0.8.5-4build5 | STOCK | optional/libs | 59 |
| libcap2 | 1:2.75-10ubuntu2 | STOCK | optional/libs | 93 |
| libcap2-bin | 1:2.75-10ubuntu2 | STOCK | important/utils | 133 |
| libcom-err2 | 1.47.2-3ubuntu4 | STOCK | optional/libs | 66 |
| libcrypt1 | 1:4.5.1-1 | STOCK | optional/libs | 244 |
| libcurl4t64 | 8.18.0-1ubuntu2.4 | STOCK | optional/libs | 1019 |
| libdaemon0 | 0.14-7.1ubuntu5 | STOCK | optional/libs | 51 |
| libdb5.3t64 | 5.3.28+dfsg2-10ubuntu1 | STOCK | optional/libs | 1817 |
| libdbus-1-3 | 1.16.2-2ubuntu4 | STOCK | optional/libs | 420 |
| libdebconfclient0 | 0.280ubuntu1 | STOCK | optional/libs | 39 |
| libelf1t64 | 0.194-4 | STOCK | optional/libs | 208 |
| libestr0 | 0.1.11-2build1 | STOCK | optional/libs | 34 |
| libexpat1 | 2.7.4-1 | STOCK | optional/libs | 411 |
| libext2fs2t64 | 1.47.2-3ubuntu4 | STOCK | optional/libs | 551 |
| libfastjson4 | 1.2304.0-2build1 | STOCK | optional/libs | 69 |
| libffi8 | 3.5.2-4 | STOCK | optional/libs | 87 |
| libgcc-s1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 201 |
| libgcrypt20 | 1.12.0-2ubuntu1 | STOCK | optional/libs | 1839 |
| libgdbm-compat4t64 | 1.26-1build1 | STOCK | optional/libs | 35 |
| libgdbm6t64 | 1.26-1build1 | STOCK | optional/libs | 97 |
| libgmp10 | 2:6.3.0+dfsg-5ubuntu2 | STOCK | optional/libs | 552 |
| libgnutls30t64 | 3.8.12-2ubuntu1.1 | STOCK | optional/libs | 2448 |
| libgpg-error0 | 1.58-2 | STOCK | optional/libs | 219 |
| libgssapi-krb5-2 | 1.22.1-2ubuntu4.1 | STOCK | optional/libs | 441 |
| libhogweed6t64 | 3.10.2-1 | STOCK | optional/libs | 350 |
| libidn2-0 | 2.3.8-4build1 | STOCK | optional/libs | 228 |
| libjansson4 | 2.14-2build4 | STOCK | optional/libs | 95 |
| libjemalloc2 | 5.3.0-4 | STOCK | optional/libs | 859 |
| libjq1 | 1.8.1-4ubuntu2 | STOCK | optional/libs | 377 |
| libk5crypto3 | 1.22.1-2ubuntu4.1 | STOCK | optional/libs | 257 |
| libkeyutils1 | 1.6.3-6ubuntu3 | STOCK | optional/libs | 42 |
| libkrb5-3 | 1.22.1-2ubuntu4.1 | STOCK | optional/libs | 1050 |
| libkrb5support0 | 1.22.1-2ubuntu4.1 | STOCK | optional/libs | 136 |
| libldap-common | 2.6.10+dfsg-1ubuntu5 | STOCK | optional/libs | 99 |
| libldap2 | 2.6.10+dfsg-1ubuntu5 | STOCK | optional/libs | 568 |
| liblz4-1 | 1.10.0-8 | STOCK | optional/libs | 185 |
| liblzf1 | 3.6-4build1 | STOCK | optional/libs | 33 |
| liblzma5 | 5.8.3-1 | STOCK | optional/libs | 473 |
| libmd0 | 1.1.0-2build4 | STOCK | optional/libs | 79 |
| libmnl0 | 1.0.5-3build1 | STOCK | optional/libs | 47 |
| libmount1 | 2.41.3-3ubuntu2 | STOCK | optional/libs | 401 |
| libncursesw6 | 6.6+20251231-1 | STOCK | optional/libs | 426 |
| libnettle8t64 | 3.10.2-1 | STOCK | optional/libs | 438 |
| libnghttp2-14 | 1.68.0-2ubuntu0.2 | STOCK | optional/libs | 196 |
| libnorm1t64 | 1.5.9+dfsg-4 | STOCK | optional/libs | 400 |
| libonig5 | 6.9.10-1build1 | STOCK | optional/libs | 652 |
| libp11-kit0 | 0.26.2-2 | STOCK | optional/libs | 1931 |
| libpam-modules | 1.7.0-5ubuntu3.1 | STOCK | required/admin | 1050 |
| libpam-modules-bin | 1.7.0-5ubuntu3.1 | STOCK | required/admin | 247 |
| libpam-runtime | 1.7.0-5ubuntu3.1 | STOCK | required/admin | 524 |
| libpam0g | 1.7.0-5ubuntu3.1 | STOCK | optional/libs | 207 |
| libpcre2-8-0 | 10.46-1build1 | STOCK | optional/libs | 708 |
| libperl5.40 | 5.40.1-7ubuntu0.1 | STOCK | optional/libs | 29326 |
| libpgm-5.3-0t64 | 5.3.128~dfsg-2.1build2 | STOCK | optional/libs | 307 |
| libpopt0 | 1.19+dfsg-2build1 | STOCK | optional/libs | 124 |
| libproc2-0 | 2:4.0.4-9ubuntu1 | STOCK | optional/libs | 241 |
| libpsl5t64 | 0.21.2-1.1build2 | STOCK | optional/libs | 108 |
| libpython3-stdlib | 3.14.3-0ubuntu2 | STOCK | optional/python | 26 |
| libpython3.14-minimal | 3.14.4-1ubuntu0.1 | STOCK | optional/python | 5642 |
| libpython3.14-stdlib | 3.14.4-1ubuntu0.1 | STOCK | optional/python | 10119 |
| libreadline8t64 | 8.3-4 | STOCK | optional/libs | 494 |
| librelp0 | 1.12.0-1 | STOCK | optional/libs | 114 |
| librtmp1 | 2.4+20151223.gitfa8646d.1-3 | STOCK | optional/libs | 141 |
| libsasl2-2 | 2.1.28+dfsg1-9ubuntu3 | STOCK | optional/libs | 152 |
| libsasl2-modules-db | 2.1.28+dfsg1-9ubuntu3 | STOCK | optional/libs | 75 |
| libseccomp2 | 2.6.0-2ubuntu5 | STOCK | optional/libs | 200 |
| libselinux1 | 3.9-4build1 | STOCK | optional/libs | 228 |
| libsemanage-common | 3.9-1build1 | STOCK | optional/libs | 20 |
| libsemanage2 | 3.9-1build1 | STOCK | optional/libs | 305 |
| libsepol2 | 3.9-2 | STOCK | optional/libs | 823 |
| libsmartcols1 | 2.41.3-3ubuntu2 | STOCK | optional/libs | 217 |
| libsodium23 | 1.0.18-2 | STOCK | optional/libs | 413 |
| libsqlite3-0 | 3.46.1-9ubuntu0.2 | STOCK | optional/libs | 1783 |
| libss2 | 1.47.2-3ubuntu4 | STOCK | optional/libs | 78 |
| libssh2-1t64 | 1.11.1-1ubuntu0.26.04.3 | STOCK | optional/libs | 457 |
| libssl3t64 | 3.5.5-1ubuntu3.5 | STOCK | optional/libs | 7982 |
| libstdc++6 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 3256 |
| libsystemd0 | 259.5-0ubuntu3.4 | STOCK | optional/libs | 1209 |
| libtasn1-6 | 4.21.0-2 | STOCK | optional/libs | 127 |
| libtext-charwidth-perl | 0.04-11build4 | STOCK | required/perl | 42 |
| libtext-wrapi18n-perl | 0.06-10 | STOCK | required/perl | 24 |
| libtinfo6 | 6.6+20251231-1 | STOCK | optional/libs | 569 |
| libtirpc-common | 1.3.7-0.1 | STOCK | optional/libs | 27 |
| libtirpc3t64 | 1.3.7-0.1 | STOCK | optional/libs | 219 |
| libudev1 | 259.5-0ubuntu3.4 | STOCK | optional/libs | 354 |
| libunistring5 | 1.3-2build1 | STOCK | optional/libs | 2081 |
| libuuid1 | 2.41.3-3ubuntu2 | STOCK | optional/libs | 90 |
| libwrap0 | 7.6.q-36build2 | STOCK | optional/libs | 107 |
| libxtables12 | 1.8.11-2ubuntu3 | STOCK | optional/libs | 104 |
| libxxhash0 | 0.8.3-2build1 | STOCK | optional/libs | 90 |
| libzmq5 | 4.3.5-1build3 | STOCK | optional/libs | 702 |
| libzstd1 | 1.5.7+dfsg-3 | STOCK | optional/libs | 802 |
| login | 1:4.16.0-2+really2.41.3-3ubuntu2 | STOCK | required/admin | 196 |
| login.defs | 1:4.17.4-2ubuntu3 | STOCK | required/admin | 103 |
| logsave | 1.47.2-3ubuntu4 | STOCK | optional/admin | 60 |
| mawk | 1.3.4.20260129-1 | STOCK | required/interpreters | 286 |
| media-types | 14.0.0build1 | STOCK | standard/net | 99 |
| mount | 2.41.3-3ubuntu2 | STOCK | required/admin | 356 |
| ncurses-base | 6.6+20251231-1 | STOCK | required/misc | 393 |
| ncurses-bin | 6.6+20251231-1 | STOCK | required/utils | 663 |
| net-tools | 2.10-2ubuntu1 | STOCK | important/net | 664 |
| netbase | 6.5build1 | STOCK | important/admin | 35 |
| openssl | 3.5.5-1ubuntu3.5 | STOCK | optional/utils | 2523 |
| openssl-provider-legacy | 3.5.5-1ubuntu3.5 | STOCK | optional/utils | 423 |
| passwd | 1:4.17.4-2ubuntu3 | STOCK | required/admin | 4348 |
| perl | 5.40.1-7ubuntu0.1 | STOCK | standard/perl | 836 |
| perl-base | 5.40.1-7ubuntu0.1 | STOCK | required/perl | 7955 |
| perl-modules-5.40 | 5.40.1-7ubuntu0.1 | STOCK | optional/libs | 19985 |
| procps | 2:4.0.4-9ubuntu1 | STOCK | important/admin | 1800 |
| python-is-python3 | 3.13.3-1+build1 | STOCK | optional/python | 16 |
| python3 | 3.14.3-0ubuntu2 | STOCK | optional/python | 80 |
| python3-autocommand | 2.2.2-4 | STOCK | optional/python | 61 |
| python3-inflect | 7.5.0-1build1 | STOCK | optional/python | 148 |
| python3-jaraco.context | 6.0.1-2 | STOCK | optional/python | 34 |
| python3-jaraco.functools | 4.1.0-1build1 | STOCK | optional/python | 47 |
| python3-jaraco.text | 4.0.0-1build1 | STOCK | optional/python | 47 |
| python3-minimal | 3.14.3-0ubuntu2 | STOCK | optional/python | 110 |
| python3-more-itertools | 10.8.0-1build1 | STOCK | optional/python | 308 |
| python3-packaging | 26.0-1 | STOCK | optional/python | 288 |
| python3-pip | 25.1.1+dfsg-1ubuntu2 | STOCK | optional/python | 10136 |
| python3-pkg-resources | 78.1.1-0.1build1 | STOCK | optional/python | 696 |
| python3-setuptools | 78.1.1-0.1build1 | STOCK | optional/python | 3897 |
| python3-typeguard | 4.4.4-2 | STOCK | optional/python | 165 |
| python3-typing-extensions | 4.15.0-2 | STOCK | optional/python | 511 |
| python3-wheel | 0.46.3-2 | STOCK | optional/python | 115 |
| python3-zipp | 3.23.0-1build1 | STOCK | optional/python | 45 |
| python3.14 | 3.14.4-1ubuntu0.1 | STOCK | optional/python | 912 |
| python3.14-minimal | 3.14.4-1ubuntu0.1 | STOCK | optional/python | 7398 |
| readline-common | 8.3-4 | STOCK | optional/utils | 81 |
| redis-tools | 5:8.0.5-1 | STOCK | optional/database | 7092 |
| rsync | 3.4.1+ds1-7ubuntu0.3 | STOCK | optional/net | 829 |
| rsyslog | 8.2512.0-1ubuntu4.1 | STOCK | optional/admin | 1840 |
| rsyslog-relp | 8.2512.0-1ubuntu4.1 | STOCK | optional/admin | 87 |
| rust-coreutils | 0.8.0-0ubuntu3 | STOCK | optional/utils | 15617 |
| sed | 4.9-2ubuntu1 | STOCK | required/utils | 344 |
| sensible-utils | 0.0.26build1 | STOCK | required/utils | 66 |
| sonic-build-hooks | 1.0 | STOCK | optional/devel |  |
| sysvinit-utils | 3.15-5ubuntu1 | STOCK | required/admin | 112 |
| tar | 1.35+dfsg-4ubuntu0.4 | STOCK | required/utils | 728 |
| tzdata | 2026c-0ubuntu0.26.04.1 | STOCK | required/localization | 1356 |
| ubuntu-keyring | 2023.11.28.1build1 | STOCK | important/misc | 29 |
| ucf | 3.0052ubuntu1 | STOCK | standard/utils | 148 |
| util-linux | 2.41.3-3ubuntu2 | STOCK | required/utils | 2887 |
| vim-common | 2:9.1.2141-1ubuntu4.8 | STOCK | important/editors | 2272 |
| vim-tiny | 2:9.1.2141-1ubuntu4.8 | STOCK | important/editors | 1975 |
| zlib1g | 1:1.3.dfsg+really1.3.1-1ubuntu3 | STOCK | required/libs | 171 |

### python dists

| dist | how |
|---|---|
| attrs-26.1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| autocommand-2.2.2.dist-info | deb `usr/lib/python3/dist-packages` |
| inflect-7.5.0.dist-info | deb `usr/lib/python3/dist-packages` |
| jaraco_context-6.0.1.dist-info | deb `usr/lib/python3/dist-packages` |
| jaraco_functools-4.1.0.dist-info | deb `usr/lib/python3/dist-packages` |
| jaraco_text-4.0.0.dist-info | deb `usr/lib/python3/dist-packages` |
| jinja2-3.1.6.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| jinjanator-25.3.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| jinjanator_plugins-25.1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| markupsafe-3.0.3.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| more_itertools-10.8.0.dist-info | deb `usr/lib/python3/dist-packages` |
| packaging-26.0.dist-info | deb `usr/lib/python3/dist-packages` |
| pip-25.1.1.dist-info | deb `usr/lib/python3/dist-packages` |
| pluggy-1.6.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| python_dotenv-1.2.3.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| pyyaml-6.0.3.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| setuptools-78.1.1.egg-info | deb `usr/lib/python3/dist-packages` |
| supervisor-4.3.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| supervisord_dependent_startup-1.4.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| toposort-1.10.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| typeguard-4.4.4.dist-info | deb `usr/lib/python3/dist-packages` |
| typing_extensions-4.15.0.dist-info | deb `usr/lib/python3/dist-packages` |
| wheel-0.46.3.dist-info | deb `usr/lib/python3/dist-packages` |
| zipp-3.23.0.dist-info | deb `usr/lib/python3/dist-packages` |

## Layer: docker-config-engine-resolute (parent docker-base-resolute)


### debs added (22, 23 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libnl-3-200 | 3.12.0-2 | SELF | optional/libs | 171 |
| libnl-cli-3-200 | 3.12.0-2 | SELF | optional/libs | 229 |
| libnl-genl-3-200 | 3.12.0-2 | SELF | optional/libs | 52 |
| libnl-nf-3-200 | 3.12.0-2 | SELF | optional/libs | 133 |
| libnl-route-3-200 | 3.12.0-2 | SELF | optional/libs | 684 |
| libswsscommon | 1.0.0 | SELF | optional/libs | 1265 |
| libyang3 | 3.13.6-1ubuntu0.1 | SELF | optional/libs | 1429 |
| python3-libyang | 3.1.0-1 | SELF | optional/python | 478 |
| python3-swsscommon | 1.0.0 | SELF | optional/libs | 3313 |
| sonic-db-cli | 1.0.0 | SELF | optional/libs | 63 |
| sonic-eventd | 1.0.0-0 | SELF | optional/devel | 554 |
| sonic-supervisord-utilities-rs | 1.0.0 | SELF | optional/net | 783 |
| apt-utils | 3.2.0 | STOCK | required/admin | 668 |
| libboost-serialization1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 2591 |
| libhiredis1.1.0 | 1.2.0-6ubuntu4 | STOCK | optional/libs | 136 |
| libpython3.14 | 3.14.4-1ubuntu0.2 | STOCK | optional/libs | 8131 |
| libyaml-0-2 | 0.2.5-2build3 | STOCK | optional/libs | 148 |
| python3-cffi | 2.0.0-3build1 | STOCK | optional/python | 417 |
| python3-cffi-backend | 2.0.0-3build1 | STOCK | optional/python | 242 |
| python3-pycparser | 3.0-1 | STOCK | optional/python | 432 |
| python3-redis | 6.4.0-1 | STOCK | optional/python | 1429 |
| python3-yaml | 6.0.3-1build1 | STOCK | optional/python | 561 |

### python dists added

| dist | how |
|---|---|
| bitarray-2.8.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| cffi-2.0.0.dist-info | deb `usr/lib/python3/dist-packages` |
| ijson-3.5.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| jsondiff-2.2.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| jsonpointer-3.1.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| libyang-3.1.0-py3.14.egg-info | deb `usr/lib/python3/dist-packages` |
| lxml-6.1.3.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| natsort-8.4.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| netaddr-0.8.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| pyang-2.7.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| pyangbind-0.8.7.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| pycparser-3.0.dist-info | deb `usr/lib/python3/dist-packages` |
| pyyaml-6.0.3.dist-info | deb `usr/lib/python3/dist-packages` |
| redis-6.4.0.dist-info | deb `usr/lib/python3/dist-packages` |
| redis_dump_load-1.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| regex-2026.9.10.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_config_engine-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_containercfgd-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_py_common-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_supervisord_utilities-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_yang_mgmt-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_yang_models-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| tabulate-0.9.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

## Layer: docker-swss-layer-resolute (parent docker-config-engine-resolute)


### debs added (9, 30 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libdashapi | 1.0.0 | SELF | optional/libs | 2794 |
| libnexthopgroup | 1.0.0 | SELF | optional/libs | 119 |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| libteam5 | 1.31-1build4 | SELF | optional/net | 79 |
| libteamdctl0 | 1.31-1build4 | SELF | optional/net | 48 |
| swss | 1.0.0 | SELF | optional/net | 18108 |
| iputils-ping | 3:20250605-1ubuntu1 | STOCK | important/net | 193 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |

## 3. Leaf containers: delta over parent


### docker-bmp-watchdog  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (0, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|

### docker-dash-engine  [vs]  parent=EXTERNAL

External base (not docker-base-resolute): libc6 2.31-0ubuntu9.18, 232 debs, 434 MB. Full list:

#### debs

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| adduser | 3.118ubuntu2 | STOCK | important/admin | 624 |
| apt | 2.0.10 | STOCK | important/admin | 4192 |
| base-files | 11ubuntu5.8 | STOCK | required/admin | 392 |
| base-passwd | 3.5.47 | STOCK | required/admin | 233 |
| bash | 5.0-6ubuntu1.2 | STOCK(name-collides-with-self-built) | required/shells | 1660 |
| binutils | 2.34-6ubuntu1.11 | STOCK | optional/devel | 109 |
| binutils-common | 2.34-6ubuntu1.11 | STOCK | optional/devel | 424 |
| binutils-x86-64-linux-gnu | 2.34-6ubuntu1.11 | STOCK | optional/devel | 9840 |
| bsdutils | 1:2.34-0.1ubuntu9.6 | STOCK | required/utils | 304 |
| build-essential | 12.8ubuntu1.1 | STOCK | optional/devel | 21 |
| bzip2 | 1.0.8-2 | STOCK | important/utils | 195 |
| ca-certificates | 20240203~20.04.1 | STOCK | standard/misc | 399 |
| coreutils | 8.30-3ubuntu2 | STOCK | required/utils | 7196 |
| cpp | 4:9.3.0-1ubuntu2 | STOCK | optional/interpreters | 64 |
| cpp-9 | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/interpreters | 26238 |
| cron | 3.0pl1-136ubuntu1 | STOCK | important/admin | 262 |
| dash | 0.5.10.2-6 | STOCK | required/shells | 212 |
| debconf | 1.5.73 | STOCK | required/admin | 520 |
| debianutils | 4.9.1 | STOCK | required/utils | 230 |
| diffutils | 1:3.7-3 | STOCK | required/utils | 532 |
| dirmngr | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 918 |
| dpkg | 1.19.7ubuntu3.2 | STOCK | required/admin | 6741 |
| dpkg-dev | 1.19.7ubuntu3.2 | STOCK | optional/utils | 2075 |
| e2fsprogs | 1.45.5-2ubuntu1.2 | STOCK | required/admin | 1492 |
| fakeroot | 1.24-1 | STOCK | optional/utils | 227 |
| fdisk | 2.34-0.1ubuntu9.6 | STOCK | required/utils | 506 |
| file | 1:5.38-4 | STOCK | standard/utils | 86 |
| findutils | 4.7.0-1ubuntu1 | STOCK | required/utils | 668 |
| g++ | 4:9.3.0-1ubuntu2 | STOCK | optional/devel | 16 |
| g++-9 | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/devel | 28016 |
| gcc | 4:9.3.0-1ubuntu2 | STOCK | optional/devel | 50 |
| gcc-10-base | 10.5.0-1ubuntu1~20.04 | STOCK | required/libs | 271 |
| gcc-9 | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/devel | 29840 |
| gcc-9-base | 9.4.0-1ubuntu1~20.04.2 | STOCK | required/libs | 265 |
| gnupg | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 413 |
| gnupg-l10n | 2.2.19-3ubuntu2.5 | STOCK | optional/localization | 380 |
| gnupg-utils | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 1554 |
| gpg | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 1135 |
| gpg-agent | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 911 |
| gpg-wks-client | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 275 |
| gpg-wks-server | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 255 |
| gpgconf | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 409 |
| gpgsm | 2.2.19-3ubuntu2.5 | STOCK | optional/utils | 568 |
| gpgv | 2.2.19-3ubuntu2.5 | STOCK | important/utils | 499 |
| grep | 3.4-1 | STOCK | required/utils | 496 |
| gzip | 1.10-0ubuntu4.1 | STOCK | required/utils | 245 |
| hostname | 3.23 | STOCK | required/admin | 54 |
| init-system-helpers | 1.57 | STOCK | required/admin | 133 |
| libacl1 | 2.2.53-6 | STOCK | required/libs | 70 |
| libalgorithm-diff-perl | 1.19.03-2 | STOCK | optional/perl | 106 |
| libalgorithm-diff-xs-perl | 0.04-6 | STOCK | optional/perl | 46 |
| libalgorithm-merge-perl | 0.08-3 | STOCK | optional/perl | 42 |
| libapt-pkg6.0 | 2.0.10 | STOCK | important/libs | 3328 |
| libasan5 | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/libs | 14965 |
| libasn1-8-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 795 |
| libassuan0 | 2.5.3-7ubuntu2 | STOCK | optional/libs | 105 |
| libatomic1 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 45 |
| libattr1 | 1:2.4.48-5 | STOCK | required/libs | 57 |
| libaudit-common | 1:2.8.5-2ubuntu6 | STOCK | required/libs | 24 |
| libaudit1 | 1:2.8.5-2ubuntu6 | STOCK | required/libs | 157 |
| libavl1 | 0.3.5-4 | STOCK | optional/libs | 26 |
| libbinutils | 2.34-6ubuntu1.11 | STOCK | optional/devel | 2696 |
| libblkid1 | 2.34-0.1ubuntu9.6 | STOCK | required/libs | 440 |
| libboost-filesystem1.71.0 | 1.71.0-6ubuntu6 | STOCK | optional/libs | 2074 |
| libboost-program-options1.71.0 | 1.71.0-6ubuntu6 | STOCK | optional/libs | 2526 |
| libboost-system1.71.0 | 1.71.0-6ubuntu6 | STOCK | optional/libs | 1973 |
| libboost-thread1.71.0 | 1.71.0-6ubuntu6 | STOCK | optional/libs | 2130 |
| libbz2-1.0 | 1.0.8-2 | STOCK | required/libs | 99 |
| libc-bin | 2.31-0ubuntu9.17 | STOCK | required/libs | 3714 |
| libc-dev-bin | 2.31-0ubuntu9.18 | STOCK | optional/libdevel | 443 |
| libc6 | 2.31-0ubuntu9.18 | STOCK | required/libs | 13239 |
| libc6-dev | 2.31-0ubuntu9.18 | STOCK | optional/libdevel | 19081 |
| libcap-ng0 | 0.7.9-2.1build1 | STOCK | required/libs | 45 |
| libcc1-0 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 156 |
| libcom-err2 | 1.45.5-2ubuntu1.2 | STOCK | required/libs | 101 |
| libcrypt-dev | 1:4.4.10-10ubuntu4 | STOCK | optional/libdevel | 321 |
| libcrypt1 | 1:4.4.10-10ubuntu4 | STOCK | required/libs | 226 |
| libctf-nobfd0 | 2.34-6ubuntu1.11 | STOCK | optional/devel | 199 |
| libctf0 | 2.34-6ubuntu1.11 | STOCK | optional/devel | 130 |
| libdb5.3 | 5.3.28+dfsg1-0.6ubuntu2 | STOCK | required/libs | 1749 |
| libdebconfclient0 | 0.251ubuntu1 | STOCK | required/libs | 74 |
| libdpkg-perl | 1.19.7ubuntu3.2 | STOCK | optional/perl | 2180 |
| libestr0 | 0.1.10-2.1 | STOCK | extra/libs | 30 |
| libev4 | 1:4.31-1 | STOCK | optional/libs | 90 |
| libexpat1 | 2.2.9-1ubuntu0.8 | STOCK | optional/libs | 403 |
| libexpat1-dev | 2.2.9-1ubuntu0.8 | STOCK | optional/libdevel | 857 |
| libext2fs2 | 1.45.5-2ubuntu1.2 | STOCK | required/libs | 541 |
| libfakeroot | 1.24-1 | STOCK | optional/utils | 157 |
| libfastjson4 | 0.99.8-2 | STOCK | optional/libs | 61 |
| libfdisk1 | 2.34-0.1ubuntu9.6 | STOCK | required/libs | 549 |
| libffi7 | 3.3-4 | STOCK | important/libs | 65 |
| libfile-fcntllock-perl | 0.22-3build4 | STOCK | optional/perl | 127 |
| libgcc-9-dev | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/libdevel | 13887 |
| libgcc-s1 | 10.5.0-1ubuntu1~20.04 | STOCK | required/libs | 120 |
| libgcrypt20 | 1.8.5-5ubuntu1.1 | STOCK | required/libs | 1224 |
| libgdbm-compat4 | 1.18.1-5 | STOCK | optional/libs | 40 |
| libgdbm6 | 1.18.1-5 | STOCK | optional/libs | 87 |
| libgmp10 | 2:6.2.0+dfsg-4ubuntu0.1 | STOCK | important/libs | 567 |
| libgnutls30 | 3.6.13-2ubuntu1.12 | STOCK | important/libs | 2192 |
| libgomp1 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 286 |
| libgpg-error0 | 1.37-1 | STOCK | required/libs | 176 |
| libgssapi3-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 325 |
| libhashkit-dev | 1.0.18-4.2ubuntu2 | STOCK | optional/libdevel | 144 |
| libhashkit2 | 1.0.18-4.2ubuntu2 | STOCK | optional/libs | 97 |
| libhcrypto4-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 275 |
| libheimbase1-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 114 |
| libheimntlm0-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 86 |
| libhogweed5 | 3.5.1+really3.5.1-2ubuntu0.2 | STOCK | important/libs | 237 |
| libhx509-5-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 361 |
| libidn2-0 | 2.2.0-2 | STOCK | important/libs | 216 |
| libisl22 | 0.22.1-1 | STOCK | optional/libs | 1926 |
| libitm1 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 115 |
| libjsoncpp1 | 1.7.4-3.1ubuntu2 | STOCK | extra/libs | 241 |
| libkrb5-26-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 666 |
| libksba8 | 1.3.5-2ubuntu0.20.04.2 | STOCK | optional/libs | 267 |
| libldap-2.4-2 | 2.4.49+dfsg-2ubuntu1.10 | STOCK | optional/libs | 523 |
| libldap-common | 2.4.49+dfsg-2ubuntu1.10 | STOCK | optional/libs | 102 |
| liblocale-gettext-perl | 1.07-4 | STOCK | required/perl | 54 |
| liblsan0 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 3222 |
| liblz4-1 | 1.9.2-2ubuntu0.20.04.1 | STOCK | required/libs | 149 |
| liblzma5 | 5.2.4-1ubuntu1.1 | STOCK | required/libs | 267 |
| libmagic-mgc | 1:5.38-4 | STOCK | optional/libs | 5723 |
| libmagic1 | 1:5.38-4 | STOCK | optional/libs | 220 |
| libmemcached-dev | 1.0.18-4.2ubuntu2 | STOCK | optional/libdevel | 915 |
| libmemcached11 | 1.0.18-4.2ubuntu2 | STOCK | optional/libs | 247 |
| libmemcachedutil2 | 1.0.18-4.2ubuntu2 | STOCK | optional/libs | 60 |
| libmount1 | 2.34-0.1ubuntu9.6 | STOCK | required/libs | 482 |
| libmpc3 | 1.1.0-1 | STOCK | extra/libs | 110 |
| libmpdec2 | 2.4.2-3 | STOCK | optional/libs | 243 |
| libmpfr6 | 4.0.2-1 | STOCK | optional/libs | 1096 |
| libncurses6 | 6.2-0ubuntu2.1 | STOCK | required/libs | 337 |
| libncursesw6 | 6.2-0ubuntu2.1 | STOCK | required/libs | 418 |
| libnettle7 | 3.5.1+really3.5.1-2ubuntu0.2 | STOCK | important/libs | 396 |
| libnpth0 | 1.6-1 | STOCK | optional/libs | 36 |
| libp11-kit0 | 0.23.20-1ubuntu0.1 | STOCK | important/libs | 1271 |
| libpam-modules | 1.3.1-5ubuntu4.7 | STOCK | required/admin | 1166 |
| libpam-modules-bin | 1.3.1-5ubuntu4.7 | STOCK | required/admin | 339 |
| libpam-runtime | 1.3.1-5ubuntu4.7 | STOCK | required/admin | 304 |
| libpam0g | 1.3.1-5ubuntu4.7 | STOCK | required/libs | 231 |
| libpcap0.8 | 1.9.1-3ubuntu1.20.04.1 | STOCK | optional/libs | 345 |
| libpcre2-8-0 | 10.34-7ubuntu0.1 | STOCK | required/libs | 596 |
| libpcre3 | 2:8.39-12ubuntu0.1 | STOCK | required/libs | 671 |
| libperl5.30 | 5.30.0-9ubuntu0.5 | STOCK | optional/libs | 27090 |
| libpopt0 | 1.16-14 | STOCK | optional/libs | 120 |
| libprocps8 | 2:3.3.16-1ubuntu2.4 | STOCK | required/libs | 128 |
| libprotobuf-c1 | 1.3.3-1ubuntu0.3 | STOCK | optional/libs | 59 |
| libpython3-dev | 3.8.2-0ubuntu2 | STOCK | optional/libdevel | 48 |
| libpython3-stdlib | 3.8.2-0ubuntu2 | STOCK | optional/python | 38 |
| libpython3.8 | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/libs | 5403 |
| libpython3.8-dev | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/libdevel | 19560 |
| libpython3.8-minimal | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/python | 4812 |
| libpython3.8-stdlib | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/python | 7900 |
| libquadmath0 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 304 |
| libreadline8 | 8.0-4 | STOCK | important/libs | 441 |
| libroken18-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 145 |
| libsasl2-2 | 2.1.27+dfsg-2ubuntu0.1 | STOCK | standard/libs | 152 |
| libsasl2-dev | 2.1.27+dfsg-2ubuntu0.1 | STOCK | optional/libdevel | 874 |
| libsasl2-modules-db | 2.1.27+dfsg-2ubuntu0.1 | STOCK | standard/libs | 66 |
| libseccomp2 | 2.5.1-1ubuntu1~20.04.2 | STOCK | important/libs | 152 |
| libselinux1 | 3.0-1build2 | STOCK | required/libs | 202 |
| libsemanage-common | 3.0-1build2 | STOCK | required/libs | 36 |
| libsemanage1 | 3.0-1build2 | STOCK | required/libs | 305 |
| libsepol1 | 3.0-1ubuntu0.1 | STOCK | required/libs | 734 |
| libsmartcols1 | 2.34-0.1ubuntu9.6 | STOCK | required/libs | 338 |
| libsqlite3-0 | 3.31.1-4ubuntu0.7 | STOCK | optional/libs | 1323 |
| libss2 | 1.45.5-2ubuntu1.2 | STOCK | required/libs | 109 |
| libssl-dev | 1.1.1f-1ubuntu2.24 | STOCK | optional/libdevel | 7831 |
| libssl1.1 | 1.1.1f-1ubuntu2.24 | STOCK | optional/libs | 4034 |
| libstdc++-9-dev | 9.4.0-1ubuntu1~20.04.2 | STOCK | optional/libdevel | 17645 |
| libstdc++6 | 10.5.0-1ubuntu1~20.04 | STOCK | important/libs | 2440 |
| libsystemd0 | 245.4-4ubuntu3.24 | STOCK | required/libs | 879 |
| libtasn1-6 | 4.16.0-2ubuntu0.1 | STOCK | important/libs | 125 |
| libtinfo6 | 6.2-0ubuntu2.1 | STOCK | required/libs | 537 |
| libtsan0 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 9012 |
| libubsan1 | 10.5.0-1ubuntu1~20.04 | STOCK | optional/libs | 3015 |
| libudev1 | 245.4-4ubuntu3.24 | STOCK | required/libs | 341 |
| libunistring2 | 0.9.10-2 | STOCK | important/libs | 1582 |
| libuuid1 | 2.34-0.1ubuntu9.6 | STOCK | required/libs | 123 |
| libwind0-heimdal | 7.7.0+dfsg-1ubuntu1.4 | STOCK | optional/libs | 206 |
| libxxhash0 | 0.7.3-1 | STOCK | optional/libs | 52 |
| libzstd1 | 1.4.4+dfsg-3ubuntu0.1 | STOCK | required/libs | 700 |
| linux-libc-dev | 5.4.0-216.236 | STOCK | optional/devel | 6332 |
| login | 1:4.8.1-1ubuntu5.20.04.5 | STOCK | required/admin | 932 |
| logrotate | 3.14.0-4ubuntu3 | STOCK | important/admin | 143 |
| logsave | 1.45.5-2ubuntu1.2 | STOCK | required/admin | 93 |
| lsb-base | 11.1.0ubuntu2 | STOCK | required/misc | 58 |
| make | 4.2.1-1.2 | STOCK | optional/devel | 384 |
| mawk | 1.3.4.20200120-2 | STOCK | required/utils | 233 |
| mime-support | 3.64ubuntu1 | STOCK | standard/net | 114 |
| mount | 2.34-0.1ubuntu9.6 | STOCK | required/admin | 434 |
| ncurses-base | 6.2-0ubuntu2.1 | STOCK | required/utils | 381 |
| ncurses-bin | 6.2-0ubuntu2.1 | STOCK | required/utils | 642 |
| net-tools | 1.60+git20180626.aebd88e-1ubuntu1.3 | STOCK | important/net | 836 |
| netbase | 6.1 | STOCK | important/admin | 43 |
| openssl | 1.1.1f-1ubuntu2.24 | STOCK | optional/utils | 1257 |
| passwd | 1:4.8.1-1ubuntu5.20.04.5 | STOCK | required/admin | 2669 |
| patch | 2.7.6-6 | STOCK | optional/vcs | 232 |
| perl | 5.30.0-9ubuntu0.5 | STOCK | standard/perl | 746 |
| perl-base | 5.30.0-9ubuntu0.5 | STOCK | required/perl | 10791 |
| perl-modules-5.30 | 5.30.0-9ubuntu0.5 | STOCK | standard/libs | 17230 |
| pinentry-curses | 1.1.0-3build1 | STOCK | optional/utils | 100 |
| procps | 2:3.3.16-1ubuntu2.4 | STOCK | required/admin | 816 |
| python-is-python3 | 3.8.2-4 | STOCK | optional/python | 10 |
| python-pip-whl | 20.0.2-5ubuntu1.11 | STOCK | optional/python | 2262 |
| python3 | 3.8.2-0ubuntu2 | STOCK | optional/python | 189 |
| python3-dev | 3.8.2-0ubuntu2 | STOCK | optional/python | 11 |
| python3-distutils | 3.8.10-0ubuntu1~20.04 | STOCK | optional/python | 1363 |
| python3-lib2to3 | 3.8.10-0ubuntu1~20.04 | STOCK | optional/python | 702 |
| python3-minimal | 3.8.2-0ubuntu2 | STOCK | optional/python | 120 |
| python3-pip | 20.0.2-5ubuntu1.11 | STOCK | optional/python | 1025 |
| python3-pkg-resources | 45.2.0-1ubuntu0.3 | STOCK | optional/python | 568 |
| python3-setuptools | 45.2.0-1ubuntu0.3 | STOCK | optional/python | 1435 |
| python3-wheel | 0.34.2-1ubuntu0.1 | STOCK | optional/python | 102 |
| python3.8 | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/python | 511 |
| python3.8-dev | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/python | 516 |
| python3.8-minimal | 3.8.10-0ubuntu1~20.04.18 | STOCK | optional/python | 5488 |
| readline-common | 8.0-4 | STOCK | important/utils | 79 |
| rsyslog | 8.2001.0-1ubuntu1.3 | STOCK | important/admin | 1655 |
| sed | 4.7-1 | STOCK | required/utils | 336 |
| sensible-utils | 0.0.12+nmu1 | STOCK | required/utils | 62 |
| sonic-build-hooks | 1.0 | STOCK | optional/devel |  |
| supervisor | 4.1.0-1ubuntu1 | STOCK | optional/admin | 1643 |
| sysvinit-utils | 2.96-2.1ubuntu1 | STOCK | required/admin | 74 |
| tar | 1.30+dfsg-7ubuntu0.20.04.4 | STOCK | required/utils | 884 |
| tcpdump | 4.9.3-4ubuntu0.3 | STOCK | optional/net | 1088 |
| tzdata | 2025b-0ubuntu0.20.04.1 | STOCK | required/localization | 3995 |
| ubuntu-keyring | 2020.02.11.4 | STOCK | important/misc | 46 |
| ucf | 3.0038+nmu1 | STOCK | standard/utils | 188 |
| util-linux | 2.34-0.1ubuntu9.6 | STOCK | required/utils | 4543 |
| xz-utils | 5.2.4-1ubuntu1.1 | STOCK | standard/utils | 348 |
| zlib1g | 1:1.2.11.dfsg-2ubuntu1.5 | STOCK | required/libs | 164 |
| zlib1g-dev | 1:1.2.11.dfsg-2ubuntu1.5 | STOCK | optional/libdevel | 593 |

#### python dists

| dist | how |
|---|---|
| Cython-0.29.36.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| cffi-1.17.1.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| coverage-7.6.1.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| grpcio-1.43.2.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| nnpy-0.1.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| pip-20.0.2.egg-info | deb `usr/lib/python3/dist-packages` |
| ptf-0.9.1.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| pycparser-2.23.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| pypcap-1.3.0.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| scapy-2.4.5.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| setuptools-45.2.0.egg-info | deb `usr/lib/python3/dist-packages` |
| six-1.16.0.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| six-1.17.0.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| supervisor-4.1.0.egg-info | deb `usr/lib/python3/dist-packages` |
| supervisord_dependent_startup-1.4.0.dist-info | pip `usr/local/lib/python3.8/dist-packages` |
| thrift-0.13.0.dist-info | pip `usr/local/lib/python3.8/site-packages` |
| toposort-1.10.dist-info | pip `usr/local/lib/python3.8/dist-packages` |
| wheel-0.34.2.egg-info | deb `usr/lib/python3/dist-packages` |
| wheel-0.45.1.dist-info | pip `usr/local/lib/python3.8/site-packages` |

### docker-dash-ha  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (1, 18 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| dash-ha | 1.0.0 | SELF | optional/net | 18638 |

### docker-database  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (3, 6 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libdashapi | 1.0.0 | SELF | optional/libs | 2794 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| redis-server | 5:8.0.5-1 | STOCK | optional/database | 177 |

#### python dists added

| dist | how |
|---|---|
| click-8.4.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-dhcp-relay  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (32, 46 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| isc-dhcp-relay | 4.4.3-P1-2 | SELF | optional/net | 2904 |
| libnl-3-dev | 3.12.0-2 | SELF | optional/libdevel | 631 |
| libnl-route-3-dev | 3.12.0-2 | SELF | optional/libdevel | 1338 |
| sonic-dhcp4relay | 1.0.0-0 | SELF | optional/devel | 1187 |
| sonic-dhcp6relay | 1.0.0-0 | SELF | optional/devel | 135 |
| sonic-dhcpmon | 1.0.0-0 | SELF | optional/devel | 239 |
| ibverbs-providers | 61.0-2ubuntu3 | STOCK | optional/net | 1378 |
| libboost-thread1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 2268 |
| libc-dev-bin | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 114 |
| libc6-dev | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 13792 |
| libdbus-1-dev | 1.16.2-2ubuntu4 | STOCK | optional/libdevel | 954 |
| libevent-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | STOCK | optional/libs | 383 |
| libevent-core-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | STOCK | optional/libs | 258 |
| libevent-pthreads-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | STOCK | optional/libs | 45 |
| libexplain51t64 | 1.4.D001-16 | STOCK | optional/libs | 1285 |
| libibverbs-dev | 61.0-2ubuntu3 | STOCK | optional/libdevel | 2514 |
| libibverbs1 | 61.0-2ubuntu3 | STOCK | optional/libs | 206 |
| libjsoncpp-dev | 1.9.6-5 | STOCK | optional/libdevel | 582 |
| libjsoncpp26 | 1.9.6-5 | STOCK | optional/libs | 245 |
| liblsof0 | 4.99.4+dfsg-2build2 | STOCK | optional/libs | 209 |
| libpcap-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 47 |
| libpcap0.8-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 907 |
| libpcap0.8t64 | 1.10.6-1ubuntu1 | STOCK | optional/libs | 407 |
| libpkgconf7 | 2.5.1-4 | STOCK | optional/libs | 127 |
| libsystemd-dev | 259.5-0ubuntu3.4 | STOCK | optional/libdevel | 5743 |
| linux-libc-dev | 7.0.0-31.31 | STOCK | optional/devel | 7919 |
| lsof | 4.99.4+dfsg-2build2 | STOCK | standard/utils | 480 |
| pkgconf | 2.5.1-4 | STOCK | optional/devel | 73 |
| pkgconf-bin | 2.5.1-4 | STOCK | optional/devel | 85 |
| rpcsvc-proto | 1.4.3-1build1 | STOCK | optional/libs | 249 |
| sgml-base | 1.31+nmu1build1 | STOCK | optional/text | 65 |
| xml-core | 0.19build1 | STOCK | optional/text | 114 |

#### python dists added

| dist | how |
|---|---|
| freezegun-1.5.5.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| psutil-7.2.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| python_dateutil-2.9.0.post0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| six-1.17.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_dhcp_utilities-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-eventd  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (0, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|

### docker-fpm-frr  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (21, 66 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| frr | 10.5.4-sonic-0 | SELF | optional/net | 38965 |
| frr-snmp | 10.5.4-sonic-0 | SELF | optional/net | 963 |
| libsensors5 | 1:3.6.2-2build1 | SELF | optional/libs | 88 |
| cron | 3.0pl1-200ubuntu1 | STOCK | important/admin | 235 |
| cron-daemon-common | 3.0pl1-200ubuntu1 | STOCK | optional/admin | 54 |
| libcares2 | 1.34.6-1 | STOCK | optional/libs | 259 |
| libgoogle-perftools4t64 | 2.18.1-1 | STOCK | optional/libs | 798 |
| libjson-c5 | 0.18+ds-3 | STOCK | optional/libs | 103 |
| liblsof0 | 4.99.4+dfsg-2build2 | STOCK | optional/libs | 209 |
| libpci3 | 1:3.14.0-1build2 | STOCK | optional/libs | 117 |
| libpcre2-posix3 | 10.46-1build1 | STOCK | optional/libs | 36 |
| libsensors-config | 1:3.6.2-2build1 | STOCK | optional/utils | 28 |
| libsnmp-base | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 655 |
| libsnmp40t64 | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 3734 |
| libsystemd-shared | 259.5-0ubuntu3.4 | STOCK | optional/libs | 7383 |
| libtcmalloc-minimal4t64 | 2.18.1-1 | STOCK | optional/libs | 432 |
| libunwind8 | 1.8.3-0ubuntu1 | STOCK | optional/libs | 199 |
| logrotate | 3.22.0-1build1 | STOCK | important/admin | 145 |
| lsof | 4.99.4+dfsg-2build2 | STOCK | standard/utils | 480 |
| pci.ids | 0.0~2026.02.12-1 | STOCK | optional/admin | 1561 |
| systemd | 259.5-0ubuntu3.4 | STOCK | important/admin | 10988 |

#### python dists added

| dist | how |
|---|---|
| sonic_bgpcfgd-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_frr_mgmt_framework-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-gbsyncd-agera2  [bcm]  parent=docker-config-engine-resolute


#### debs added (13, 53 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsaiagera2 | 3.14.0-4 | SELF | extra/libs |  |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| sswsyncd | 1.0.0 | SELF | optional/net | 46 |
| syncd | 1.0.0 | SELF | optional/net | 8342 |
| libc-dev-bin | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 114 |
| libc6-dev | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 13792 |
| libprotobuf-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 12067 |
| libprotobuf-lite32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 890 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| linux-libc-dev | 7.0.0-31.31 | STOCK | optional/devel | 7919 |
| rpcsvc-proto | 1.4.3-1build1 | STOCK | optional/libs | 249 |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1ubuntu3.1 | STOCK | optional/libdevel | 1324 |

### docker-gbsyncd-broncos  [bcm]  parent=docker-config-engine-resolute


#### debs added (13, 53 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsaibroncos | 3.12 | SELF | extra/libs |  |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| sswsyncd | 1.0.0 | SELF | optional/net | 46 |
| syncd | 1.0.0 | SELF | optional/net | 8342 |
| libc-dev-bin | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 114 |
| libc6-dev | 2.43-2ubuntu2.4 | STOCK | optional/libdevel | 13792 |
| libprotobuf-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 12067 |
| libprotobuf-lite32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 890 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| linux-libc-dev | 7.0.0-31.31 | STOCK | optional/devel | 7919 |
| rpcsvc-proto | 1.4.3-1build1 | STOCK | optional/libs | 249 |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1ubuntu3.1 | STOCK | optional/libdevel | 1324 |

### docker-gbsyncd-credo  [bcm]  parent=docker-config-engine-resolute


#### debs added (7, 31 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| syncd | 1.0.0 | SELF | optional/net | 8342 |
| saicredo-blackhawk | 1.2.6 | STOCK | optional/devel | 865 |
| saicredo-crt88322 | 1.2.6 | STOCK | optional/devel | 972 |
| saicredo-owl | 1.2.6 | STOCK | optional/devel | 1077 |
| saicredo-saicredo | 1.2.6 | STOCK | optional/devel | 14323 |

### docker-gbsyncd-vs  [vs]  parent=docker-config-engine-resolute


#### debs added (128, 750 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libnl-3-dev | 3.12.0-2 | SELF | optional/libdevel | 631 |
| libnl-route-3-dev | 3.12.0-2 | SELF | optional/libdevel | 1338 |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| libsaivs | 1.0.0 | SELF | optional/libs | 1663 |
| syncd-vs | 1.0.0 | SELF | optional/net | 8341 |
| autoconf | 2.72-3.1ubuntu2 | STOCK | optional/devel | 2091 |
| automake | 1:1.18.1-3build1 | STOCK | optional/devel | 1640 |
| autotools-dev | 20240727.1build1 | STOCK | optional/devel | 147 |
| binutils | 2.46-3ubuntu2 | STOCK | optional/devel | 1150 |
| binutils-common | 2.46-3ubuntu2 | STOCK | optional/devel | 532 |
| binutils-x86-64-linux-gnu | 2.46-3ubuntu2 | STOCK | optional/devel | 6109 |
| clang | 1:21.1.6-71 | STOCK | optional/devel | 21 |
| clang-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 498 |
| cpp | 4:15.2.0-5ubuntu1 | STOCK | optional/interpreters | 37 |
| cpp-15 | 15.2.0-16ubuntu1 | STOCK | optional/interpreters | 11 |
| cpp-15-x86-64-linux-gnu | 15.2.0-16ubuntu1 | STOCK | optional/interpreters | 37902 |
| cpp-x86-64-linux-gnu | 4:15.2.0-5ubuntu1 | STOCK | optional/interpreters | 21 |
| file | 1:5.46-5build2 | STOCK | standard/utils | 60 |
| flex | 2.6.4-8.2build2 | STOCK | optional/devel | 932 |
| gcc-15-base | 15.2.0-16ubuntu1 | STOCK | optional/libs | 106 |
| ibverbs-providers | 61.0-2ubuntu3 | STOCK | optional/net | 1378 |
| libabsl-dev | 20260107.0-4 | STOCK | optional/libdevel | 8532 |
| libabsl20260107 | 20260107.0-4 | STOCK | optional/libs | 2794 |
| libasan8 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 11430 |
| libbinutils | 2.46-3ubuntu2 | STOCK | optional/devel | 2416 |
| libbpf-dev | 1:1.6.3-1ubuntu1 | STOCK | optional/libdevel | 1136 |
| libc-ares-dev | 1.34.6-1 | STOCK | optional/libdevel | 879 |
| libc-ares2 | 1.34.6-1 | STOCK | optional/oldlibs | 32 |
| libc-dev-bin | 2.43-2ubuntu2.3 | STOCK | optional/libdevel | 114 |
| libc6-dev | 2.43-2ubuntu2.3 | STOCK | optional/libdevel | 13792 |
| libcares2 | 1.34.6-1 | STOCK | optional/libs | 259 |
| libclang-common-21-dev | 1:21.1.8-6ubuntu1 | STOCK | optional/libdevel | 14666 |
| libclang-cpp21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 58935 |
| libclang1-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 31988 |
| libctf-nobfd0 | 2.46-3ubuntu2 | STOCK | optional/devel | 323 |
| libctf0 | 2.46-3ubuntu2 | STOCK | optional/devel | 244 |
| libdbus-1-dev | 1.16.2-2ubuntu4 | STOCK | optional/libdevel | 954 |
| libdouble-conversion3 | 3.4.0-1 | STOCK | optional/libs | 106 |
| libedit2 | 3.1-20251016-1 | STOCK | optional/libs | 258 |
| libelf-dev | 0.194-4 | STOCK | optional/libdevel | 486 |
| libfl-dev | 2.6.4-8.2build2 | STOCK | optional/libdevel | 54 |
| libfl2 | 2.6.4-8.2build2 | STOCK | optional/libs | 57 |
| libgc-dev | 1:8.2.12-1 | STOCK | optional/libdevel | 988 |
| libgc1 | 1:8.2.12-1 | STOCK | optional/libs | 409 |
| libgcc-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 18201 |
| libglib2.0-0t64 | 2.88.0-1 | STOCK | optional/libs | 4330 |
| libgmp-dev | 2:6.3.0+dfsg-5ubuntu2 | STOCK | optional/libdevel | 1600 |
| libgmpxx4ldbl | 2:6.3.0+dfsg-5ubuntu2 | STOCK | optional/libs | 54 |
| libgomp1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 406 |
| libgprofng0 | 2.46-3ubuntu2 | STOCK | optional/devel | 4066 |
| libgrpc++-dev | 1.51.1-8ubuntu1 | STOCK | optional/libdevel | 7007 |
| libgrpc++1.51t64 | 1.51.1-8ubuntu1 | STOCK | optional/libs | 2094 |
| libgrpc-dev | 1.51.1-8ubuntu1 | STOCK | optional/libdevel | 33596 |
| libgrpc29t64 | 1.51.1-8ubuntu1 | STOCK | optional/libs | 10271 |
| libhwasan0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 5144 |
| libibverbs-dev | 61.0-2ubuntu3 | STOCK | optional/libdevel | 2514 |
| libibverbs1 | 61.0-2ubuntu3 | STOCK | optional/libs | 206 |
| libicu78 | 78.2-2ubuntu1 | STOCK | optional/libs | 38705 |
| libisl23 | 0.27-1build1 | STOCK | optional/libs | 2060 |
| libitm1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 119 |
| libllvm21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 135358 |
| liblsan0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 4023 |
| libmagic-mgc | 1:5.46-5build2 | STOCK | optional/libs | 10135 |
| libmagic1t64 | 1:5.46-5build2 | STOCK | optional/libs | 225 |
| libmpc3 | 1.3.1-3 | STOCK | optional/libs | 149 |
| libmpfr6 | 4.2.2-3 | STOCK | optional/libs | 1215 |
| libnanomsg-dev | 1.1.5+dfsg-1.2 | STOCK | optional/libdevel | 1265 |
| libnanomsg5 | 1.1.5+dfsg-1.2 | STOCK | optional/libs | 288 |
| libobjc-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 1511 |
| libobjc4 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 214 |
| libpcap-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 47 |
| libpcap0.8-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 907 |
| libpcap0.8t64 | 1.10.6-1ubuntu1 | STOCK | optional/libs | 407 |
| libpcre2-16-0 | 10.46-1build1 | STOCK | optional/libs | 651 |
| libpfm4 | 4.13.0+git106-g3e4031b-1 | STOCK | optional/libs | 3742 |
| libpkgconf7 | 2.5.1-4 | STOCK | optional/libs | 127 |
| libprotobuf-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 12067 |
| libprotobuf-lite32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 890 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| libprotoc-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 7115 |
| libprotoc32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 2352 |
| libqt5core5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 6188 |
| libqt5dbus5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 765 |
| libqt5network5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 2528 |
| libquadmath0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 304 |
| libre2-11 | 20250805-1build3 | STOCK | optional/libs | 424 |
| libre2-dev | 20250805-1build3 | STOCK | optional/libdevel | 1027 |
| libsframe3 | 2.46-3ubuntu2 | STOCK | optional/devel | 140 |
| libssl-dev | 3.5.5-1ubuntu3.4 | STOCK | optional/libdevel | 16030 |
| libstdc++-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 25491 |
| libsystemd-dev | 259.5-0ubuntu3.4 | STOCK | optional/libdevel | 5743 |
| libsystemd-shared | 259.5-0ubuntu3.4 | STOCK | optional/libs | 7383 |
| libthrift-0.22.0 | 0.22.0-3ubuntu1 | STOCK | optional/libs | 980 |
| libthrift-dev | 0.22.0-3ubuntu1 | STOCK | optional/libdevel | 4007 |
| libtool | 2.5.4-9 | STOCK | optional/devel | 881 |
| libtsan2 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 9295 |
| libubsan1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 3527 |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | STOCK | optional/libs | 1565 |
| libzstd-dev | 1.5.7+dfsg-3 | STOCK | optional/libdevel | 1297 |
| linux-libc-dev | 7.0.0-30.30 | STOCK | optional/devel | 7893 |
| llvm | 1:21.1.6-71 | STOCK | optional/devel | 156 |
| llvm-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 86355 |
| llvm-21-linker-tools | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 4295 |
| llvm-21-runtime | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 1719 |
| llvm-runtime | 1:21.1.6-71 | STOCK | optional/devel | 16 |
| m4 | 1.4.21-1 | STOCK | optional/interpreters | 580 |
| pkg-config | 2.5.1-4 | STOCK | optional/oldlibs | 34 |
| pkgconf | 2.5.1-4 | STOCK | optional/devel | 73 |
| pkgconf-bin | 2.5.1-4 | STOCK | optional/devel | 85 |
| protobuf-compiler | 3.21.12-15ubuntu1 | STOCK | optional/devel | 113 |
| protobuf-compiler-grpc | 1.51.1-8ubuntu1 | STOCK | optional/libs | 161 |
| python3-grpcio | 1.51.1-8ubuntu1 | STOCK | optional/python | 6448 |
| python3-ply | 3.11-10 | STOCK | optional/python | 249 |
| python3-protobuf | 3.21.12-15ubuntu1 | STOCK | optional/python | 699 |
| python3-psutil | 7.1.0-1ubuntu1 | STOCK | optional/python | 1109 |
| python3-pyroute2 | 0.8.1-4 | STOCK | optional/python | 1809 |
| python3-scapy | 2.7.0+dfsg1-1 | STOCK | optional/python | 9334 |
| python3-six | 1.17.0-2build1 | STOCK | optional/python | 59 |
| python3-thrift | 0.22.0-3ubuntu1 | STOCK | optional/python | 318 |
| rpcsvc-proto | 1.4.3-1build1 | STOCK | optional/libs | 249 |
| sgml-base | 1.31+nmu1build1 | STOCK | optional/text | 65 |
| shared-mime-info | 2.4-5build3 | STOCK | optional/misc | 2876 |
| systemd | 259.5-0ubuntu3.4 | STOCK | important/admin | 10988 |
| tcpdump | 4.99.6-1 | STOCK | optional/net | 1325 |
| thrift-compiler | 0.22.0-3ubuntu1 | STOCK | optional/devel | 4232 |
| xml-core | 0.19build1 | STOCK | optional/text | 114 |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1ubuntu3 | STOCK | optional/libdevel | 1326 |

#### python dists added

| dist | how |
|---|---|
| grpcio-1.51.1.egg-info | deb `usr/lib/python3/dist-packages` |
| lxml-6.1.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| ply-3.11.egg-info | deb `usr/lib/python3/dist-packages` |
| protobuf-4.21.12.egg-info | deb `usr/lib/python3/dist-packages` |
| psutil-7.1.0.dist-info | deb `usr/lib/python3/dist-packages` |
| pyroute2-0.8.1.dist-info | deb `usr/lib/python3/dist-packages` |
| regex-2026.7.19.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| scapy-2.7.1.dist-info | deb `usr/lib/python3/dist-packages` |
| six-1.17.0.dist-info | deb `usr/lib/python3/dist-packages` |
| thrift-0.22.0.egg-info | deb `usr/lib/python3/dist-packages` |

### docker-gnmi-sidecar  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (0, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|

### docker-gnmi-watchdog  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (0, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|

### docker-lldp  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (9, 8 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsensors5 | 1:3.6.2-2build1 | SELF | optional/libs | 88 |
| lldpd | 1.0.19-1 | SELF | optional/net | 567 |
| libevent-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | STOCK | optional/libs | 383 |
| libpci3 | 1:3.14.0-1build2 | STOCK | optional/libs | 117 |
| libsensors-config | 1:3.6.2-2build1 | STOCK | optional/utils | 28 |
| libsnmp-base | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 655 |
| libsnmp40t64 | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 3734 |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | STOCK | optional/libs | 1565 |
| pci.ids | 0.0~2026.02.12-1 | STOCK | optional/admin | 1561 |

#### python dists added

| dist | how |
|---|---|
| sonic_d-2.0.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-macsec  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (2, 3 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| wpasupplicant | 2:2.9.0-14 | SELF | optional/net | 2999 |
| libpcsclite1 | 2.4.1-1 | STOCK | optional/libs | 77 |

### docker-mux  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (5, 12 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| sonic-linkmgrd | 1.0.0-1 | SELF | optional/devel | 1316 |
| libboost-filesystem1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 2284 |
| libboost-log1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 3748 |
| libboost-program-options1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 2408 |
| libboost-thread1.83.0 | 1.83.0-5ubuntu5 | STOCK | optional/libs | 2268 |

### docker-nat  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (8, 3 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| bridge-utils | 1.7.1-4ubuntu3 | STOCK | optional/net | 112 |
| conntrack | 1:1.4.9-1 | STOCK | optional/net | 122 |
| iptables | 1.8.11-2ubuntu3 | STOCK | optional/net | 2436 |
| libip4tc2 | 1.8.11-2ubuntu3 | STOCK | optional/libs | 68 |
| libip6tc2 | 1.8.11-2ubuntu3 | STOCK | optional/libs | 68 |
| libnetfilter-conntrack3 | 1.1.1-1 | STOCK | optional/libs | 148 |
| libnfnetlink0 | 1.0.2-3build1 | STOCK | optional/libs | 51 |
| libnftnl11 | 1.3.1-1 | STOCK | optional/libs | 248 |

### docker-orchagent  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (20, 24 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| arping | 2.28-1 | STOCK | optional/net | 85 |
| bridge-utils | 1.7.1-4ubuntu3 | STOCK | optional/net | 112 |
| conntrack | 1:1.4.9-1 | STOCK | optional/net | 122 |
| ifupdown | 0.8.43ubuntu3 | STOCK | important/admin | 206 |
| libibverbs1 | 61.0-2ubuntu3 | STOCK | optional/libs | 206 |
| libkmod2 | 34.2-2ubuntu2 | STOCK | optional/libs | 146 |
| libnet9 | 1.3+dfsg-3 | STOCK | optional/libs | 130 |
| libnetfilter-conntrack3 | 1.1.1-1 | STOCK | optional/libs | 148 |
| libnfnetlink0 | 1.0.2-3build1 | STOCK | optional/libs | 51 |
| libpcap0.8t64 | 1.10.6-1ubuntu1 | STOCK | optional/libs | 407 |
| libpci3 | 1:3.14.0-1build2 | STOCK | optional/libs | 117 |
| libsystemd-shared | 259.5-0ubuntu3.4 | STOCK | optional/libs | 7383 |
| ndisc6 | 1.0.8-1 | STOCK | optional/net | 276 |
| ndppd | 0.2.5-6build2 | STOCK | optional/net | 144 |
| pci.ids | 0.0~2026.02.12-1 | STOCK | optional/admin | 1561 |
| pciutils | 1:3.14.0-1build2 | STOCK | standard/admin | 256 |
| python3-netifaces | 0.11.0-2build7 | STOCK | optional/python | 56 |
| python3-protobuf | 3.21.12-15ubuntu1 | STOCK | optional/python | 699 |
| systemd | 259.5-0ubuntu3.4 | STOCK | important/admin | 10988 |
| tcpdump | 4.99.6-1 | STOCK | optional/net | 1325 |

#### python dists added

| dist | how |
|---|---|
| netifaces-0.11.0.egg-info | deb `usr/lib/python3/dist-packages` |
| protobuf-4.21.12.egg-info | deb `usr/lib/python3/dist-packages` |
| pyroute2-0.5.14.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| scapy-2.6.1.dev0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-platform-monitor  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (63, 72 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| fancontrol | 1:3.6.2-2build1 | SELF | optional/utils | 85 |
| libsensors5 | 1:3.6.2-2build1 | SELF | optional/libs | 88 |
| lm-sensors | 1:3.6.2-2build1 | SELF | optional/utils | 390 |
| sensord | 1:3.6.2-2build1 | SELF | optional/utils | 73 |
| dmidecode | 3.6-2ubuntu1 | STOCK | important/utils | 227 |
| ethtool | 1:6.19-1 | STOCK | optional/net | 1080 |
| fontconfig | 2.17.1-3ubuntu1 | STOCK | optional/fonts | 468 |
| fontconfig-config | 2.17.1-3ubuntu1 | STOCK | optional/fonts | 243 |
| fonts-dejavu-core | 2.37-8build1 | STOCK | optional/fonts | 2292 |
| fonts-dejavu-mono | 2.37-8build1 | STOCK | optional/fonts | 1281 |
| freeipmi-common | 1.6.16-1ubuntu0.1 | STOCK | optional/admin | 368 |
| i2c-tools | 4.4-2build3 | STOCK | optional/utils | 324 |
| ipmitool | 1.8.19-10ubuntu1 | STOCK | optional/utils | 6122 |
| iputils-ping | 3:20250605-1ubuntu1 | STOCK | important/net | 193 |
| libcairo2 | 1.18.4-3 | STOCK | optional/libs | 1394 |
| libdatrie1 | 0.2.14-1 | STOCK | optional/libs | 53 |
| libdbi1t64 | 0.9.0-6.1build2 | STOCK | optional/libs | 95 |
| libfontconfig1 | 2.17.1-3ubuntu1 | STOCK | optional/libs | 358 |
| libfreeipmi17 | 1.6.16-1ubuntu0.1 | STOCK | optional/libs | 5406 |
| libfreetype6 | 2.14.2+dfsg-1ubuntu0.1 | STOCK | optional/libs | 906 |
| libfribidi0 | 1.0.16-5 | STOCK | optional/libs | 144 |
| libglib2.0-0t64 | 2.88.0-1 | STOCK | optional/libs | 4330 |
| libgraphite2-3 | 1.3.14-11ubuntu1.1 | STOCK | optional/libs | 171 |
| libharfbuzz0b | 12.3.2-2 | STOCK | optional/libs | 1252 |
| libi2c0 | 4.4-2build3 | STOCK | optional/libs | 31 |
| libjson-c5 | 0.18+ds-3 | STOCK | optional/libs | 103 |
| libkmod2 | 34.2-2ubuntu2 | STOCK | optional/libs | 146 |
| libnvme1t64 | 1.16.1-4 | STOCK | optional/libs | 278 |
| libpango-1.0-0 | 1.57.0-1 | STOCK | optional/libs | 556 |
| libpangocairo-1.0-0 | 1.57.0-1 | STOCK | optional/libs | 109 |
| libpangoft2-1.0-0 | 1.57.0-1 | STOCK | optional/libs | 172 |
| libpci3 | 1:3.14.0-1build2 | STOCK | optional/libs | 117 |
| libpixman-1-0 | 0.46.4-1 | STOCK | optional/libs | 757 |
| libpng16-16t64 | 1.6.57-1 | STOCK | optional/libs | 346 |
| librrd-dev | 1.9.0-2build1 | STOCK | optional/libdevel | 815 |
| librrd8t64 | 1.9.0-2build1 | STOCK | optional/libs | 434 |
| libsensors-config | 1:3.6.2-2build1 | STOCK | optional/utils | 28 |
| libsystemd-shared | 259.5-0ubuntu3.4 | STOCK | optional/libs | 7383 |
| libthai-data | 0.1.30-1 | STOCK | optional/libs | 594 |
| libthai0 | 0.1.30-1 | STOCK | optional/libs | 97 |
| libx11-6 | 2:1.8.13-1 | STOCK | optional/libs | 1381 |
| libx11-data | 2:1.8.13-1 | STOCK | optional/x11 | 1343 |
| libxau6 | 1:1.0.11-1build2 | STOCK | optional/libs | 33 |
| libxcb-render0 | 1.17.0-2ubuntu1 | STOCK | optional/libs | 81 |
| libxcb-shm0 | 1.17.0-2ubuntu1 | STOCK | optional/libs | 31 |
| libxcb1 | 1.17.0-2ubuntu1 | STOCK | optional/libs | 205 |
| libxdmcp6 | 1:1.1.5-2 | STOCK | optional/libs | 41 |
| libxext6 | 2:1.3.4-1build3 | STOCK | optional/libs | 103 |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | STOCK | optional/libs | 1565 |
| libxrender1 | 1:0.9.12-1build1 | STOCK | optional/libs | 58 |
| nvme-cli | 2.16-1 | STOCK | optional/admin | 2254 |
| pci.ids | 0.0~2026.02.12-1 | STOCK | optional/admin | 1561 |
| pciutils | 1:3.14.0-1build2 | STOCK | standard/admin | 256 |
| psmisc | 23.7-2ubuntu2 | STOCK | optional/admin | 604 |
| python3-bottle | 0.13.2-1.1 | STOCK | optional/python | 204 |
| python3-netifaces | 0.11.0-2build7 | STOCK | optional/python | 56 |
| python3-smbus | 4.4-2build3 | STOCK | optional/python | 46 |
| rrdtool | 1.9.0-2build1 | STOCK | optional/utils | 1116 |
| smartmontools | 7.5-2 | STOCK | optional/utils | 2250 |
| systemd | 259.5-0ubuntu3.4 | STOCK | important/admin | 10988 |
| udev | 259.5-0ubuntu3.4 | STOCK | important/admin | 10382 |
| uuid-runtime | 2.41.3-3ubuntu2.2 | STOCK | optional/utils | 163 |
| xxd | 2:9.1.2141-1ubuntu4.9 | STOCK | optional/editors | 165 |

#### python dists added

| dist | how |
|---|---|
| blkinfo-0.2.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| bottle-0.13.2.egg-info | deb `usr/lib/python3/dist-packages` |
| certifi-2026.6.17.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| charset_normalizer-3.4.7.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| enum34-1.1.10.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| grpcio-1.71.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| grpcio_tools-1.71.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| guacamole-0.9.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| idna-3.18.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| jsonschema-2.6.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| libpci-0.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| netifaces-0.11.0.egg-info | deb `usr/lib/python3/dist-packages` |
| protobuf-5.29.6.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| psutil-7.2.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| python_dateutil-2.9.0.post0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| requests-2.34.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| six-1.17.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| smbus-1.1.egg-info | deb `usr/lib/python3/dist-packages` |
| smbus2-0.6.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_bmcctld-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_chassisd-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_ledd-1.1.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_pcied-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_platform_common-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_platform_pddf_common-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_psud-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_sensormond-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_stormond-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_syseepromd-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_thermalctld-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_xcvrd-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_ycabled-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| thrift-0.13.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| urllib3-2.7.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-restapi-sidecar  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (0, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|

### docker-router-advertiser  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (1, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| radvd | 1:2.20-1build1 | STOCK | optional/net | 167 |

### docker-sflow  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (4, 1 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| hsflowd | 2.0.51-26 | SELF | optional/admin | 462 |
| psample | 1.1-1 | SELF | optional/devel | 59 |
| sflowtool | 5.04 | SELF | optional/devel | 555 |
| dmidecode | 3.6-2ubuntu1 | STOCK | important/utils | 227 |

### docker-snmp  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (11, 19 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsensors5 | 1:3.6.2-2build1 | SELF | optional/libs | 88 |
| freeipmi-common | 1.6.16-1ubuntu0.1 | STOCK | optional/admin | 368 |
| ipmitool | 1.8.19-10ubuntu1 | STOCK | optional/utils | 6122 |
| libfreeipmi17 | 1.6.16-1ubuntu0.1 | STOCK | optional/libs | 5406 |
| libpci3 | 1:3.14.0-1build2 | STOCK | optional/libs | 117 |
| libsensors-config | 1:3.6.2-2build1 | STOCK | optional/utils | 28 |
| libsnmp-base | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 655 |
| libsnmp40t64 | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/libs | 3734 |
| pci.ids | 0.0~2026.02.12-1 | STOCK | optional/admin | 1561 |
| snmp | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/net | 716 |
| snmpd | 5.9.4+dfsg-2ubuntu3 | STOCK | optional/net | 151 |

#### python dists added

| dist | how |
|---|---|
| asyncsnmp-2.1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| hiredis-3.4.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| psutil-7.2.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| python_arptable-0.0.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| smbus-1.1.post2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| sonic_platform_common-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-sonic-bmp  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (1, 1 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| sonic-bmp | 0.1 | SELF | optional/devel | 947 |

#### python dists added

| dist | how |
|---|---|
| sonic_bmpcfgd_services-1.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-sonic-gnmi  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (2, 136 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| sonic-gnmi | 0.1 | SELF | optional/devel | 138328 |
| sonic-mgmt-common | 1.0.0 | SELF | extra/net | 996 |

### docker-sonic-mgmt-framework  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (4, 58 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| sonic-mgmt-common | 1.0.0 | SELF | extra/net | 996 |
| sonic-mgmt-framework | 1.0-01 | SELF | extra/net | 56765 |
| libcjson1 | 1.7.19-2 | STOCK | optional/libs | 83 |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | STOCK | optional/libs | 1565 |

#### python dists added

| dist | how |
|---|---|
| certifi-2026.6.17.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| charset_normalizer-3.4.7.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| idna-3.18.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| requests-2.34.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| urllib3-2.7.0.dist-info | pip `usr/local/lib/python3.14/dist-packages` |

### docker-sonic-otel  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (2, 326 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| otelcol-contrib | 0.144.0 | STOCK | optional/ | 333138 |
| wget | 1.25.0-2ubuntu4.4 | STOCK | standard/web | 732 |

### docker-syncd-brcm  [bcm]  parent=docker-config-engine-resolute


#### debs added (10, 563 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libsaibcm | 15.2.0.0.0.0.11.1 | SELF | extra/libs | 557601 |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| sswsyncd | 1.0.0 | SELF | optional/net | 46 |
| syncd | 1.0.0 | SELF | optional/net | 8342 |
| ethtool | 1:6.19-1 | STOCK | optional/net | 1080 |
| kmod | 34.2-2ubuntu2 | STOCK | important/admin | 264 |
| libkmod2 | 34.2-2ubuntu2 | STOCK | optional/libs | 146 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| lz4 | 1.10.0-8 | STOCK | optional/utils | 138 |

### docker-syncd-vs  [vs]  parent=docker-config-engine-resolute


#### debs added (128, 750 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libnl-3-dev | 3.12.0-2 | SELF | optional/libdevel | 631 |
| libnl-route-3-dev | 3.12.0-2 | SELF | optional/libdevel | 1338 |
| libsaimetadata | 1.0.0 | SELF | optional/libs | 4491 |
| libsairedis | 1.0.0 | SELF | optional/libs | 1762 |
| libsaivs | 1.0.0 | SELF | optional/libs | 1663 |
| syncd-vs | 1.0.0 | SELF | optional/net | 8341 |
| autoconf | 2.72-3.1ubuntu2 | STOCK | optional/devel | 2091 |
| automake | 1:1.18.1-3build1 | STOCK | optional/devel | 1640 |
| autotools-dev | 20240727.1build1 | STOCK | optional/devel | 147 |
| binutils | 2.46-3ubuntu2 | STOCK | optional/devel | 1150 |
| binutils-common | 2.46-3ubuntu2 | STOCK | optional/devel | 532 |
| binutils-x86-64-linux-gnu | 2.46-3ubuntu2 | STOCK | optional/devel | 6109 |
| clang | 1:21.1.6-71 | STOCK | optional/devel | 21 |
| clang-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 498 |
| cpp | 4:15.2.0-5ubuntu1 | STOCK | optional/interpreters | 37 |
| cpp-15 | 15.2.0-16ubuntu1 | STOCK | optional/interpreters | 11 |
| cpp-15-x86-64-linux-gnu | 15.2.0-16ubuntu1 | STOCK | optional/interpreters | 37902 |
| cpp-x86-64-linux-gnu | 4:15.2.0-5ubuntu1 | STOCK | optional/interpreters | 21 |
| file | 1:5.46-5build2 | STOCK | standard/utils | 60 |
| flex | 2.6.4-8.2build2 | STOCK | optional/devel | 932 |
| gcc-15-base | 15.2.0-16ubuntu1 | STOCK | optional/libs | 106 |
| ibverbs-providers | 61.0-2ubuntu3 | STOCK | optional/net | 1378 |
| libabsl-dev | 20260107.0-4 | STOCK | optional/libdevel | 8532 |
| libabsl20260107 | 20260107.0-4 | STOCK | optional/libs | 2794 |
| libasan8 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 11430 |
| libbinutils | 2.46-3ubuntu2 | STOCK | optional/devel | 2416 |
| libbpf-dev | 1:1.6.3-1ubuntu1 | STOCK | optional/libdevel | 1136 |
| libc-ares-dev | 1.34.6-1 | STOCK | optional/libdevel | 879 |
| libc-ares2 | 1.34.6-1 | STOCK | optional/oldlibs | 32 |
| libc-dev-bin | 2.43-2ubuntu2.3 | STOCK | optional/libdevel | 114 |
| libc6-dev | 2.43-2ubuntu2.3 | STOCK | optional/libdevel | 13792 |
| libcares2 | 1.34.6-1 | STOCK | optional/libs | 259 |
| libclang-common-21-dev | 1:21.1.8-6ubuntu1 | STOCK | optional/libdevel | 14666 |
| libclang-cpp21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 58935 |
| libclang1-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 31988 |
| libctf-nobfd0 | 2.46-3ubuntu2 | STOCK | optional/devel | 323 |
| libctf0 | 2.46-3ubuntu2 | STOCK | optional/devel | 244 |
| libdbus-1-dev | 1.16.2-2ubuntu4 | STOCK | optional/libdevel | 954 |
| libdouble-conversion3 | 3.4.0-1 | STOCK | optional/libs | 106 |
| libedit2 | 3.1-20251016-1 | STOCK | optional/libs | 258 |
| libelf-dev | 0.194-4 | STOCK | optional/libdevel | 486 |
| libfl-dev | 2.6.4-8.2build2 | STOCK | optional/libdevel | 54 |
| libfl2 | 2.6.4-8.2build2 | STOCK | optional/libs | 57 |
| libgc-dev | 1:8.2.12-1 | STOCK | optional/libdevel | 988 |
| libgc1 | 1:8.2.12-1 | STOCK | optional/libs | 409 |
| libgcc-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 18201 |
| libglib2.0-0t64 | 2.88.0-1 | STOCK | optional/libs | 4330 |
| libgmp-dev | 2:6.3.0+dfsg-5ubuntu2 | STOCK | optional/libdevel | 1600 |
| libgmpxx4ldbl | 2:6.3.0+dfsg-5ubuntu2 | STOCK | optional/libs | 54 |
| libgomp1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 406 |
| libgprofng0 | 2.46-3ubuntu2 | STOCK | optional/devel | 4066 |
| libgrpc++-dev | 1.51.1-8ubuntu1 | STOCK | optional/libdevel | 7007 |
| libgrpc++1.51t64 | 1.51.1-8ubuntu1 | STOCK | optional/libs | 2094 |
| libgrpc-dev | 1.51.1-8ubuntu1 | STOCK | optional/libdevel | 33596 |
| libgrpc29t64 | 1.51.1-8ubuntu1 | STOCK | optional/libs | 10271 |
| libhwasan0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 5144 |
| libibverbs-dev | 61.0-2ubuntu3 | STOCK | optional/libdevel | 2514 |
| libibverbs1 | 61.0-2ubuntu3 | STOCK | optional/libs | 206 |
| libicu78 | 78.2-2ubuntu1 | STOCK | optional/libs | 38705 |
| libisl23 | 0.27-1build1 | STOCK | optional/libs | 2060 |
| libitm1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 119 |
| libllvm21 | 1:21.1.8-6ubuntu1 | STOCK | optional/libs | 135358 |
| liblsan0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 4023 |
| libmagic-mgc | 1:5.46-5build2 | STOCK | optional/libs | 10135 |
| libmagic1t64 | 1:5.46-5build2 | STOCK | optional/libs | 225 |
| libmpc3 | 1.3.1-3 | STOCK | optional/libs | 149 |
| libmpfr6 | 4.2.2-3 | STOCK | optional/libs | 1215 |
| libnanomsg-dev | 1.1.5+dfsg-1.2 | STOCK | optional/libdevel | 1265 |
| libnanomsg5 | 1.1.5+dfsg-1.2 | STOCK | optional/libs | 288 |
| libobjc-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 1511 |
| libobjc4 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 214 |
| libpcap-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 47 |
| libpcap0.8-dev | 1.10.6-1ubuntu1 | STOCK | optional/libdevel | 907 |
| libpcap0.8t64 | 1.10.6-1ubuntu1 | STOCK | optional/libs | 407 |
| libpcre2-16-0 | 10.46-1build1 | STOCK | optional/libs | 651 |
| libpfm4 | 4.13.0+git106-g3e4031b-1 | STOCK | optional/libs | 3742 |
| libpkgconf7 | 2.5.1-4 | STOCK | optional/libs | 127 |
| libprotobuf-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 12067 |
| libprotobuf-lite32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 890 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |
| libprotoc-dev | 3.21.12-15ubuntu1 | STOCK | optional/libdevel | 7115 |
| libprotoc32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 2352 |
| libqt5core5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 6188 |
| libqt5dbus5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 765 |
| libqt5network5t64 | 5.15.18+dfsg-1ubuntu1 | STOCK | optional/libs | 2528 |
| libquadmath0 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 304 |
| libre2-11 | 20250805-1build3 | STOCK | optional/libs | 424 |
| libre2-dev | 20250805-1build3 | STOCK | optional/libdevel | 1027 |
| libsframe3 | 2.46-3ubuntu2 | STOCK | optional/devel | 140 |
| libssl-dev | 3.5.5-1ubuntu3.4 | STOCK | optional/libdevel | 16030 |
| libstdc++-15-dev | 15.2.0-16ubuntu1 | STOCK | optional/libdevel | 25491 |
| libsystemd-dev | 259.5-0ubuntu3.4 | STOCK | optional/libdevel | 5743 |
| libsystemd-shared | 259.5-0ubuntu3.4 | STOCK | optional/libs | 7383 |
| libthrift-0.22.0 | 0.22.0-3ubuntu1 | STOCK | optional/libs | 980 |
| libthrift-dev | 0.22.0-3ubuntu1 | STOCK | optional/libdevel | 4007 |
| libtool | 2.5.4-9 | STOCK | optional/devel | 881 |
| libtsan2 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 9295 |
| libubsan1 | 16-20260322-1ubuntu1 | STOCK | optional/libs | 3527 |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | STOCK | optional/libs | 1565 |
| libzstd-dev | 1.5.7+dfsg-3 | STOCK | optional/libdevel | 1297 |
| linux-libc-dev | 7.0.0-30.30 | STOCK | optional/devel | 7893 |
| llvm | 1:21.1.6-71 | STOCK | optional/devel | 156 |
| llvm-21 | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 86355 |
| llvm-21-linker-tools | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 4295 |
| llvm-21-runtime | 1:21.1.8-6ubuntu1 | STOCK | optional/devel | 1719 |
| llvm-runtime | 1:21.1.6-71 | STOCK | optional/devel | 16 |
| m4 | 1.4.21-1 | STOCK | optional/interpreters | 580 |
| pkg-config | 2.5.1-4 | STOCK | optional/oldlibs | 34 |
| pkgconf | 2.5.1-4 | STOCK | optional/devel | 73 |
| pkgconf-bin | 2.5.1-4 | STOCK | optional/devel | 85 |
| protobuf-compiler | 3.21.12-15ubuntu1 | STOCK | optional/devel | 113 |
| protobuf-compiler-grpc | 1.51.1-8ubuntu1 | STOCK | optional/libs | 161 |
| python3-grpcio | 1.51.1-8ubuntu1 | STOCK | optional/python | 6448 |
| python3-ply | 3.11-10 | STOCK | optional/python | 249 |
| python3-protobuf | 3.21.12-15ubuntu1 | STOCK | optional/python | 699 |
| python3-psutil | 7.1.0-1ubuntu1 | STOCK | optional/python | 1109 |
| python3-pyroute2 | 0.8.1-4 | STOCK | optional/python | 1809 |
| python3-scapy | 2.7.0+dfsg1-1 | STOCK | optional/python | 9334 |
| python3-six | 1.17.0-2build1 | STOCK | optional/python | 59 |
| python3-thrift | 0.22.0-3ubuntu1 | STOCK | optional/python | 318 |
| rpcsvc-proto | 1.4.3-1build1 | STOCK | optional/libs | 249 |
| sgml-base | 1.31+nmu1build1 | STOCK | optional/text | 65 |
| shared-mime-info | 2.4-5build3 | STOCK | optional/misc | 2876 |
| systemd | 259.5-0ubuntu3.4 | STOCK | important/admin | 10988 |
| tcpdump | 4.99.6-1 | STOCK | optional/net | 1325 |
| thrift-compiler | 0.22.0-3ubuntu1 | STOCK | optional/devel | 4232 |
| xml-core | 0.19build1 | STOCK | optional/text | 114 |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1ubuntu3 | STOCK | optional/libdevel | 1326 |

#### python dists added

| dist | how |
|---|---|
| grpcio-1.51.1.egg-info | deb `usr/lib/python3/dist-packages` |
| lxml-6.1.2.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| ply-3.11.egg-info | deb `usr/lib/python3/dist-packages` |
| protobuf-4.21.12.egg-info | deb `usr/lib/python3/dist-packages` |
| psutil-7.1.0.dist-info | deb `usr/lib/python3/dist-packages` |
| pyroute2-0.8.1.dist-info | deb `usr/lib/python3/dist-packages` |
| regex-2026.7.19.dist-info | pip `usr/local/lib/python3.14/dist-packages` |
| scapy-2.7.1.dist-info | deb `usr/lib/python3/dist-packages` |
| six-1.17.0.dist-info | deb `usr/lib/python3/dist-packages` |
| thrift-0.22.0.egg-info | deb `usr/lib/python3/dist-packages` |

### docker-sysmgr  [vs / bcm]  parent=docker-config-engine-resolute


#### debs added (3, 4 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| sysmgr | 1.0.0 | SELF | optional/net | 1204 |
| libdbus-c++-1-0v5 | 0.9.0-16 | STOCK | optional/libs | 202 |
| libprotobuf32t64 | 3.21.12-15ubuntu1 | STOCK | optional/libs | 3107 |

### docker-teamd  [vs / bcm]  parent=docker-swss-layer-resolute


#### debs added (1, 0 MB)

| package | version | tag | prio/section | KB |
|---|---|---|---|--:|
| libteam-utils | 1.31-1build4 | SELF | optional/net | 312 |

## 4. Union of STOCK Ubuntu packages across all vs+bcm containers (chisel slice scope)

422 distinct stock packages.

| package | used by N images | only in |
|---|--:|---|
| adduser | 30 |  |
| apt | 30 |  |
| apt-utils | 30 |  |
| base-files | 30 |  |
| base-passwd | 30 |  |
| bsdutils | 30 |  |
| ca-certificates | 30 |  |
| coreutils | 30 |  |
| coreutils-from-uutils | 30 |  |
| curl | 30 |  |
| dash | 30 |  |
| debconf | 30 |  |
| debianutils | 30 |  |
| diffutils | 30 |  |
| dpkg | 30 |  |
| e2fsprogs | 30 |  |
| findutils | 30 |  |
| gcc-16-base | 30 |  |
| gnu-coreutils | 30 |  |
| gpgv | 30 |  |
| grep | 30 |  |
| gzip | 30 |  |
| hostname | 30 |  |
| init-system-helpers | 30 |  |
| iproute2 | 30 |  |
| jq | 30 |  |
| less | 30 |  |
| libacl1 | 30 |  |
| libapt-pkg7.0 | 30 |  |
| libatomic1 | 30 |  |
| libattr1 | 30 |  |
| libaudit-common | 30 |  |
| libaudit1 | 30 |  |
| libblkid1 | 30 |  |
| libboost-serialization1.83.0 | 30 |  |
| libbpf1 | 30 |  |
| libbrotli1 | 30 |  |
| libbsd0 | 30 |  |
| libbz2-1.0 | 30 |  |
| libc-bin | 30 |  |
| libc-gconv-modules-extra | 30 |  |
| libc6 | 30 |  |
| libcap-ng0 | 30 |  |
| libcap2 | 30 |  |
| libcap2-bin | 30 |  |
| libcom-err2 | 30 |  |
| libcrypt1 | 30 |  |
| libcurl4t64 | 30 |  |
| libdaemon0 | 30 |  |
| libdb5.3t64 | 30 |  |
| libdbus-1-3 | 30 |  |
| libdebconfclient0 | 30 |  |
| libelf1t64 | 30 |  |
| libestr0 | 30 |  |
| libexpat1 | 30 |  |
| libext2fs2t64 | 30 |  |
| libfastjson4 | 30 |  |
| libffi8 | 30 |  |
| libgcc-s1 | 30 |  |
| libgcrypt20 | 30 |  |
| libgdbm-compat4t64 | 30 |  |
| libgdbm6t64 | 30 |  |
| libgmp10 | 30 |  |
| libgnutls30t64 | 30 |  |
| libgpg-error0 | 30 |  |
| libgssapi-krb5-2 | 30 |  |
| libhiredis1.1.0 | 30 |  |
| libhogweed6t64 | 30 |  |
| libidn2-0 | 30 |  |
| libjansson4 | 30 |  |
| libjemalloc2 | 30 |  |
| libjq1 | 30 |  |
| libk5crypto3 | 30 |  |
| libkeyutils1 | 30 |  |
| libkrb5-3 | 30 |  |
| libkrb5support0 | 30 |  |
| libldap-common | 30 |  |
| libldap2 | 30 |  |
| liblz4-1 | 30 |  |
| liblzf1 | 30 |  |
| liblzma5 | 30 |  |
| libmd0 | 30 |  |
| libmnl0 | 30 |  |
| libmount1 | 30 |  |
| libncursesw6 | 30 |  |
| libnettle8t64 | 30 |  |
| libnghttp2-14 | 30 |  |
| libnorm1t64 | 30 |  |
| libonig5 | 30 |  |
| libp11-kit0 | 30 |  |
| libpam-modules | 30 |  |
| libpam-modules-bin | 30 |  |
| libpam-runtime | 30 |  |
| libpam0g | 30 |  |
| libpcre2-8-0 | 30 |  |
| libperl5.40 | 30 |  |
| libpgm-5.3-0t64 | 30 |  |
| libpopt0 | 30 |  |
| libproc2-0 | 30 |  |
| libpsl5t64 | 30 |  |
| libpython3-stdlib | 30 |  |
| libpython3.14 | 30 |  |
| libpython3.14-minimal | 30 |  |
| libpython3.14-stdlib | 30 |  |
| libreadline8t64 | 30 |  |
| librelp0 | 30 |  |
| librtmp1 | 30 |  |
| libsasl2-2 | 30 |  |
| libsasl2-modules-db | 30 |  |
| libseccomp2 | 30 |  |
| libselinux1 | 30 |  |
| libsemanage-common | 30 |  |
| libsemanage2 | 30 |  |
| libsepol2 | 30 |  |
| libsmartcols1 | 30 |  |
| libsodium23 | 30 |  |
| libsqlite3-0 | 30 |  |
| libss2 | 30 |  |
| libssh2-1t64 | 30 |  |
| libssl3t64 | 30 |  |
| libstdc++6 | 30 |  |
| libsystemd0 | 30 |  |
| libtasn1-6 | 30 |  |
| libtext-charwidth-perl | 30 |  |
| libtext-wrapi18n-perl | 30 |  |
| libtinfo6 | 30 |  |
| libtirpc-common | 30 |  |
| libtirpc3t64 | 30 |  |
| libudev1 | 30 |  |
| libunistring5 | 30 |  |
| libuuid1 | 30 |  |
| libwrap0 | 30 |  |
| libxtables12 | 30 |  |
| libxxhash0 | 30 |  |
| libyaml-0-2 | 30 |  |
| libzmq5 | 30 |  |
| libzstd1 | 30 |  |
| login | 30 |  |
| login.defs | 30 |  |
| logsave | 30 |  |
| mawk | 30 |  |
| media-types | 30 |  |
| mount | 30 |  |
| ncurses-base | 30 |  |
| ncurses-bin | 30 |  |
| net-tools | 30 |  |
| netbase | 30 |  |
| openssl | 30 |  |
| openssl-provider-legacy | 30 |  |
| passwd | 30 |  |
| perl | 30 |  |
| perl-base | 30 |  |
| perl-modules-5.40 | 30 |  |
| procps | 30 |  |
| python-is-python3 | 30 |  |
| python3 | 30 |  |
| python3-autocommand | 30 |  |
| python3-cffi | 30 |  |
| python3-cffi-backend | 30 |  |
| python3-inflect | 30 |  |
| python3-jaraco.context | 30 |  |
| python3-jaraco.functools | 30 |  |
| python3-jaraco.text | 30 |  |
| python3-minimal | 30 |  |
| python3-more-itertools | 30 |  |
| python3-packaging | 30 |  |
| python3-pip | 30 |  |
| python3-pkg-resources | 30 |  |
| python3-pycparser | 30 |  |
| python3-redis | 30 |  |
| python3-setuptools | 30 |  |
| python3-typeguard | 30 |  |
| python3-typing-extensions | 30 |  |
| python3-wheel | 30 |  |
| python3-yaml | 30 |  |
| python3-zipp | 30 |  |
| python3.14 | 30 |  |
| python3.14-minimal | 30 |  |
| readline-common | 30 |  |
| redis-tools | 30 |  |
| rsync | 30 |  |
| rsyslog | 30 |  |
| rsyslog-relp | 30 |  |
| rust-coreutils | 30 |  |
| sed | 30 |  |
| sensible-utils | 30 |  |
| sonic-build-hooks | 30 |  |
| sysvinit-utils | 30 |  |
| tar | 30 |  |
| tzdata | 30 |  |
| ubuntu-keyring | 30 |  |
| ucf | 30 |  |
| util-linux | 30 |  |
| vim-common | 30 |  |
| vim-tiny | 30 |  |
| zlib1g | 30 |  |
| libprotobuf32t64 | 14 | docker-dash-ha, docker-database, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| iputils-ping | 8 | docker-dash-ha, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-platform-monitor, docker-sflow, docker-teamd |
| libc-dev-bin | 5 | docker-dhcp-relay, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| libc6-dev | 5 | docker-dhcp-relay, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| libpci3 | 5 | docker-fpm-frr, docker-lldp, docker-orchagent, docker-platform-monitor, docker-snmp |
| libsystemd-shared | 5 | docker-fpm-frr, docker-gbsyncd-vs, docker-orchagent, docker-platform-monitor, docker-syncd-vs |
| libxml2-16 | 5 | docker-gbsyncd-vs, docker-lldp, docker-platform-monitor, docker-sonic-mgmt-framework, docker-syncd-vs |
| linux-libc-dev | 5 | docker-dhcp-relay, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| pci.ids | 5 | docker-fpm-frr, docker-lldp, docker-orchagent, docker-platform-monitor, docker-snmp |
| rpcsvc-proto | 5 | docker-dhcp-relay, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| systemd | 5 | docker-fpm-frr, docker-gbsyncd-vs, docker-orchagent, docker-platform-monitor, docker-syncd-vs |
| libibverbs1 | 4 | docker-dhcp-relay, docker-gbsyncd-vs, docker-orchagent, docker-syncd-vs |
| libpcap0.8t64 | 4 | docker-dhcp-relay, docker-gbsyncd-vs, docker-orchagent, docker-syncd-vs |
| libprotobuf-dev | 4 | docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| libprotobuf-lite32t64 | 4 | docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| libsensors-config | 4 | docker-fpm-frr, docker-lldp, docker-platform-monitor, docker-snmp |
| zlib1g-dev | 4 | docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-vs, docker-syncd-vs |
| ibverbs-providers | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libcares2 | 3 | docker-fpm-frr, docker-gbsyncd-vs, docker-syncd-vs |
| libdbus-1-dev | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libglib2.0-0t64 | 3 | docker-gbsyncd-vs, docker-platform-monitor, docker-syncd-vs |
| libibverbs-dev | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libkmod2 | 3 | docker-orchagent, docker-platform-monitor, docker-syncd-brcm |
| libpcap-dev | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libpcap0.8-dev | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libpkgconf7 | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libsnmp-base | 3 | docker-fpm-frr, docker-lldp, docker-snmp |
| libsnmp40t64 | 3 | docker-fpm-frr, docker-lldp, docker-snmp |
| libsystemd-dev | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| pkgconf | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| pkgconf-bin | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| python3-protobuf | 3 | docker-gbsyncd-vs, docker-orchagent, docker-syncd-vs |
| sgml-base | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| tcpdump | 3 | docker-gbsyncd-vs, docker-orchagent, docker-syncd-vs |
| xml-core | 3 | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| autoconf | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| automake | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| autotools-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| binutils | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| binutils-common | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| binutils-x86-64-linux-gnu | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| bridge-utils | 2 | docker-nat, docker-orchagent |
| clang | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| clang-21 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| conntrack | 2 | docker-nat, docker-orchagent |
| cpp | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| cpp-15 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| cpp-15-x86-64-linux-gnu | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| cpp-x86-64-linux-gnu | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| dmidecode | 2 | docker-platform-monitor, docker-sflow |
| ethtool | 2 | docker-platform-monitor, docker-syncd-brcm |
| file | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| flex | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| freeipmi-common | 2 | docker-platform-monitor, docker-snmp |
| gcc-15-base | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| ipmitool | 2 | docker-platform-monitor, docker-snmp |
| libabsl-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libabsl20260107 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libasan8 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libbinutils | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libboost-thread1.83.0 | 2 | docker-dhcp-relay, docker-mux |
| libbpf-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libc-ares-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libc-ares2 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libclang-common-21-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libclang-cpp21 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libclang1-21 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libctf-nobfd0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libctf0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libdouble-conversion3 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libedit2 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libelf-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libevent-2.1-7t64 | 2 | docker-dhcp-relay, docker-lldp |
| libfl-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libfl2 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libfreeipmi17 | 2 | docker-platform-monitor, docker-snmp |
| libgc-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgc1 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgcc-15-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgmp-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgmpxx4ldbl | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgomp1 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgprofng0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgrpc++-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgrpc++1.51t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgrpc-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libgrpc29t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libhwasan0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libicu78 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libisl23 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libitm1 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libjson-c5 | 2 | docker-fpm-frr, docker-platform-monitor |
| libllvm21 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| liblsan0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| liblsof0 | 2 | docker-dhcp-relay, docker-fpm-frr |
| libmagic-mgc | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libmagic1t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libmpc3 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libmpfr6 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libnanomsg-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libnanomsg5 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libnetfilter-conntrack3 | 2 | docker-nat, docker-orchagent |
| libnfnetlink0 | 2 | docker-nat, docker-orchagent |
| libobjc-15-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libobjc4 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libpcre2-16-0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libpfm4 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libprotoc-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libprotoc32t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libqt5core5t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libqt5dbus5t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libqt5network5t64 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libquadmath0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libre2-11 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libre2-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libsframe3 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libssl-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libstdc++-15-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libthrift-0.22.0 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libthrift-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libtool | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libtsan2 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libubsan1 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| libzstd-dev | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| llvm | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| llvm-21 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| llvm-21-linker-tools | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| llvm-21-runtime | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| llvm-runtime | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| lsof | 2 | docker-dhcp-relay, docker-fpm-frr |
| m4 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| pciutils | 2 | docker-orchagent, docker-platform-monitor |
| pkg-config | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| protobuf-compiler | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| protobuf-compiler-grpc | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-grpcio | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-netifaces | 2 | docker-orchagent, docker-platform-monitor |
| python3-ply | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-psutil | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-pyroute2 | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-scapy | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-six | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| python3-thrift | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| shared-mime-info | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| thrift-compiler | 2 | docker-gbsyncd-vs, docker-syncd-vs |
| arping | 1 | docker-orchagent |
| cron | 1 | docker-fpm-frr |
| cron-daemon-common | 1 | docker-fpm-frr |
| fontconfig | 1 | docker-platform-monitor |
| fontconfig-config | 1 | docker-platform-monitor |
| fonts-dejavu-core | 1 | docker-platform-monitor |
| fonts-dejavu-mono | 1 | docker-platform-monitor |
| i2c-tools | 1 | docker-platform-monitor |
| ifupdown | 1 | docker-orchagent |
| iptables | 1 | docker-nat |
| kmod | 1 | docker-syncd-brcm |
| libboost-filesystem1.83.0 | 1 | docker-mux |
| libboost-log1.83.0 | 1 | docker-mux |
| libboost-program-options1.83.0 | 1 | docker-mux |
| libcairo2 | 1 | docker-platform-monitor |
| libcjson1 | 1 | docker-sonic-mgmt-framework |
| libdatrie1 | 1 | docker-platform-monitor |
| libdbi1t64 | 1 | docker-platform-monitor |
| libdbus-c++-1-0v5 | 1 | docker-sysmgr |
| libevent-core-2.1-7t64 | 1 | docker-dhcp-relay |
| libevent-pthreads-2.1-7t64 | 1 | docker-dhcp-relay |
| libexplain51t64 | 1 | docker-dhcp-relay |
| libfontconfig1 | 1 | docker-platform-monitor |
| libfreetype6 | 1 | docker-platform-monitor |
| libfribidi0 | 1 | docker-platform-monitor |
| libgoogle-perftools4t64 | 1 | docker-fpm-frr |
| libgraphite2-3 | 1 | docker-platform-monitor |
| libharfbuzz0b | 1 | docker-platform-monitor |
| libi2c0 | 1 | docker-platform-monitor |
| libip4tc2 | 1 | docker-nat |
| libip6tc2 | 1 | docker-nat |
| libjsoncpp-dev | 1 | docker-dhcp-relay |
| libjsoncpp26 | 1 | docker-dhcp-relay |
| libnet9 | 1 | docker-orchagent |
| libnftnl11 | 1 | docker-nat |
| libnvme1t64 | 1 | docker-platform-monitor |
| libpango-1.0-0 | 1 | docker-platform-monitor |
| libpangocairo-1.0-0 | 1 | docker-platform-monitor |
| libpangoft2-1.0-0 | 1 | docker-platform-monitor |
| libpcre2-posix3 | 1 | docker-fpm-frr |
| libpcsclite1 | 1 | docker-macsec |
| libpixman-1-0 | 1 | docker-platform-monitor |
| libpng16-16t64 | 1 | docker-platform-monitor |
| librrd-dev | 1 | docker-platform-monitor |
| librrd8t64 | 1 | docker-platform-monitor |
| libtcmalloc-minimal4t64 | 1 | docker-fpm-frr |
| libthai-data | 1 | docker-platform-monitor |
| libthai0 | 1 | docker-platform-monitor |
| libunwind8 | 1 | docker-fpm-frr |
| libx11-6 | 1 | docker-platform-monitor |
| libx11-data | 1 | docker-platform-monitor |
| libxau6 | 1 | docker-platform-monitor |
| libxcb-render0 | 1 | docker-platform-monitor |
| libxcb-shm0 | 1 | docker-platform-monitor |
| libxcb1 | 1 | docker-platform-monitor |
| libxdmcp6 | 1 | docker-platform-monitor |
| libxext6 | 1 | docker-platform-monitor |
| libxrender1 | 1 | docker-platform-monitor |
| logrotate | 1 | docker-fpm-frr |
| lz4 | 1 | docker-syncd-brcm |
| ndisc6 | 1 | docker-orchagent |
| ndppd | 1 | docker-orchagent |
| nvme-cli | 1 | docker-platform-monitor |
| otelcol-contrib | 1 | docker-sonic-otel |
| psmisc | 1 | docker-platform-monitor |
| python3-bottle | 1 | docker-platform-monitor |
| python3-smbus | 1 | docker-platform-monitor |
| radvd | 1 | docker-router-advertiser |
| redis-server | 1 | docker-database |
| rrdtool | 1 | docker-platform-monitor |
| saicredo-blackhawk | 1 | docker-gbsyncd-credo |
| saicredo-crt88322 | 1 | docker-gbsyncd-credo |
| saicredo-owl | 1 | docker-gbsyncd-credo |
| saicredo-saicredo | 1 | docker-gbsyncd-credo |
| smartmontools | 1 | docker-platform-monitor |
| snmp | 1 | docker-snmp |
| snmpd | 1 | docker-snmp |
| udev | 1 | docker-platform-monitor |
| uuid-runtime | 1 | docker-platform-monitor |
| wget | 1 | docker-sonic-otel |
| xxd | 1 | docker-platform-monitor |

## 5. Union of SELF-built debs across all vs+bcm containers

| package | used by |
|---|---|
| bash | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| dash-ha | docker-dash-ha |
| fancontrol | docker-platform-monitor |
| frr | docker-fpm-frr |
| frr-snmp | docker-fpm-frr |
| hsflowd | docker-sflow |
| isc-dhcp-relay | docker-dhcp-relay |
| libdashapi | docker-dash-ha, docker-database, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-teamd |
| libnexthopgroup | docker-dash-ha, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-teamd |
| libnl-3-200 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libnl-3-dev | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libnl-cli-3-200 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libnl-genl-3-200 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libnl-nf-3-200 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libnl-route-3-200 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libnl-route-3-dev | docker-dhcp-relay, docker-gbsyncd-vs, docker-syncd-vs |
| libsaiagera2 | docker-gbsyncd-agera2 |
| libsaibcm | docker-syncd-brcm |
| libsaibroncos | docker-gbsyncd-broncos |
| libsaimetadata | docker-dash-ha, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-syncd-brcm, docker-syncd-vs, docker-teamd |
| libsairedis | docker-dash-ha, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-syncd-brcm, docker-syncd-vs, docker-teamd |
| libsaivs | docker-gbsyncd-vs, docker-syncd-vs |
| libsensors5 | docker-fpm-frr, docker-lldp, docker-platform-monitor, docker-snmp |
| libswsscommon | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| libteam-utils | docker-teamd |
| libteam5 | docker-dash-ha, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-teamd |
| libteamdctl0 | docker-dash-ha, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-teamd |
| libyang3 | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| lldpd | docker-lldp |
| lm-sensors | docker-platform-monitor |
| psample | docker-sflow |
| python3-libyang | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| python3-swsscommon | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| sensord | docker-platform-monitor |
| sflowtool | docker-sflow |
| socat | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| sonic-bmp | docker-sonic-bmp |
| sonic-db-cli | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| sonic-dhcp4relay | docker-dhcp-relay |
| sonic-dhcp6relay | docker-dhcp-relay |
| sonic-dhcpmon | docker-dhcp-relay |
| sonic-eventd | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| sonic-gnmi | docker-sonic-gnmi |
| sonic-linkmgrd | docker-mux |
| sonic-mgmt-common | docker-sonic-gnmi, docker-sonic-mgmt-framework |
| sonic-mgmt-framework | docker-sonic-mgmt-framework |
| sonic-supervisord-utilities-rs | docker-bmp-watchdog, docker-dash-ha, docker-database, docker-dhcp-relay, docker-eventd, docker-fpm-frr, docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-gbsyncd-vs, docker-gnmi-sidecar, docker-gnmi-watchdog, docker-lldp, docker-macsec, docker-mux, docker-nat, docker-orchagent, docker-platform-monitor, docker-restapi-sidecar, docker-router-advertiser, docker-sflow, docker-snmp, docker-sonic-bmp, docker-sonic-gnmi, docker-sonic-mgmt-framework, docker-sonic-otel, docker-syncd-brcm, docker-syncd-vs, docker-sysmgr, docker-teamd |
| sswsyncd | docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-syncd-brcm |
| swss | docker-dash-ha, docker-fpm-frr, docker-macsec, docker-nat, docker-orchagent, docker-sflow, docker-teamd |
| syncd | docker-gbsyncd-agera2, docker-gbsyncd-broncos, docker-gbsyncd-credo, docker-syncd-brcm |
| syncd-vs | docker-gbsyncd-vs, docker-syncd-vs |
| sysmgr | docker-sysmgr |
| wpasupplicant | docker-macsec |
