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

## Repacking an existing image

- `repack-bin.sh IN.bin OUT.bin SLAVE_IMAGE [hardlink options]` — hardlink inside `dockerfs.tar.gz`, rebuild `fs.zip`, fix `payload_image_size` and `payload_sha1` in the sharch header. `zip` is taken from `SLAVE_IMAGE` (any `sonic-slave-resolute-*` image); the host needs pigz and util-linux `hardlink`.
- `repack-img.sh IN.img.gz OUT.img.gz [hardlink options]` — hardlink in place on an installed vs disk, `fstrim` the partition, convert back to qcow2 and gzip. `NOHL=1` skips the hardlink, which gives a baseline through the same pipeline.

## Boot test

- `build_kvm_image-local.patch` — the local changes to `scripts/build_kvm_image.sh` used for the ONIE installs. It drops the `apt-get` line, and binds VNC and SSH forwarding to 127.0.0.1.
  - The ONIE iso is `platform/vs/onie.mk`'s `onie-recovery-x86_64-kvm_x86_64-r0.iso`.
  - Install with `sudo -E env SONIC_USERNAME=admin PASSWD=YourPaSsWoRd ./build_kvm_image.sh OUT.img ONIE.iso sonic-vs.bin 16`.
- `vmtest.sh`:
  - `inject DISK RAW SCRIPT` converts the installed qcow2 to raw and installs `SCRIPT` as `hlcheck.service` in the image's `rw` overlay.
  - `boot RAW CONSOLE` boots it under KVM with 33 NICs until the guest powers off.
  - `fetch RAW DIR` copies `/host/hlcheck*.txt` out.
- `hlcheck.sh` — first-boot checks. It waits for the container set to stay unchanged for 3 minutes, then records:
  - the containers, the feature table, failed units, ASIC_DB ports and routes, BGP, and hardlink counts;
  - a copy-up test on `/usr/share/misc/pci.ids`, and whether `docker save` digests match `diff_ids`;
  - the results of `docker rmi docker-gbsyncd-vs`, `restart swss` and `config reload` (the `rmi` is refused on vs, where gbsyncd runs by default; `hlcheck2.sh` covers removal);
  - normalised syslog ERR lines.

  It then powers off.
- `hlcheck2.sh` — second boot: `docker rmi` the six images whose features are disabled, check that no remaining layer file changed, then run `config reload`.

## Results

`results/result-{a,b}.txt` come from `hlcheck.sh`, and `results/result2-{a,b}.txt` from `hlcheck2.sh`. `a` is the hardlinked 2026-08-23 vs image and `b` the unmodified one.
