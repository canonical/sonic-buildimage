# Real dependencies: /home/yan.jiang@canonical.com/.cache/rockdeps/vs/eventd/rootfs.tar

| package | evidence (count, sample) | platforms | covering slices |
|---|---|---|---|
| base-files | 1: trace /etc/host.conf | broadcom,vs | base-files_release-info |
| bash | 2: trace /bin/bash; trace /usr/bin/bash | broadcom,vs | bash_bins |
| coreutils-from-uutils | 7: trace /usr/bin/cat; trace /usr/bin/echo; trace /usr/bin/env | broadcom,vs | NO-SDF |
| gnu-coreutils | 1: trace /usr/bin/gnurm | broadcom,vs | gnu-coreutils_rm-bin |
| jq | 1: trace /usr/bin/jq | broadcom,vs | jq_bins |
| libboost-serialization1.83.0 | 3: ELF-needed /usr/lib/x86_64-linux-gnu/libboost_serialization.so.1.83.0 by /usr/bin/eventd,/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; trace /lib/x86_64-linux-gnu/libboost_serialization.so.1.83.0; trace /usr/lib/x86_64-linux-gnu/libboost_serialization.so.1.83.0 | broadcom,static,vs | libboost-serialization1.83.0_libs |
| libbsd0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libbsd.so.0 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; ELF-needed /usr/lib/x86_64-linux-gnu/libbsd.so.0.12.2 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; trace /usr/lib/x86_64-linux-gnu/libbsd.so.0 | broadcom,static,vs | libbsd0_libs |
| libc6 | 10: ELF-needed /lib64/ld-linux-x86-64.so.2 by /usr/bin/bash,/usr/bin/eventd; ELF-needed /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 by /usr/bin/bash,/usr/bin/eventd; ELF-needed /usr/lib/x86_64-linux-gnu/libc.so.6 by /usr/bin/bash,/usr/bin/eventd | broadcom,static,vs | libc6_libs |
| libcom-err2 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libcom_err.so.2 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; ELF-needed /usr/lib/x86_64-linux-gnu/libcom_err.so.2.1 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; trace /usr/lib/x86_64-linux-gnu/libcom_err.so.2 | broadcom,static,vs | libcom-err2_libs |
| libestr0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libestr.so.0 by /usr/sbin/rsyslogd; ELF-needed /usr/lib/x86_64-linux-gnu/libestr.so.0.0.0 by /usr/sbin/rsyslogd; trace /lib/x86_64-linux-gnu/libestr.so.0 | broadcom,static,vs | libestr0_libs |
| libexpat1 | 2: ELF-needed /usr/lib/x86_64-linux-gnu/libexpat.so.1 by /usr/lib/x86_64-linux-gnu/libpython3.14.so.1.0; ELF-needed /usr/lib/x86_64-linux-gnu/libexpat.so.1.11.2 by /usr/lib/x86_64-linux-gnu/libpython3.14.so.1.0 | static | libexpat1_libs |
| libfastjson4 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libfastjson.so.4 by /usr/sbin/rsyslogd; ELF-needed /usr/lib/x86_64-linux-gnu/libfastjson.so.4.3.0 by /usr/sbin/rsyslogd; trace /lib/x86_64-linux-gnu/libfastjson.so.4 | broadcom,static,vs | libfastjson4_libs |
| libffi8 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libffi.so.8 by /usr/lib/x86_64-linux-gnu/libp11-kit.so.0.4.8; ELF-needed /usr/lib/x86_64-linux-gnu/libffi.so.8.2.0 by /usr/lib/x86_64-linux-gnu/libp11-kit.so.0.4.8; trace /lib/x86_64-linux-gnu/libffi.so.8 | broadcom,static,vs | libffi8_libs |
| libgcc-s1 | 2: ELF-needed /usr/lib/x86_64-linux-gnu/libgcc_s.so.1 by /usr/bin/eventd,/usr/bin/eventdb; trace /usr/lib/x86_64-linux-gnu/libgcc_s.so.1 | broadcom,static,vs | libgcc-s1_libs |
| libgmp10 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libgmp.so.10 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libhogweed.so.6.11; ELF-needed /usr/lib/x86_64-linux-gnu/libgmp.so.10.5.0 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libhogweed.so.6.11; trace /usr/lib/x86_64-linux-gnu/libgmp.so.10 | broadcom,static,vs | libgmp10_libs |
| libgnutls30t64 | 5: ELF-needed /usr/lib/x86_64-linux-gnu/libgnutls.so.30 by /usr/lib/x86_64-linux-gnu/librelp.so.0.5.1; ELF-needed /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1 by /usr/lib/x86_64-linux-gnu/librelp.so.0.5.1; trace /etc/gnutls/config | broadcom,static,vs | libgnutls30t64_libs |
| libgssapi-krb5-2 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; ELF-needed /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; trace /lib/x86_64-linux-gnu/libgssapi_krb5.so.2 | broadcom,static,vs | libgssapi-krb5-2_libs |
| libhiredis1.1.0 | 3: ELF-needed /usr/lib/x86_64-linux-gnu/libhiredis.so.1.1.0 by /usr/lib/python3/dist-packages/swsscommon/_swsscommon.so.0.0.0,/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; trace /lib/x86_64-linux-gnu/libhiredis.so.1.1.0; trace /usr/lib/x86_64-linux-gnu/libhiredis.so.1.1.0 | broadcom,static,vs | libhiredis1.1.0_libs |
| libhogweed6t64 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libhogweed.so.6 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; ELF-needed /usr/lib/x86_64-linux-gnu/libhogweed.so.6.11 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; trace /lib/x86_64-linux-gnu/libhogweed.so.6 | broadcom,static,vs | libhogweed6t64_libs |
| libidn2-0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libidn2.so.0 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; ELF-needed /usr/lib/x86_64-linux-gnu/libidn2.so.0.4.0 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; trace /lib/x86_64-linux-gnu/libidn2.so.0 | broadcom,static,vs | libidn2-0_libs |
| libjq1 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libjq.so.1 by /usr/bin/jq; ELF-needed /usr/lib/x86_64-linux-gnu/libjq.so.1.0.4 by /usr/bin/jq; trace /lib/x86_64-linux-gnu/libjq.so.1 | broadcom,static,vs | libjq1_libs |
| libk5crypto3 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libk5crypto.so.3 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; ELF-needed /usr/lib/x86_64-linux-gnu/libk5crypto.so.3.1 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; trace /lib/x86_64-linux-gnu/libk5crypto.so.3 | broadcom,static,vs | libk5crypto3_libs |
| libkeyutils1 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libkeyutils.so.1 by /usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; ELF-needed /usr/lib/x86_64-linux-gnu/libkeyutils.so.1.10 by /usr/lib/x86_64-linux-gnu/libkrb5.so.3.3; trace /lib/x86_64-linux-gnu/libkeyutils.so.1 | broadcom,static,vs | libkeyutils1_libs |
| libkrb5-3 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libkrb5.so.3 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2; ELF-needed /usr/lib/x86_64-linux-gnu/libkrb5.so.3.3 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2; trace /lib/x86_64-linux-gnu/libkrb5.so.3 | broadcom,static,vs | libkrb5-3_libs |
| libkrb5support0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libkrb5support.so.0 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libk5crypto.so.3.1; ELF-needed /usr/lib/x86_64-linux-gnu/libkrb5support.so.0.1 by /usr/lib/x86_64-linux-gnu/libgssapi_krb5.so.2.2,/usr/lib/x86_64-linux-gnu/libk5crypto.so.3.1; trace /lib/x86_64-linux-gnu/libkrb5support.so.0 | broadcom,static,vs | libkrb5support0_libs |
| libmd0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libmd.so.0 by /usr/lib/x86_64-linux-gnu/libbsd.so.0.12.2; ELF-needed /usr/lib/x86_64-linux-gnu/libmd.so.0.1.0 by /usr/lib/x86_64-linux-gnu/libbsd.so.0.12.2; trace /usr/lib/x86_64-linux-gnu/libmd.so.0 | broadcom,static,vs | libmd0_libs |
| libnettle8t64 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libnettle.so.8 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libhogweed.so.6.11; ELF-needed /usr/lib/x86_64-linux-gnu/libnettle.so.8.11 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libhogweed.so.6.11; trace /lib/x86_64-linux-gnu/libnettle.so.8 | broadcom,static,vs | libnettle8t64_libs |
| libnl-3-200 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libnl-3.so.200 by /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200.26.0,/usr/lib/x86_64-linux-gnu/libnl-route-3.so.200.26.0; ELF-needed /usr/lib/x86_64-linux-gnu/libnl-3.so.200.26.0 by /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200.26.0,/usr/lib/x86_64-linux-gnu/libnl-route-3.so.200.26.0; trace /lib/x86_64-linux-gnu/libnl-3.so.200 | broadcom,static,vs | libnl-3-200_libs |
| libnl-nf-3-200 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200 by /usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; ELF-needed /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200.26.0 by /usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; trace /lib/x86_64-linux-gnu/libnl-nf-3.so.200 | broadcom,static,vs | libnl-nf-3-200_libs |
| libnl-route-3-200 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libnl-route-3.so.200 by /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200.26.0,/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; ELF-needed /usr/lib/x86_64-linux-gnu/libnl-route-3.so.200.26.0 by /usr/lib/x86_64-linux-gnu/libnl-nf-3.so.200.26.0,/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0; trace /lib/x86_64-linux-gnu/libnl-route-3.so.200 | broadcom,static,vs | libnl-route-3-200_libs |
| libnorm1t64 | 3: ELF-needed /usr/lib/x86_64-linux-gnu/libnorm.so.1 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; trace /lib/x86_64-linux-gnu/libnorm.so.1; trace /usr/lib/x86_64-linux-gnu/libnorm.so.1 | broadcom,static,vs | libnorm1t64_libs |
| libonig5 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libonig.so.5 by /usr/bin/jq,/usr/lib/x86_64-linux-gnu/libjq.so.1.0.4; ELF-needed /usr/lib/x86_64-linux-gnu/libonig.so.5.5.0 by /usr/bin/jq,/usr/lib/x86_64-linux-gnu/libjq.so.1.0.4; trace /lib/x86_64-linux-gnu/libonig.so.5 | broadcom,static,vs | libonig5_libs |
| libp11-kit0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libp11-kit.so.0 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; ELF-needed /usr/lib/x86_64-linux-gnu/libp11-kit.so.0.4.8 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; trace /lib/x86_64-linux-gnu/libp11-kit.so.0 | broadcom,static,vs | libp11-kit0_libs |
| libpcre2-8-0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0 by /usr/lib/x86_64-linux-gnu/libselinux.so.1,/usr/lib/x86_64-linux-gnu/libyang.so.3.9.14; ELF-needed /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0.14.0 by /usr/lib/x86_64-linux-gnu/libselinux.so.1,/usr/lib/x86_64-linux-gnu/libyang.so.3.9.14; trace /usr/lib/x86_64-linux-gnu/libpcre2-8.so.0 | broadcom,static,vs | libpcre2-8-0_libs |
| libpgm-5.3-0t64 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libpgm-5.3.so.0 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; ELF-needed /usr/lib/x86_64-linux-gnu/libpgm-5.3.so.0.0.128 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; trace /lib/x86_64-linux-gnu/libpgm-5.3.so.0 | broadcom,static,vs | libpgm-5.3-0t64_libs |
| libproc2-0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libproc2.so.0 by /usr/bin/pgrep,/usr/bin/ps; ELF-needed /usr/lib/x86_64-linux-gnu/libproc2.so.0.0.2 by /usr/bin/pgrep,/usr/bin/ps; trace /usr/lib/x86_64-linux-gnu/libproc2.so.0 | broadcom,static,vs | libproc2-0_libs |
| libpython3.14 | 1: ELF-needed /usr/lib/x86_64-linux-gnu/libpython3.14.so.1.0 by /usr/lib/python3/dist-packages/swsscommon/_swsscommon.so.0.0.0 | static | libpython3.14_libs |
| libreadline8t64 | 2: ELF-needed /usr/lib/x86_64-linux-gnu/libreadline.so.8 by /usr/bin/filan,/usr/bin/procan; ELF-needed /usr/lib/x86_64-linux-gnu/libreadline.so.8.3 by /usr/bin/filan,/usr/bin/procan | static | libreadline8t64_libs |
| librelp0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/librelp.so.0 by /usr/lib/x86_64-linux-gnu/rsyslog/omrelp.so; ELF-needed /usr/lib/x86_64-linux-gnu/librelp.so.0.5.1 by /usr/lib/x86_64-linux-gnu/rsyslog/omrelp.so; trace /lib/x86_64-linux-gnu/librelp.so.0 | broadcom,static,vs | librelp0_libs |
| libselinux1 | 2: ELF-needed /usr/lib/x86_64-linux-gnu/libselinux.so.1 by /usr/lib/cargo/bin/coreutils/b3sum,/usr/lib/cargo/bin/coreutils/cat; trace /usr/lib/x86_64-linux-gnu/libselinux.so.1 | broadcom,static,vs | libselinux1_libs |
| libsodium23 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libsodium.so.23 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; ELF-needed /usr/lib/x86_64-linux-gnu/libsodium.so.23.3.0 by /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5; trace /lib/x86_64-linux-gnu/libsodium.so.23 | broadcom,static,vs | libsodium23_libs |
| libssl3t64 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libcrypto.so.3 by /usr/bin/socat1,/usr/lib/x86_64-linux-gnu/librelp.so.0.5.1; ELF-needed /usr/lib/x86_64-linux-gnu/libssl.so.3 by /usr/bin/socat1,/usr/lib/x86_64-linux-gnu/librelp.so.0.5.1; trace /usr/lib/x86_64-linux-gnu/libcrypto.so.3 | broadcom,static,vs | libssl3t64_libs |
| libstdc++6 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libstdc++.so.6 by /usr/bin/eventd,/usr/bin/eventdb; ELF-needed /usr/lib/x86_64-linux-gnu/libstdc++.so.6.0.35 by /usr/bin/eventd,/usr/bin/eventdb; trace /usr/lib/x86_64-linux-gnu/libstdc++.so.6 | broadcom,static,vs | libstdc++6_libs |
| libsystemd0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libsystemd.so.0 by /usr/lib/cargo/bin/coreutils/b3sum,/usr/lib/cargo/bin/coreutils/cat; ELF-needed /usr/lib/x86_64-linux-gnu/libsystemd.so.0.42.0 by /usr/lib/cargo/bin/coreutils/b3sum,/usr/lib/cargo/bin/coreutils/cat; trace /usr/lib/x86_64-linux-gnu/libsystemd.so.0 | broadcom,static,vs | libsystemd0_libs |
| libtasn1-6 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libtasn1.so.6 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; ELF-needed /usr/lib/x86_64-linux-gnu/libtasn1.so.6.6.5 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1; trace /lib/x86_64-linux-gnu/libtasn1.so.6 | broadcom,static,vs | libtasn1-6_libs |
| libtinfo6 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libtinfo.so.6 by /usr/bin/bash,/usr/bin/more; ELF-needed /usr/lib/x86_64-linux-gnu/libtinfo.so.6.6 by /usr/bin/bash,/usr/bin/more; trace /usr/lib/x86_64-linux-gnu/libtinfo.so.6 | broadcom,static,vs | libtinfo6_libs |
| libunistring5 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libunistring.so.5 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libidn2.so.0.4.0; ELF-needed /usr/lib/x86_64-linux-gnu/libunistring.so.5.2.0 by /usr/lib/x86_64-linux-gnu/libgnutls.so.30.41.1,/usr/lib/x86_64-linux-gnu/libidn2.so.0.4.0; trace /lib/x86_64-linux-gnu/libunistring.so.5 | broadcom,static,vs | libunistring5_libs |
| libuuid1 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libuuid.so.1 by /usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0,/usr/sbin/rsyslogd; ELF-needed /usr/lib/x86_64-linux-gnu/libuuid.so.1.3.0 by /usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0,/usr/sbin/rsyslogd; trace /usr/lib/x86_64-linux-gnu/libuuid.so.1 | broadcom,static,vs | libuuid1_libs |
| libwrap0 | 2: ELF-needed /usr/lib/x86_64-linux-gnu/libwrap.so.0 by /usr/bin/socat1; ELF-needed /usr/lib/x86_64-linux-gnu/libwrap.so.0.7.6 by /usr/bin/socat1 | static | libwrap0_libs |
| libxxhash0 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libxxhash.so.0 by /usr/lib/x86_64-linux-gnu/libyang.so.3.9.14; ELF-needed /usr/lib/x86_64-linux-gnu/libxxhash.so.0.8.3 by /usr/lib/x86_64-linux-gnu/libyang.so.3.9.14; trace /usr/lib/x86_64-linux-gnu/libxxhash.so.0 | broadcom,static,vs | libxxhash0_libs |
| libzmq5 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libzmq.so.5 by /usr/bin/eventd,/usr/bin/events_tool; ELF-needed /usr/lib/x86_64-linux-gnu/libzmq.so.5.2.5 by /usr/bin/eventd,/usr/bin/events_tool; trace /lib/x86_64-linux-gnu/libzmq.so.5 | broadcom,static,vs | libzmq5_libs |
| libzstd1 | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libzstd.so.1 by /usr/lib/x86_64-linux-gnu/libcrypto.so.3; ELF-needed /usr/lib/x86_64-linux-gnu/libzstd.so.1.5.7 by /usr/lib/x86_64-linux-gnu/libcrypto.so.3; trace /usr/lib/x86_64-linux-gnu/libzstd.so.1 | broadcom,static,vs | libzstd1_libs |
| netbase | 1: trace /etc/protocols | broadcom,vs | netbase_config |
| procps | 3: trace /usr/bin/kill; trace /usr/bin/pgrep; trace /usr/bin/ps | broadcom,vs | procps_bins procps_ps-bin |
| rsyslog | 4: trace /etc/rsyslog.conf; trace /usr/lib/x86_64-linux-gnu/rsyslog/imuxsock.so; trace /usr/lib/x86_64-linux-gnu/rsyslog/lmnet.so | broadcom,vs | rsyslog_bins rsyslog_config rsyslog_modules |
| rsyslog-relp | 1: trace /usr/lib/x86_64-linux-gnu/rsyslog/omrelp.so | broadcom,vs | rsyslog-relp_modules |
| rust-coreutils | 7: trace /usr/lib/cargo/bin/coreutils/cat; trace /usr/lib/cargo/bin/coreutils/echo; trace /usr/lib/cargo/bin/coreutils/env | broadcom,vs | NO-SDF |
| zlib1g | 4: ELF-needed /usr/lib/x86_64-linux-gnu/libz.so.1 by /usr/lib/x86_64-linux-gnu/libcrypto.so.3,/usr/lib/x86_64-linux-gnu/libpython3.14.so.1.0; ELF-needed /usr/lib/x86_64-linux-gnu/libz.so.1.3.1 by /usr/lib/x86_64-linux-gnu/libcrypto.so.3,/usr/lib/x86_64-linux-gnu/libpython3.14.so.1.0; trace /usr/lib/x86_64-linux-gnu/libz.so.1 | broadcom,static,vs | zlib1g_libs |

## Used paths no slice covers (they would be missing from a chiselled rock)

- `/etc/gnutls/config` (libgnutls30t64)

## Non-archive files used (self-built debs, wheels, generated)

- `/`  [broadcom,vs]
- `/etc/evprofile/default.json`  [broadcom,vs]
- `/etc/group`  [broadcom,vs]
- `/etc/hosts`  [broadcom,vs]
- `/etc/ld.so.cache`  [broadcom,vs]
- `/etc/localtime`  [broadcom,vs]
- `/etc/nsswitch.conf`  [broadcom,vs]
- `/etc/passwd`  [broadcom,vs]
- `/etc/resolv.conf`  [broadcom,vs]
- `/etc/rsyslog.d`  [broadcom,vs]
- `/etc/rsyslog.d/rsyslog_plugin_conf`  [broadcom,vs]
- `/etc/supervisor/critical_processes`  [vs]
- `/lib/x86_64-linux-gnu/libswsscommon.so.0`  [broadcom,vs]
- `/lib/x86_64-linux-gnu/libyang.so.3`  [broadcom,vs]
- `/run/redis/sonic-db/database_config.json`  [broadcom,vs]
- `/usr/bin/eventd`  [broadcom,vs]
- `/usr/bin/eventdb_wrapper.sh`  [broadcom,vs]
- `/usr/bin/pebble`  [broadcom,vs]
- `/usr/bin/start.sh`  [broadcom,vs]
- `/usr/bin/supervisor-proc-exit-listener-rs`  [vs]
- `/usr/lib/x86_64-linux-gnu/libswsscommon.so.0.0.0`  [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/libyang.so.3.9.14`  [broadcom,vs]
- `/usr/share/sonic/templates/syslog-layer.yaml`  [broadcom,vs]
- `/var/lib/pebble/default`  [broadcom,vs]
- `/var/lib/pebble/default/.pebble.state`  [broadcom,vs]
- `/var/lib/pebble/default/layers`  [broadcom,vs]
- `/var/lib/pebble/default/layers/001-rockcraft-docker-eventd.yaml`  [broadcom,vs]
- `/var/run/redis/sonic-db/database_config.json`  [broadcom,vs]

## Traced but absent from this rootfs (failed probes, or build differences: review)

- `/etc/libnl/classid` [broadcom,vs]
- `/etc/sonic/init_cfg.json` [broadcom,vs]
- `/etc/supervisor/watchdog_processes` [vs]
- `/lib/glibc-hwcaps/x86-64-v2/libnss_db.so.2` [broadcom,vs]
- `/lib/glibc-hwcaps/x86-64-v2/libnuma.so` [broadcom,vs]
- `/lib/glibc-hwcaps/x86-64-v3/libnss_db.so.2` [vs]
- `/lib/glibc-hwcaps/x86-64-v3/libnuma.so` [vs]
- `/lib/libnss_db.so.2` [broadcom,vs]
- `/lib/libnuma.so` [broadcom,vs]
- `/lib/libnuma.so.1` [broadcom,vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libestr.so.0` [broadcom,vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libjq.so.1` [broadcom,vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libnuma.so` [broadcom,vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libswsscommon.so.0` [broadcom,vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libestr.so.0` [vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libjq.so.1` [vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libnuma.so` [vs]
- `/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libswsscommon.so.0` [vs]
- `/lib/x86_64-linux-gnu/libnss_db.so.2` [broadcom,vs]
- `/lib/x86_64-linux-gnu/libnuma.so` [broadcom,vs]
- `/lib/x86_64-linux-gnu/libnuma.so.1` [broadcom,vs]
- `/root/.config/pebble/cli.json` [broadcom,vs]
- `/runc` [broadcom,vs]
- `/tmp/rockdeps-probe` [broadcom,vs]
- `/tmp/rockdeps-probe.d` [broadcom,vs]
- `/usr/lib/glibc-hwcaps/x86-64-v2/libnss_db.so.2` [broadcom,vs]
- `/usr/lib/glibc-hwcaps/x86-64-v2/libnuma.so` [broadcom,vs]
- `/usr/lib/glibc-hwcaps/x86-64-v3/libnss_db.so.2` [vs]
- `/usr/lib/glibc-hwcaps/x86-64-v3/libnuma.so` [vs]
- `/usr/lib/libnss_db.so.2` [broadcom,vs]
- `/usr/lib/libnuma.so` [broadcom,vs]
- `/usr/lib/libnuma.so.1` [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libnss_db.so.2` [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v2/libnuma.so` [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libnss_db.so.2` [vs]
- `/usr/lib/x86_64-linux-gnu/glibc-hwcaps/x86-64-v3/libnuma.so` [vs]
- `/usr/lib/x86_64-linux-gnu/libnss_db.so.2` [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/libnuma.so` [broadcom,vs]
- `/usr/lib/x86_64-linux-gnu/libnuma.so.1` [broadcom,vs]
- `/usr/share/coreutils/locales/cat/en-US.ftl` [broadcom,vs]
- `/usr/share/coreutils/locales/echo/en-US.ftl` [broadcom,vs]
- `/usr/share/coreutils/locales/env/en-US.ftl` [broadcom,vs]
- `/usr/share/coreutils/locales/ls/en-US.ftl` [broadcom,vs]
- `/usr/share/coreutils/locales/mkdir/en-US.ftl` [broadcom,vs]
- `/usr/share/coreutils/locales/touch/en-US.ftl` [broadcom,vs]
- `/var/lib/crypto-config/profiles/current/gnutls.conf` [broadcom,vs]
- `/var/lib/docker/overlay2/3e833be9d59c02b54b635802c3b492626d7d5f57049825d2510ce8088c0743d3/merged` [vs]
- `/var/lib/docker/overlay2/4577b603ac42aabee53e93352f8870f9225f447204a31ed78c1400e57366234d/merged` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1042921785~` [vs]
- `/var/lib/pebble/default/.pebble.state.104321433~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1060133128~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1089314189~` [vs]
- `/var/lib/pebble/default/.pebble.state.1096015787~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1096415730~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1169415978~` [vs]
- `/var/lib/pebble/default/.pebble.state.1178502263~` [vs]
- `/var/lib/pebble/default/.pebble.state.1183896827~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1198798851~` [vs]
- `/var/lib/pebble/default/.pebble.state.1219952208~` [vs]
- `/var/lib/pebble/default/.pebble.state.126549643~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1273898576~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1290956410~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.130347268~` [vs]
- `/var/lib/pebble/default/.pebble.state.130519637~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1308395609~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1316719830~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1355771424~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1359347996~` [vs]
- `/var/lib/pebble/default/.pebble.state.1369712031~` [vs]
- `/var/lib/pebble/default/.pebble.state.1372534952~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1384554726~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1394806310~` [vs]
- `/var/lib/pebble/default/.pebble.state.1414115081~` [vs]
- `/var/lib/pebble/default/.pebble.state.1428920115~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.145706115~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1501087423~` [vs]
- `/var/lib/pebble/default/.pebble.state.1514148139~` [vs]
- `/var/lib/pebble/default/.pebble.state.1527337230~` [vs]
- `/var/lib/pebble/default/.pebble.state.1569217346~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1572853286~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1592156434~` [vs]
- `/var/lib/pebble/default/.pebble.state.1592237444~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1613409176~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1617741907~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1623845430~` [vs]
- `/var/lib/pebble/default/.pebble.state.1716288284~` [vs]
- `/var/lib/pebble/default/.pebble.state.1770873687~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1783837667~` [vs]
- `/var/lib/pebble/default/.pebble.state.1786444490~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1803804434~` [vs]
- `/var/lib/pebble/default/.pebble.state.1818714055~` [vs]
- `/var/lib/pebble/default/.pebble.state.1891203548~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1893704808~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.1918555672~` [vs]
- `/var/lib/pebble/default/.pebble.state.1945900738~` [vs]
- `/var/lib/pebble/default/.pebble.state.1963266118~` [vs]
- `/var/lib/pebble/default/.pebble.state.1963271563~` [vs]
- `/var/lib/pebble/default/.pebble.state.1986948703~` [vs]
- `/var/lib/pebble/default/.pebble.state.2014020868~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2042164604~` [vs]
- `/var/lib/pebble/default/.pebble.state.2080361219~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2136287142~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2140998992~` [vs]
- `/var/lib/pebble/default/.pebble.state.2159347957~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2189019813~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2220516866~` [vs]
- `/var/lib/pebble/default/.pebble.state.2246605175~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2254846311~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2264830364~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2331754972~` [vs]
- `/var/lib/pebble/default/.pebble.state.2367081864~` [vs]
- `/var/lib/pebble/default/.pebble.state.2390526754~` [vs]
- `/var/lib/pebble/default/.pebble.state.2392219543~` [vs]
- `/var/lib/pebble/default/.pebble.state.2406941672~` [vs]
- `/var/lib/pebble/default/.pebble.state.2444982773~` [vs]
- `/var/lib/pebble/default/.pebble.state.24878757~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2497315486~` [vs]
- `/var/lib/pebble/default/.pebble.state.2515349798~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2521350337~` [vs]
- `/var/lib/pebble/default/.pebble.state.2523762220~` [vs]
- `/var/lib/pebble/default/.pebble.state.2548490694~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2556298566~` [vs]
- `/var/lib/pebble/default/.pebble.state.2556519725~` [vs]
- `/var/lib/pebble/default/.pebble.state.2571121332~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2584201962~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2593018156~` [vs]
- `/var/lib/pebble/default/.pebble.state.2598833884~` [vs]
- `/var/lib/pebble/default/.pebble.state.2602475366~` [vs]
- `/var/lib/pebble/default/.pebble.state.2665145677~` [vs]
- `/var/lib/pebble/default/.pebble.state.2741334977~` [vs]
- `/var/lib/pebble/default/.pebble.state.2782342919~` [vs]
- `/var/lib/pebble/default/.pebble.state.2783033073~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2815554375~` [vs]
- `/var/lib/pebble/default/.pebble.state.2852032441~` [vs]
- `/var/lib/pebble/default/.pebble.state.287506335~` [vs]
- `/var/lib/pebble/default/.pebble.state.2885418030~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2984621583~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.299219377~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.2996928430~` [vs]
- `/var/lib/pebble/default/.pebble.state.3004329814~` [vs]
- `/var/lib/pebble/default/.pebble.state.3020886266~` [vs]
- `/var/lib/pebble/default/.pebble.state.3039503504~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3039706059~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3049919602~` [vs]
- `/var/lib/pebble/default/.pebble.state.3068828070~` [vs]
- `/var/lib/pebble/default/.pebble.state.3079040401~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3085415976~` [vs]
- `/var/lib/pebble/default/.pebble.state.3087365805~` [vs]
- `/var/lib/pebble/default/.pebble.state.3113731110~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3197471246~` [vs]
- `/var/lib/pebble/default/.pebble.state.3210190181~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3231918800~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3261921663~` [vs]
- `/var/lib/pebble/default/.pebble.state.3272118180~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3314919938~` [vs]
- `/var/lib/pebble/default/.pebble.state.3315316909~` [vs]
- `/var/lib/pebble/default/.pebble.state.3350833299~` [vs]
- `/var/lib/pebble/default/.pebble.state.3365260948~` [vs]
- `/var/lib/pebble/default/.pebble.state.3373111378~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3410597103~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3418379051~` [vs]
- `/var/lib/pebble/default/.pebble.state.3425285388~` [vs]
- `/var/lib/pebble/default/.pebble.state.3433417296~` [vs]
- `/var/lib/pebble/default/.pebble.state.3455189349~` [vs]
- `/var/lib/pebble/default/.pebble.state.3534862391~` [vs]
- `/var/lib/pebble/default/.pebble.state.3592367494~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.360632299~` [vs]
- `/var/lib/pebble/default/.pebble.state.3614498580~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3650649475~` [vs]
- `/var/lib/pebble/default/.pebble.state.3652592947~` [vs]
- `/var/lib/pebble/default/.pebble.state.3663691571~` [vs]
- `/var/lib/pebble/default/.pebble.state.3678765975~` [vs]
- `/var/lib/pebble/default/.pebble.state.3707947432~` [vs]
- `/var/lib/pebble/default/.pebble.state.3718643876~` [vs]
- `/var/lib/pebble/default/.pebble.state.3742080567~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3857675771~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3939779362~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.3967253074~` [vs]
- `/var/lib/pebble/default/.pebble.state.397699845~` [vs]
- `/var/lib/pebble/default/.pebble.state.4010394056~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.401591620~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4052951272~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4056998125~` [vs]
- `/var/lib/pebble/default/.pebble.state.4100447800~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4121123013~` [vs]
- `/var/lib/pebble/default/.pebble.state.4138942999~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.417466073~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4176740632~` [vs]
- `/var/lib/pebble/default/.pebble.state.4225866128~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4263491892~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.4266274601~` [vs]
- `/var/lib/pebble/default/.pebble.state.473483516~` [vs]
- `/var/lib/pebble/default/.pebble.state.51966556~` [vs]
- `/var/lib/pebble/default/.pebble.state.550191218~` [vs]
- `/var/lib/pebble/default/.pebble.state.555224433~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.5935956~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.596171538~` [vs]
- `/var/lib/pebble/default/.pebble.state.60147410~` [vs]
- `/var/lib/pebble/default/.pebble.state.625170861~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.644159295~` [vs]
- `/var/lib/pebble/default/.pebble.state.66572435~` [vs]
- `/var/lib/pebble/default/.pebble.state.686626059~` [vs]
- `/var/lib/pebble/default/.pebble.state.716721332~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.792098935~` [vs]
- `/var/lib/pebble/default/.pebble.state.835153418~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.863910986~` [vs]
- `/var/lib/pebble/default/.pebble.state.8673725~` [vs]
- `/var/lib/pebble/default/.pebble.state.873516062~` [vs]
- `/var/lib/pebble/default/.pebble.state.909779791~` [vs]
- `/var/lib/pebble/default/.pebble.state.951921537~` [broadcom]
- `/var/lib/pebble/default/.pebble.state.988178926~` [broadcom]

## Missing libraries (NEEDED but not found in rootfs)


## Diff against /tmp/opencode/an3/eventd.head-rockcraft.yaml

Unused (in recipe, no evidence): iproute2, libdaemon0, libdbus-1-3, libjansson4, libnl-cli-3-200, net-tools, python3, python3-cffi-backend, python3-redis, python3-venv, python3-yaml, redis-tools

Used but not in recipe (came in as Depends): base-files, bash, coreutils-from-uutils, gnu-coreutils, libbsd0, libc6, libcom-err2, libestr0, libexpat1, libfastjson4, libffi8, libgcc-s1, libgmp10, libgnutls30t64, libgssapi-krb5-2, libhogweed6t64, libidn2-0, libjq1, libk5crypto3, libkeyutils1, libkrb5-3, libkrb5support0, libmd0, libnettle8t64, libnl-3-200, libnl-nf-3-200, libnl-route-3-200, libnorm1t64, libonig5, libp11-kit0, libpcre2-8-0, libpgm-5.3-0t64, libproc2-0, libreadline8t64, librelp0, libselinux1, libsodium23, libssl3t64, libstdc++6, libsystemd0, libtasn1-6, libtinfo6, libunistring5, libuuid1, libzstd1, netbase, procps, rust-coreutils, zlib1g
