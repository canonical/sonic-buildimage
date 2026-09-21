# Slice completeness on ubuntu-26.04 for the 236 archive packages our containers use

Generated 2026-09-17. For each package: real .deb from the resolute archive vs the union of every slice `contents:` in `slices/<pkg>.yaml` @70d32b4 (globs expanded, `copy:` sources counted, directories ignored). "doc/locale" = man/doc/completions/lintian/info/locale — excluded by chisel-releases policy. "REAL" = anything else the slices leave out.

**166 / 236 packages: every non-doc file is reachable via slices. 70 packages leave REAL files out.** Files: 12272 total, 3245 doc/locale excluded, 452 REAL uncovered.

Maintainer scripts: 62 of 236 packages ship preinst/postinst/prerm/postrm; chisel never runs them — only 6 of those SDFs carry a `mutate:` replacement (apt, base-passwd, ca-certificates, debianutils, libpam-runtime, libwrap0).

| package | version | files | doc/locale | REAL | slices | mutate | maint scripts | REAL categories | REAL examples |
|---|---|--:|--:|--:|--:|:-:|---|---|---|
| linux-libc-dev | 7.0.0-31.31 | 1041 | 1 | 122 | 3 |  |  | dev(headers/.a/.pc):122 | /usr/include/cxl/features.h /usr/include/drm/amdgpu_drm.h /usr/include/drm/amdxdna_accel.h /usr/include/drm/armada_drm.h … |
| python3-pkg-resources | 78.1.1-0.1build1 | 68 | 2 | 46 | 2 |  | postinst,prerm | python modules:46 | /usr/lib/python3/dist-packages/setuptools/_vendor/jaraco/text/Lorem ipsum.txt /usr/lib/python3/dist-packages/setuptools/_vendor/jaraco/text/__init__.py /usr/lib/python3/dist-packages/setuptools/_vendor/jaraco/text/layouts.py /usr/lib/python3/dist-packages/setuptools/_vendor/jaraco/text/show-newlines.py … |
| base-files | 14ubuntu6.2 | 66 | 11 | 41 | 10 |  | postinst,postrm,preinst,prerm | other /usr/share:33, etc config:5, systemd units:2, BINARIES:1 | /etc/legal /etc/profile.d/01-locale-fix.sh /etc/update-motd.d/00-header /etc/update-motd.d/10-help-text … |
| apt | 3.2.0 | 191 | 148 | 30 | 5 | ✓ | postinst,postrm,preinst,prerm | other /usr/lib:20, systemd units:4, BINARIES:2, other /usr/share:2, init.d/default/cron:1, etc config:1 | /etc/cron.daily/apt-compat /etc/logrotate.d/apt /usr/bin/apt-cache /usr/bin/apt-cdrom … |
| binutils | 2.46-3ubuntu2 | 41 | 9 | 27 | 4 |  | preinst | BINARIES:24, etc config:1, other /usr/share:1, other /usr/lib:1 | /etc/gprofng.rc /usr/bin/gprofng /usr/bin/gprofng-archive /usr/bin/gprofng-collect-app … |
| libgcc-15-dev | 15.2.0-16ubuntu1 | 195 | 0 | 25 | 4 |  |  | dev(headers/.a/.pc):13, dev(.so symlink):9, other /usr/lib:3 | /usr/lib/gcc/x86_64-linux-gnu/15/libasan.a /usr/lib/gcc/x86_64-linux-gnu/15/libasan_preinit.o /usr/lib/gcc/x86_64-linux-gnu/15/libatomic.a /usr/lib/gcc/x86_64-linux-gnu/15/libbacktrace.a … |
| systemd | 259.5-0ubuntu3.4 | 909 | 335 | 21 | 32 |  | postinst,postrm,preinst,prerm | other /usr/share:11, systemd units:5, etc config:4, other /usr/lib:1 | /usr/lib/pcrlock.d/770-nvpcr-separator.pcrlock /usr/lib/systemd/network/80-auto-link-local.network.example /usr/lib/systemd/network/80-wifi-ap.network.example /usr/lib/systemd/network/80-wifi-station.network.example … |
| binutils-x86-64-linux-gnu | 2.46-3ubuntu2 | 177 | 18 | 12 | 11 |  |  | BINARIES:12 | /usr/bin/x86_64-linux-gnu-addr2line /usr/bin/x86_64-linux-gnu-c++filt /usr/bin/x86_64-linux-gnu-elfedit /usr/bin/x86_64-linux-gnu-gprof … |
| libc-bin | 2.43-2ubuntu2.4 | 35 | 4 | 12 | 7 |  | postinst | BINARIES:8, etc config:4 | /etc/bindresvport.blacklist /etc/gai.conf /etc/ld.so.conf /etc/ld.so.conf.d/libc.conf … |
| vim-common | 2:9.1.2141-1ubuntu4.9 | 52 | 40 | 9 | 4 |  | postinst,postrm | other /usr/share:7, BINARIES:1, other /usr/lib:1 | /usr/bin/helpztags /usr/lib/mime/packages/vim-common /usr/share/icons/hicolor/48x48/apps/gvim.png /usr/share/icons/hicolor/scalable/apps/gvim.svg … |
| dpkg | 1.23.7ubuntu1 | 152 | 80 | 8 | 10 |  | postinst,postrm,prerm | etc config:3, systemd units:2, other /usr/share:2, init.d/default/cron:1 | /etc/alternatives/README /etc/cron.daily/dpkg /etc/logrotate.d/alternatives /etc/logrotate.d/dpkg … |
| cron | 3.0pl1-200ubuntu1 | 25 | 14 | 6 | 4 |  | postinst,postrm,preinst,prerm | etc config:2, other /usr/share:2, init.d/default/cron:1, systemd units:1 | /etc/init.d/cron /etc/supercat/spcrc-crontab /etc/supercat/spcrc-crontab-light /usr/lib/systemd/system/cron.service … |
| libstdc++6 | 16-20260322-1ubuntu1 | 8 | 0 | 5 | 2 |  | prerm | other /usr/share:5 | /usr/share/gcc/python/libstdcxx/__init__.py /usr/share/gcc/python/libstdcxx/v6/__init__.py /usr/share/gcc/python/libstdcxx/v6/printers.py /usr/share/gcc/python/libstdcxx/v6/xmethods.py … |
| vim-tiny | 2:9.1.2141-1ubuntu4.9 | 10 | 2 | 5 | 3 |  | postinst,prerm | other /usr/share:5 | /usr/share/bug/vim-tiny/presubj /usr/share/bug/vim-tiny/script /usr/share/vim/vim91/doc/README.Debian /usr/share/vim/vim91/doc/help.txt … |
| python3 | 3.14.3-0ubuntu2 | 18 | 10 | 4 | 4 |  | postinst,postrm,preinst,prerm | other /usr/share:3, other /usr/lib:1 | /usr/lib/valgrind/python3.supp /usr/share/python3/python.mk /usr/share/python3/runtime.d/public_modules.rtinstall /usr/share/python3/runtime.d/public_modules.rtremove |
| less | 668-1build1 | 16 | 9 | 3 | 2 |  | postinst,preinst,prerm | BINARIES:2, other /usr/lib:1 | /usr/bin/lesspipe /usr/lib/mime/packages/less /usr/bin/lessfile |
| libpython3.14-stdlib | 3.14.4-1ubuntu0.2 | 380 | 1 | 3 | 33 |  | prerm | python modules:3 | /usr/lib/python3.14/EXTERNALLY-MANAGED /usr/lib/python3.14/LICENSE.txt /usr/lib/python3.14/build-details_x86_64-linux-gnu.json |
| openssl | 3.5.5-1ubuntu3.5 | 379 | 368 | 3 | 5 |  | postinst | other /usr/lib:3 | /usr/lib/ssl/misc/CA.pl /usr/lib/ssl/misc/tsget.pl /usr/lib/ssl/misc/tsget |
| procps | 2:4.0.4-9ubuntu1 | 170 | 139 | 3 | 5 |  | postinst,postrm,preinst,prerm | init.d/default/cron:1, etc config:1, other /usr/share:1 | /etc/init.d/procps /etc/sysctl.d/README.sysctl /usr/share/bug/procps/presubj |
| redis-server | 5:8.0.5-1 | 13 | 5 | 3 | 4 |  | postinst,postrm,preinst,prerm | init.d/default/cron:2, etc config:1 | /etc/default/redis-server /etc/init.d/redis-server /etc/logrotate.d/redis-server |
| util-linux | 2.41.3-3ubuntu2.2 | 234 | 168 | 3 | 24 |  | postinst,postrm,prerm | other /usr/share:2, BINARIES:1 | /usr/bin/logger /usr/share/doc/util-linux/AUTHORS.gz /usr/share/util-linux/logcheck/ignore.d.server/util-linux |
| file | 1:5.46-5build2 | 7 | 3 | 2 | 2 |  |  | other /usr/share:2 | /usr/share/bug/file/control /usr/share/bug/file/presubj |
| fontconfig-config | 2.17.1-3ubuntu1 | 74 | 2 | 2 | 2 |  | postinst,postrm,preinst,prerm | etc config:1, other /usr/share:1 | /etc/fonts/conf.d/README /usr/share/fontconfig/conf.avail/48-guessfamily.conf |
| iproute2 | 6.19.0-1ubuntu1.1 | 190 | 154 | 2 | 8 |  | postinst,postrm,preinst,prerm | BINARIES:2 | /usr/bin/netshaper /usr/sbin/dpll |
| iputils-ping | 3:20250605-1ubuntu1 | 9 | 5 | 2 | 2 |  | postinst | BINARIES:2 | /usr/bin/ping4 /usr/bin/ping6 |
| libgcrypt20 | 1.12.0-2ubuntu1.1 | 9 | 4 | 2 | 2 |  | postinst | other /usr/share:2 | /usr/share/doc/libgcrypt20/AUTHORS.gz /usr/share/libgcrypt20/clean-up-unmanaged-libraries |
| libgnutls30t64 | 3.8.12-2ubuntu1.1 | 10 | 5 | 2 | 2 |  |  | etc config:1, other /usr/share:1 | /etc/gnutls/config /usr/share/doc/libgnutls30t64/AUTHORS.gz |
| libmagic1t64 | 1:5.46-5build2 | 11 | 3 | 2 | 4 |  |  | other /usr/share:2 | /usr/share/bug/libmagic1t64/control /usr/share/bug/libmagic1t64/presubj |
| libpam-runtime | 1.7.0-5ubuntu3.2 | 87 | 71 | 2 | 5 | ✓ | postinst,postrm,prerm | BINARIES:2 | /usr/sbin/pam-auth-update /usr/sbin/pam_getenv |
| perl-base | 5.40.1-7ubuntu0.3 | 624 | 5 | 2 | 4 |  |  | BINARIES:1, other /usr/share:1 | /usr/bin/perl5.40.1 link to ./usr/bin/perl /usr/share/doc/perl/AUTHORS.gz |
| python3.14-minimal | 3.14.4-1ubuntu0.2 | 8 | 4 | 2 | 2 |  | postinst,postrm,preinst,prerm | other /usr/lib:1, other /usr/share:1 | /usr/lib/binfmt.d/python3.14.conf /usr/share/binfmts/python3.14 |
| tar | 1.35+dfsg-4ubuntu0.4 | 14 | 7 | 2 | 5 |  | postinst,prerm | other /usr/lib:1, other /usr/share:1 | /usr/lib/mime/packages/tar /usr/share/doc/tar/AUTHORS |
| wget | 1.25.0-2ubuntu4.4 | 10 | 6 | 2 | 2 |  |  | etc config:1, other /usr/share:1 | /etc/wgetrc /usr/share/doc/wget/AUTHORS.gz |
| base-passwd | 3.6.8 | 18 | 14 | 1 | 2 | ✓ | postinst,postrm,preinst | BINARIES:1 | /usr/sbin/update-passwd |
| cpp-15-x86-64-linux-gnu | 15.2.0-16ubuntu1 | 5 | 2 | 1 | 2 |  |  | BINARIES:1 | /usr/bin/x86_64-linux-gnu-cpp-15 |
| cpp-x86-64-linux-gnu | 4:15.2.0-5ubuntu1 | 5 | 3 | 1 | 1 |  |  | BINARIES:1 | /usr/bin/x86_64-linux-gnu-cpp |
| curl | 8.18.0-1ubuntu2.5 | 10 | 7 | 1 | 2 |  |  | BINARIES:1 | /usr/bin/wcurl |
| dash | 0.5.12-12ubuntu3 | 11 | 7 | 1 | 2 |  | postinst,postrm,preinst,prerm | other /usr/share:1 | /usr/share/debianutils/shells.d/dash |
| fontconfig | 2.17.1-3ubuntu1 | 26 | 15 | 1 | 3 |  | postinst,postrm | other /usr/share:1 | /usr/share/apport/package-hooks/source_fontconfig.py |
| fonts-dejavu-core | 2.37-8build1 | 28 | 6 | 1 | 3 |  | postinst,postrm,preinst,prerm | other /usr/share:1 | /usr/share/doc/fonts-dejavu-core/AUTHORS |
| fonts-dejavu-mono | 2.37-8build1 | 20 | 6 | 1 | 3 |  |  | other /usr/share:1 | /usr/share/doc/fonts-dejavu-mono/AUTHORS |
| grep | 3.12-1 | 17 | 11 | 1 | 3 |  |  | other /usr/share:1 | /usr/share/doc/grep/AUTHORS |
| init-system-helpers | 1.69 | 16 | 9 | 1 | 9 |  | postinst | other /usr/share:1 | /usr/share/bug/init-system-helpers/control |
| jq | 1.8.1-4ubuntu2 | 7 | 4 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/jq/AUTHORS.gz |
| libc6-dev | 2.43-2ubuntu2.4 | 522 | 3 | 1 | 11 |  |  | other /usr/share:1 | /usr/share/gdb/auto-load/lib/x86_64-linux-gnu/libc.so.6-gdb.py |
| libdbus-1-3 | 1.16.2-2ubuntu4 | 7 | 3 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libdbus-1-3/AUTHORS.gz |
| libexpat1 | 2.7.4-1 | 7 | 1 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libexpat1/AUTHORS |
| libidn2-0 | 2.3.8-4build1 | 8 | 4 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libidn2-0/AUTHORS |
| libisl23 | 0.27-1build1 | 5 | 1 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/gdb/auto-load/usr/lib/x86_64-linux-gnu/libisl.so.23.4.0-gdb.py |
| liblzma5 | 5.8.3-1 | 7 | 3 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/liblzma5/AUTHORS |
| libmpfr6 | 4.2.2-3 | 9 | 5 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libmpfr6/AUTHORS |
| libnghttp2-14 | 1.68.0-2ubuntu0.2 | 6 | 2 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libnghttp2-14/AUTHORS |
| libpcsclite1 | 2.4.1-1 | 4 | 1 | 1 | 2 |  |  | other /usr/lib:1 | /usr/lib/x86_64-linux-gnu/libpcsclite_real.so.1 |
| libperl5.40 | 5.40.1-7ubuntu0.3 | 397 | 4 | 1 | 34 |  |  | perl modules:1 | /usr/lib/x86_64-linux-gnu/perl/debian-config-data-5.40.1/README |
| libselinux1 | 3.9-4build1 | 5 | 1 | 1 | 3 |  | postinst | other:1 | /usr/libexec/libselinux/selinux_compile_fcontexts |
| libsensors-config | 1:3.6.2-2build1 | 4 | 1 | 1 | 2 |  |  | etc config:1 | /etc/sensors.d/.placeholder |
| libsodium23 | 1.0.18-2 | 7 | 3 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libsodium23/AUTHORS.gz |
| libssh2-1t64 | 1.11.1-1ubuntu0.26.04.4 | 6 | 2 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libssh2-1t64/AUTHORS |
| libssl3t64 | 3.5.5-1ubuntu3.5 | 9 | 3 | 1 | 2 |  |  | dev(.so symlink):1 | /usr/lib/x86_64-linux-gnu/engines-3/padlock.so |
| libtasn1-6 | 4.21.0-2 | 7 | 3 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libtasn1-6/AUTHORS |
| libzmq5 | 4.3.5-1build3 | 6 | 2 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/libzmq5/AUTHORS |
| login | 1:4.16.0-2+really2.41.3-3ubuntu2.2 | 21 | 16 | 1 | 3 |  | postinst,postrm,preinst,prerm | etc config:1 | /etc/pam.d/remote |
| media-types | 14.0.0build1 | 4 | 1 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/bug/media-types/presubj |
| ncurses-base | 6.6+20251231-1 | 54 | 4 | 1 | 3 |  |  | etc config:1 | /etc/terminfo/README |
| perl | 5.40.1-7ubuntu0.3 | 63 | 32 | 1 | 9 |  | postinst | BINARIES:1 | /usr/bin/perlthanks link to ./usr/bin/perlbug |
| python3-setuptools | 78.1.1-0.1build1 | 414 | 8 | 1 | 2 |  | postinst,prerm | python modules:1 | /usr/lib/python3/dist-packages/distutils-precedence.pth |
| sed | 4.9-2ubuntu1 | 12 | 9 | 1 | 2 |  |  | other /usr/share:1 | /usr/share/doc/sed/AUTHORS |
| tzdata | 2026c-0ubuntu0.26.04.1 | 499 | 4 | 1 | 14 |  | postinst,postrm | other /usr/share:1 | /usr/share/zoneinfo/America/Coyhaique |
| ucf | 3.0052ubuntu1 | 16 | 10 | 1 | 3 |  | postinst,postrm,preinst | other /usr/share:1 | /usr/share/ucf/ucf_library.sh |
| zlib1g-dev | 1:1.3.dfsg+really1.3.1-1ubuntu3.1 | 30 | 24 | 1 | 3 |  |  | dev(headers/.a/.pc):1 | /usr/lib/x86_64-linux-gnu/pkgconfig/zlib.pc |
| binutils-common | 2.46-3ubuntu2 | 29 | 28 | 0 | 1 |  |  |  |  |
| ca-certificates | 20260601~26.04.1 | 138 | 15 | 0 | 4 | ✓ | postinst,postrm,prerm |  |  |
| coreutils | 9.5-1ubuntu2+0.0.0~ubuntu25 | 2 | 1 | 0 | 70 |  |  |  |  |
| debianutils | 5.23.2build1 | 70 | 59 | 0 | 13 | ✓ | postinst,postrm,prerm |  |  |
| diffutils | 1:3.12-1ubuntu0.1 | 12 | 7 | 0 | 3 |  |  |  |  |
| findutils | 4.10.0-3build2 | 12 | 9 | 0 | 4 |  |  |  |  |
| gcc-15-base | 15.2.0-16ubuntu1 | 4 | 3 | 0 | 1 |  |  |  |  |
| gcc-16-base | 16-20260322-1ubuntu1 | 4 | 3 | 0 | 1 |  |  |  |  |
| gnu-coreutils | 9.7-3ubuntu2.1 | 259 | 152 | 0 | 70 |  |  |  |  |
| gpgv | 2.4.8-4ubuntu3.1 | 5 | 3 | 0 | 2 |  |  |  |  |
| gzip | 1.14-1~exp2ubuntu1.1 | 34 | 19 | 0 | 3 |  | postinst,preinst |  |  |
| hostname | 3.25build1 | 12 | 6 | 0 | 2 |  |  |  |  |
| iptables | 1.8.11-2ubuntu3 | 200 | 45 | 0 | 6 |  | postinst,prerm |  |  |
| libacl1 | 2.3.2-2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libapt-pkg7.0 | 3.2.0 | 49 | 46 | 0 | 2 |  |  |  |  |
| libasan8 | 16-20260322-1ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libatomic1 | 16-20260322-1ubuntu1 | 3 | 0 | 0 | 2 |  |  |  |  |
| libattr1 | 1:2.5.2-4ubuntu0.1 | 6 | 2 | 0 | 3 |  |  |  |  |
| libaudit-common | 1:4.1.2-1ubuntu0.1 | 4 | 2 | 0 | 2 |  |  |  |  |
| libaudit1 | 1:4.1.2-1ubuntu0.1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libbinutils | 2.46-3ubuntu2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libblkid1 | 2.41.3-3ubuntu2.2 | 6 | 3 | 0 | 2 |  |  |  |  |
| libboost-filesystem1.83.0 | 1.83.0-5ubuntu5 | 4 | 2 | 0 | 2 |  |  |  |  |
| libboost-log1.83.0 | 1.83.0-5ubuntu5 | 5 | 2 | 0 | 2 |  |  |  |  |
| libboost-program-options1.83.0 | 1.83.0-5ubuntu5 | 4 | 2 | 0 | 2 |  |  |  |  |
| libboost-serialization1.83.0 | 1.83.0-5ubuntu5 | 5 | 2 | 0 | 2 |  |  |  |  |
| libboost-thread1.83.0 | 1.83.0-5ubuntu5 | 4 | 2 | 0 | 2 |  |  |  |  |
| libbpf1 | 1:1.6.3-1ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libbrotli1 | 1.2.0-3build1 | 9 | 2 | 0 | 2 |  |  |  |  |
| libbsd0 | 0.12.2-2build2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libbz2-1.0 | 1.0.8-6ubuntu0.1 | 5 | 1 | 0 | 2 |  |  |  |  |
| libc6 | 2.43-2ubuntu2.4 | 39 | 6 | 0 | 6 |  | postinst,postrm,preinst |  |  |
| libcairo2 | 1.18.4-3 | 4 | 1 | 0 | 2 |  |  |  |  |
| libcap-ng0 | 0.8.5-4build5 | 6 | 1 | 0 | 2 |  |  |  |  |
| libcap2 | 1:2.75-10ubuntu2 | 6 | 1 | 0 | 2 |  |  |  |  |
| libcap2-bin | 1:2.75-10ubuntu2 | 12 | 7 | 0 | 2 |  |  |  |  |
| libcares2 | 1.34.6-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libcjson1 | 1.7.19-2 | 6 | 1 | 0 | 2 |  |  |  |  |
| libcom-err2 | 1.47.2-3ubuntu4 | 4 | 1 | 0 | 2 |  |  |  |  |
| libcrypt1 | 1:4.5.1-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libctf0 | 2.46-3ubuntu2 | 3 | 0 | 0 | 2 |  |  |  |  |
| libcurl4t64 | 8.18.0-1ubuntu2.5 | 4 | 1 | 0 | 2 |  |  |  |  |
| libdatrie1 | 0.2.14-1 | 6 | 3 | 0 | 2 |  |  |  |  |
| libdb5.3t64 | 5.3.28+dfsg2-10ubuntu1 | 5 | 3 | 0 | 2 |  |  |  |  |
| libedit2 | 3.1-20251016-1 | 8 | 5 | 0 | 2 |  |  |  |  |
| libelf1t64 | 0.194-4 | 4 | 1 | 0 | 2 |  |  |  |  |
| libevent-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libevent-core-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libevent-pthreads-2.1-7t64 | 2.1.12-stable-10ubuntu0.1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libffi8 | 3.5.2-4 | 4 | 1 | 0 | 2 |  |  |  |  |
| libfontconfig1 | 2.17.1-3ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libfreetype6 | 2.14.2+dfsg-1ubuntu0.1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libfribidi0 | 1.0.16-5 | 8 | 5 | 0 | 2 |  |  |  |  |
| libgcc-s1 | 16-20260322-1ubuntu1 | 3 | 1 | 0 | 2 |  |  |  |  |
| libgdbm-compat4t64 | 1.26-1build1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libgdbm6t64 | 1.26-1build1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libglib2.0-0t64 | 2.88.0-1 | 19 | 5 | 0 | 7 |  | postinst,postrm,preinst |  |  |
| libgmp10 | 2:6.3.0+dfsg-5ubuntu2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libgomp1 | 16-20260322-1ubuntu1 | 3 | 0 | 0 | 2 |  |  |  |  |
| libgpg-error0 | 1.58-2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libgraphite2-3 | 1.3.14-11ubuntu1.1 | 5 | 1 | 0 | 2 |  |  |  |  |
| libgssapi-krb5-2 | 1.22.1-2ubuntu4.1 | 6 | 3 | 0 | 2 |  | postinst,postrm |  |  |
| libharfbuzz0b | 12.3.2-2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libhiredis1.1.0 | 1.2.0-6ubuntu4 | 6 | 1 | 0 | 2 |  |  |  |  |
| libhogweed6t64 | 3.10.2-1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libicu78 | 78.2-2ubuntu1 | 15 | 2 | 0 | 2 |  |  |  |  |
| libip4tc2 | 1.8.11-2ubuntu3 | 5 | 2 | 0 | 2 |  |  |  |  |
| libip6tc2 | 1.8.11-2ubuntu3 | 5 | 2 | 0 | 2 |  |  |  |  |
| libjansson4 | 2.14-2build4 | 6 | 3 | 0 | 2 |  |  |  |  |
| libjemalloc2 | 5.3.0-4 | 4 | 2 | 0 | 2 |  |  |  |  |
| libjq1 | 1.8.1-4ubuntu2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libjson-c5 | 0.18+ds-3 | 6 | 3 | 0 | 2 |  |  |  |  |
| libk5crypto3 | 1.22.1-2ubuntu4.1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libkeyutils1 | 1.6.3-6ubuntu3 | 4 | 1 | 0 | 2 |  |  |  |  |
| libkmod2 | 34.2-2ubuntu2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libkrb5-3 | 1.22.1-2ubuntu4.1 | 9 | 5 | 0 | 2 |  |  |  |  |
| libkrb5support0 | 1.22.1-2ubuntu4.1 | 6 | 3 | 0 | 2 |  |  |  |  |
| libldap-common | 2.6.10+dfsg-1ubuntu5 | 5 | 3 | 0 | 2 |  |  |  |  |
| libldap2 | 2.6.10+dfsg-1ubuntu5 | 7 | 2 | 0 | 2 |  |  |  |  |
| libllvm21 | 1:21.1.8-6ubuntu1 | 6 | 3 | 0 | 2 |  |  |  |  |
| liblz4-1 | 1.10.0-8 | 4 | 1 | 0 | 2 |  |  |  |  |
| liblzf1 | 3.6-4build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libmagic-mgc | 1:5.46-5build2 | 6 | 2 | 0 | 2 |  |  |  |  |
| libmd0 | 1.1.0-2build4 | 4 | 1 | 0 | 2 |  |  |  |  |
| libmnl0 | 1.0.5-3build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libmount1 | 2.41.3-3ubuntu2.2 | 6 | 3 | 0 | 2 |  |  |  |  |
| libmpc3 | 1.3.1-3 | 4 | 1 | 0 | 2 |  |  |  |  |
| libncursesw6 | 6.6+20251231-1 | 9 | 0 | 0 | 2 |  |  |  |  |
| libnetfilter-conntrack3 | 1.1.1-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libnettle8t64 | 3.10.2-1 | 7 | 4 | 0 | 2 |  |  |  |  |
| libnfnetlink0 | 1.0.2-3build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libnftnl11 | 1.3.1-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libnorm1t64 | 1.5.9+dfsg-4 | 4 | 2 | 0 | 2 |  |  |  |  |
| libonig5 | 6.9.10-1build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libp11-kit0 | 0.26.2-2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpam-modules | 1.7.0-5ubuntu3.2 | 61 | 4 | 0 | 4 |  | postinst,postrm,preinst |  |  |
| libpam-modules-bin | 1.7.0-5ubuntu3.2 | 13 | 2 | 0 | 4 |  | postinst,postrm,prerm |  |  |
| libpam0g | 1.7.0-5ubuntu3.2 | 13 | 6 | 0 | 2 |  | postinst,postrm |  |  |
| libpango-1.0-0 | 1.57.0-1 | 7 | 4 | 0 | 2 |  |  |  |  |
| libpangocairo-1.0-0 | 1.57.0-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libpangoft2-1.0-0 | 1.57.0-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libpcre2-8-0 | 10.46-1build1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpgm-5.3-0t64 | 5.3.128~dfsg-2.1build2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpixman-1-0 | 0.46.4-1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpng16-16t64 | 1.6.57-1 | 10 | 7 | 0 | 2 |  |  |  |  |
| libproc2-0 | 2:4.0.4-9ubuntu1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpsl5t64 | 0.21.2-1.1build2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libpython3-stdlib | 3.14.3-0ubuntu2 | 3 | 2 | 0 | 32 |  |  |  |  |
| libpython3.14-minimal | 3.14.4-1ubuntu0.2 | 312 | 3 | 0 | 3 |  | postinst,postrm,prerm |  |  |
| libreadline8t64 | 8.3-4 | 10 | 5 | 0 | 2 |  | postrm,preinst |  |  |
| librtmp1 | 2.4+20151223.gitfa8646d.1-3 | 3 | 1 | 0 | 2 |  |  |  |  |
| libsasl2-2 | 2.1.28+dfsg1-9ubuntu3 | 6 | 3 | 0 | 2 |  |  |  |  |
| libsasl2-modules-db | 2.1.28+dfsg1-9ubuntu3 | 5 | 1 | 0 | 2 |  |  |  |  |
| libseccomp2 | 2.6.0-2ubuntu5 | 4 | 1 | 0 | 2 |  |  |  |  |
| libsemanage-common | 3.9-1build1 | 4 | 2 | 0 | 2 |  |  |  |  |
| libsemanage2 | 3.9-1build1 | 3 | 1 | 0 | 2 |  |  |  |  |
| libsepol2 | 3.9-2 | 3 | 1 | 0 | 2 |  |  |  |  |
| libsframe3 | 2.46-3ubuntu2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libsmartcols1 | 2.41.3-3ubuntu2.2 | 6 | 3 | 0 | 2 |  |  |  |  |
| libsqlite3-0 | 3.46.1-9ubuntu0.3 | 5 | 2 | 0 | 2 |  |  |  |  |
| libsystemd-shared | 259.5-0ubuntu3.4 | 6 | 3 | 0 | 2 |  | preinst |  |  |
| libsystemd0 | 259.5-0ubuntu3.4 | 5 | 2 | 0 | 2 |  |  |  |  |
| libthai-data | 0.1.30-1 | 3 | 1 | 0 | 2 |  |  |  |  |
| libthai0 | 0.1.30-1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libtinfo6 | 6.6+20251231-1 | 6 | 1 | 0 | 2 |  |  |  |  |
| libtirpc-common | 1.3.7-0.1 | 4 | 2 | 0 | 2 |  |  |  |  |
| libtirpc3t64 | 1.3.7-0.1 | 5 | 2 | 0 | 2 |  | postrm,preinst |  |  |
| libubsan1 | 16-20260322-1ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libudev1 | 259.5-0ubuntu3.4 | 5 | 2 | 0 | 2 |  |  |  |  |
| libunistring5 | 1.3-2build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libunwind8 | 1.8.3-0ubuntu1 | 10 | 1 | 0 | 2 |  |  |  |  |
| libuuid1 | 2.41.3-3ubuntu2.2 | 5 | 2 | 0 | 2 |  |  |  |  |
| libwrap0 | 7.6.q-36build2 | 10 | 7 | 0 | 3 | ✓ | postinst,postrm |  |  |
| libx11-6 | 2:1.8.13-1 | 5 | 2 | 0 | 2 |  |  |  |  |
| libx11-data | 2:1.8.13-1 | 194 | 3 | 0 | 3 |  |  |  |  |
| libxau6 | 1:1.0.11-1build2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxcb-render0 | 1.17.0-2ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxcb-shm0 | 1.17.0-2ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxcb1 | 1.17.0-2ubuntu1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxdmcp6 | 1:1.1.5-2 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxext6 | 2:1.3.4-1build3 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxml2-16 | 2.15.2+dfsg-0.1ubuntu0.1 | 8 | 5 | 0 | 2 |  |  |  |  |
| libxrender1 | 1:0.9.12-1build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libxtables12 | 1.8.11-2ubuntu3 | 5 | 2 | 0 | 2 |  |  |  |  |
| libxxhash0 | 0.8.3-2build1 | 4 | 1 | 0 | 2 |  |  |  |  |
| libyaml-0-2 | 0.2.5-2build3 | 4 | 1 | 0 | 2 |  |  |  |  |
| libzstd1 | 1.5.7+dfsg-3 | 4 | 1 | 0 | 2 |  |  |  |  |
| logsave | 1.47.2-3ubuntu4 | 4 | 2 | 0 | 2 |  |  |  |  |
| mawk | 1.3.4.20260129-1 | 18 | 16 | 0 | 2 |  | postinst,prerm |  |  |
| mount | 2.41.3-3ubuntu2.2 | 24 | 18 | 0 | 2 |  |  |  |  |
| ncurses-bin | 6.6+20251231-1 | 27 | 16 | 0 | 2 |  |  |  |  |
| netbase | 6.5build1 | 6 | 1 | 0 | 4 |  | postinst,postrm |  |  |
| openssl-provider-legacy | 3.5.5-1ubuntu3.5 | 3 | 1 | 0 | 2 |  |  |  |  |
| passwd | 1:4.17.4-2ubuntu3 | 368 | 336 | 0 | 12 |  | postinst,postrm,preinst,prerm |  |  |
| perl-modules-5.40 | 5.40.1-7ubuntu0.3 | 1336 | 2 | 0 | 56 |  |  |  |  |
| python3-minimal | 3.14.3-0ubuntu2 | 18 | 6 | 0 | 5 |  | postinst,prerm |  |  |
| python3-pip | 25.1.1+dfsg-1ubuntu2 | 684 | 249 | 0 | 3 |  | postinst,prerm |  |  |
| python3-wheel | 0.46.3-2 | 20 | 1 | 0 | 2 |  | postinst,prerm |  |  |
| python3.14 | 3.14.4-1ubuntu0.2 | 17 | 13 | 0 | 4 |  | postinst,prerm |  |  |
| readline-common | 8.3-4 | 8 | 6 | 0 | 2 |  | postinst,postrm |  |  |
| redis-tools | 5:8.0.5-1 | 16 | 11 | 0 | 2 |  | postinst,postrm |  |  |
| sensible-utils | 0.0.26build1 | 29 | 22 | 0 | 3 |  |  |  |  |
| shared-mime-info | 2.4-5build3 | 17 | 11 | 0 | 3 |  | postinst,postrm |  |  |
| sysvinit-utils | 3.15-5ubuntu1 | 14 | 5 | 0 | 4 |  |  |  |  |
| ubuntu-keyring | 2023.11.28.1build1 | 9 | 1 | 0 | 2 |  | postinst |  |  |
| zlib1g | 1:1.3.dfsg+really1.3.1-1ubuntu3.1 | 4 | 1 | 0 | 2 |  |  |  |  |
