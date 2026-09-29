# Docker layer duplication: tools and raw results

Tools behind [2026-09-29-resolute-docker-layer-dedup-report-en.md](../../2026-09-29-resolute-docker-layer-dedup-report-en.md).

## Analysis (no root needed for `.bin` input)

- `scan_tar.py X.pkl` — read an uncompressed dockerfs tar from stdin and record every file in the overlay2 layers: layer, path, type, size, sha256, mtime, mode, owner. It also keeps the small `image/` metadata files, which hold the layer graph.
- `scan_fs.py DOCKER_DIR X.pkl` — the same, for a mounted `/var/lib/docker` or `/host/image-*/docker`. Run as root.
- `analyze.py X.pkl` — duplicate bytes, copy histogram, the three kinds of duplicate, per-layer and per-directory waste, the largest duplicates, and the size if every image were flattened. Writes `X.pkl.graph`.
- `mtime_report.py X.pkl SDE` — bytes `hardlink` would save ignoring mtime, respecting it, and after clamping mtimes to `SDE`; plus shadowed bytes. `SDE` was the commit time of the build's source commit (`git log -1 --format=%ct`).
- `dedup_tar.py` — re-emit a tar stream with repeated contents as link entries, giving a lower bound for the compressed size.

A `.bin` into a scan:

```sh
sed -e '1,/^exit_marker$/d' sonic-X.bin | tar xf - installer/fs.zip
unzip -p installer/fs.zip dockerfs.tar.gz | pigz -dc | ./scan_tar.py X.pkl
./analyze.py X.pkl
./mtime_report.py X.pkl "$(git log -1 --format=%ct <build commit>)"
unzip -p installer/fs.zip dockerfs.tar.gz | pigz -dc | ./dedup_tar.py | pigz -c | wc -c
```

## Repacking and measuring

- `repack-bin.sh IN.bin OUT.bin SLAVE_IMAGE [hardlink options]` — hardlink inside `dockerfs.tar.gz`, rebuild `fs.zip`, fix `payload_image_size` and `payload_sha1` in the sharch header. `zip` is taken from `SLAVE_IMAGE` (any `sonic-slave-resolute-*` image); the host needs pigz and util-linux `hardlink`.
- `repack-img.sh IN.img.gz OUT.img.gz [hardlink options]` — hardlink in place on an installed vs disk, `fstrim` the partition, convert back to qcow2 and gzip. `NOHL=1` skips the hardlink, which gives a baseline through the same pipeline.
- `measure.sh NAME IMAGE.bin DISK` — print the sizes compared in the report:
  - from the `.bin`: `dockerfs.tar.gz` and the `.bin` itself;
  - from the installed disk (a qcow2, or the `.img.gz` of one): the docker directory, SONiC-OS partition usage, `img.gz` size, and files with more than one link.
- `attach.sh` — sourced by `measure.sh` and `vmtest.sh`. It attaches a disk image as a partitioned block device: loop for raw, `qemu-nbd` for qcow2.

## Building the rock variant

- `build_rocks-local.patch` — the local copy of `build_rocks.sh` used for the rock variant in §5. It runs `rockcraft clean` after each pack and leaves out `docker-iccpd`, which `INCLUDE_ICCPD=n` does not install.
- Sequence, from a vs-configured checkout:
  1. `make target/sonic-vs.img.gz`; keep `target/sonic-vs.{bin,img.gz}`.
  2. Check that `mount | grep dockers/` shows nothing, then run `sg lxd -c 'bash build_rocks-local.sh'`.
  3. Run `make target/sonic-vs.img.gz` again.

  `build_rocks.sh` ends each rock with `rm -r ./debs/`, and `slave.mk` bind-mounts `target/debs` there during docker builds; that is why step 2 checks for mounts first.

## Boot test

- `build_kvm_image-local.patch` — the local changes to `scripts/build_kvm_image.sh` used for the ONIE installs. It drops the `apt-get` line, and binds VNC and SSH forwarding to 127.0.0.1.
  - The ONIE iso is `platform/vs/onie.mk`'s `onie-recovery-x86_64-kvm_x86_64-r0.iso`.
  - Install with `sudo -E env SONIC_USERNAME=admin PASSWD=YourPaSsWoRd ./build_kvm_image.sh OUT.img ONIE.iso sonic-vs.bin 16`.
- `vmtest.sh` works on an installed disk, qcow2 or raw, and changes it in place:
  - `inject DISK SCRIPT` installs `SCRIPT` as `hlcheck.service` in the image's `rw` overlay.
  - `boot DISK CONSOLE` boots it under KVM with 33 NICs until the guest powers off.
  - `fetch DISK DIR` copies `/host/hlcheck*.txt` out.
- `hlcheck.sh` — first-boot checks. It waits for the container set to stay unchanged for 3 minutes, then records:
  - the containers, the feature table, failed units, ASIC_DB ports and routes, BGP, and hardlink counts;
  - a copy-up test on `/usr/share/misc/pci.ids`, and whether `docker save` digests match `diff_ids`;
  - the results of `docker rmi docker-gbsyncd-vs`, `restart swss` and `config reload` (the `rmi` is refused on vs, where gbsyncd runs by default; `hlcheck2.sh` covers removal);
  - normalised syslog ERR lines.

  It then powers off.
- `hlcheck2.sh` — second boot: `docker rmi` the six images whose features are disabled, check that no remaining layer file changed, then run `config reload`.

## Results

- `results/result-{a,b}.txt` come from `hlcheck.sh`, and `results/result2-{a,b}.txt` from `hlcheck2.sh`. `a` is the hardlinked 2026-08-23 vs image and `b` the unmodified one.
- `results/four-way/` holds the same-commit comparison (`43f0cf6558`). `D` is Dockerfile, `DH` Dockerfile with links, `R` rock and `RH` rock with links. It contains:
  - `*-hlcheck.txt` and `*-hlcheck2.txt`;
  - `sizes.txt` from `measure.sh`;
  - `mtime.txt` from `mtime_report.py`;
  - `D-analyze.txt` and `R-analyze.txt` from `analyze.py`.
