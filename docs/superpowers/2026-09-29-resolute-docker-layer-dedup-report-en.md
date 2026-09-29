# Duplicate files across SONiC docker images: measurements and the hardlink fix

- Date: 2026-09-29
- Images measured (all amd64):
  - resolute broadcom: the 2026-09-17 incremental build, the PR #14 CI build (`c05f0e016`) and the 2026-08-23 from-zero build (`2957b9e3`)
  - resolute vs: the 2026-08-27 build
  - official upstream 202605 broadcom: Azure build 20260928.6 (`6aec5bee6`, build id 1232715)
  - the rock-branch vs image `sonic-vs-rock-260929.img.gz` (`202605_resolute_rock.0-dirty-20260926.010724`)
- Change: local branch `feat/dockerfs-hardlink`, one signed commit `6dc4a02257` on top of `d2f9ae8502`, not pushed
- Tools and raw results: [data/2026-09-29-docker-layer-dedup/](data/2026-09-29-docker-layer-dedup/)
- This is the English version and the source of truth; the Chinese version is `-zh.md`

## 0. Conclusions

- **The SONiC docker images are not flattened to one layer.** Each Dockerfile adds one layer on top of its parent image, and overlay2 stores each shared parent layer once (§1).
- **Duplication comes from sibling images.** Images that do not share a parent each install the same files into their own layer. Examples are syncd and gbsyncd, protobuf and the SAI libraries.
  - resolute broadcom: 242 MB duplicated, 12% of all layer content.
  - resolute vs: 968 MB, 29%, most of it syncd-vs and gbsyncd-vs carrying the same toolchain.
  - official upstream broadcom: 241 MB, 11.8%. Upstream has the same problem at the same scale (§2).
  - rock vs: 3266 MB, 57% (§5).
- **Where it costs.** gzip cannot deduplicate across files, so the duplicates cost their compressed size in the `.bin` and their full size on disk after install.
- **The fix needs no common parent image.** Running util-linux `hardlink` over `overlay2/*/diff` just before `dockerfs.tar.gz` is packed takes one line in `build_debian.sh` (§3).
- **Verified end to end on vs**, by repacking an existing image rather than rebuilding (§4):
  - `dockerfs.tar.gz` 1025.6 → 742.1 MB and the installed docker directory 3356 → 2442 MB.
  - ONIE install, boot, copy-up isolation, `docker save` digests, `restart swss`, `config reload` and `docker rmi` all behave the same as the unmodified image.
- **Rock vs, repacked in place:** `img.gz` 3523.7 → 2596.0 MB (−26%), or 2412.3 MB (−32%) with `hardlink -t`. No boot test yet (§5).
- **mtime limits how much can be linked.** By default `hardlink` only merges files whose mtime also matches. Clamping build-time mtimes to `SOURCE_DATE_EPOCH` recovers nearly all of the remainder. This is the reproducible-build angle (§6).

## 1. How the images are stored

**Layers.** Images come in two shapes:

- **Dockerfile images.**
  - `docker-base-resolute` ends in `FROM scratch` / `COPY --from=base / /`, which makes it a single layer of 233 MB.
  - Every other Dockerfile starts `FROM $BASE` and adds one layer via the `rsync_from_builder_stage` macro (`dockers/dockerfile-macros.j2:48-50`), plus an empty `rm /cache.tgz` layer.
  - The chain is base (233 MB) → config-engine (94 MB) → swss-layer (32 MB, shared by 7 images) → the image's own layer.
  - A parent layer is stored once no matter how many images sit on it. If every broadcom image were flattened into one self-contained layer, the total would be 9828 MB instead of the 2018 MB stored now.
- **Rock images** have a different shape, described in §5.

**Storage path.**

- **`.bin`.** `sonic-*.bin` → `installer/fs.zip` → `dockerfs.tar.gz`. That last file is a pigz tar of the build's whole `/var/lib/docker`: overlay2 layer directories plus image metadata (`build_debian.sh:954-963`).
- **Installed disk.** On an installed disk, including the vs `img.gz`, `installer/install.sh:233` untars it into `/host/image-<version>/docker`.
- **Neither form deduplicates across layers.**

## 2. How much is duplicated

"Duplicated" means bytes of a regular file whose content (sha256) already exists elsewhere in the layer set. "Shadowed" means bytes in a lower layer that an upper layer of the same image overwrites. Shadowed bytes are stored but never visible.

| Image | Layer content | Duplicated | Shadowed |
|---|---|---|---|
| resolute broadcom, 2026-09-17 incremental | 2018 MB | **242 MB (12.0%)** | 43 MB |
| resolute broadcom, PR #14 CI build | 1986 MB | 227 MB (11.4%) | 19 MB |
| resolute broadcom, 2026-08-23 from-zero | 1989 MB | 226 MB (11.3%) | 1.5 MB |
| **official upstream 202605 broadcom** | 2043 MB | **241 MB (11.8%)** | 3.6 MB |
| resolute vs, 2026-08-27 | 3367 MB | **968 MB (28.7%)** | not measured |
| rock vs, 2026-09-26 | 5711 MB | **3266 MB (57.2%)** | 2.0 MB |

What the duplicate bytes are (2026-09-17 broadcom):

- 205.7 MB are the same path in a sibling or unrelated layer: two images that each installed the same package.
- 18.4 MB are the same content under a different path.
- 17.9 MB are a file an image re-copies although its own ancestor layer already has it.

Largest items:

| Wasted | Copies | File |
|---|---|---|
| 15.8 MB | ×6 | `libprotobuf.so.32` |
| 13.7 MB | ×5 | `libsaimetadata.so` |
| 12.5 MB | ×3 | `libc.a` |
| 10.0 MB | ×3 | `libsystemd-shared-259.so` |
| 9.6 MB | ×4 | `/usr/bin/syncd` (syncd-brcm plus three gbsyncd images) |
| 7.2 MB | ×5 | `libsairedis.so` |
| 6.3 MB | ×5 | `/usr/share/misc/pci.ids` |

Upstream's list is the same, plus about 22 copies of the buildinfo `copyrights.tar.gz`. On vs, 770 of the 968 MB come from docker-syncd-vs and docker-gbsyncd-vs, which both carry LLVM 21, clang, gcc's `cc1` and the gRPC static libraries.

**Shadowed bytes track version pinning.** In the 09-17 build, `docker-base-resolute` came from a 09-03 cache while config-engine was built on 09-17. apt had upgraded `libc6` and `python3.14` in between, so the old copies in the base layer are still stored underneath the new ones. The CI build shows the same drift within a single run (19 MB). Upstream pins deb versions and has 3.6 MB.

**Cost in each form**, for the 09-17 broadcom build:

- **`.bin`:** `dockerfs.tar.gz` is 555 MB. Storing duplicates as tar links brings it to 486 MB, so the duplicates cost 69 MB compressed. With a single `zstd --long=31` stream they would cost 0.2 MB, but that changes the format ONIE's installer has to read.
- **Disk:** full size, 265 MB after 4 KiB block rounding.
- **Host rootfs:** a further 306 MB of the host rootfs is byte-identical to files in docker layers. That is two separate archives, so these tools cannot link them.

## 3. The fix: hardlink before packing

```sh
## Hardlink identical files across docker image layers; tar keeps the links
sudo bash -c "hardlink --respect-xattrs $FILESYSTEM_ROOT/${DOCKERFS_PATH}var/lib/docker/overlay2/*/diff"
```

This goes in `build_debian.sh` immediately before `## Compress docker files`. The slave image already has util-linux 2.41.3 `hardlink`. Why it is safe:

- **tar.** GNU tar writes the second and later names of an inode as link entries, and busybox tar in ONIE restores them as links.
- **overlayfs.** Lower layers are read-only to containers. A write, `chmod` or `rm` inside a container copies the file up into that container's upper directory and leaves the shared inode untouched.
- **`docker save`** regenerates each layer tar from its diff directory, so layer digests do not change.
- **`docker rmi`** deletes a layer directory. A file still linked from another layer keeps its inode.
- **Merge rules.** `hardlink` only merges files with equal content, mode, owner, and (with `--respect-xattrs`) extended attributes. By default mtime must match too. `-t` drops the mtime check.
  - Neither measured layer set contains any `.pyc` file, so `-t` does not invalidate bytecode caches.
  - It does make some files report a different mtime than the one they were built with.

What it saves:

| Image | Measurement | Before | After |
|---|---|---|---|
| resolute broadcom 09-17 | ext4 used by layers | 2011 MB | 1790 MB |
| resolute broadcom 09-17 | `dockerfs.tar.gz` | 555 MB | 493 MB (486 MB if every duplicate were linked) |
| official 202605 broadcom | `dockerfs.tar.gz`, every duplicate linked | 593 MB | 507 MB |
| resolute vs 08-23 | `dockerfs.tar.gz` / installed docker dir | 1025.6 / 3356 MB | 742.1 / 2442 MB (§4) |
| rock vs 09-26 | `dockerfs.tar.gz`, default / `-t` | 1877 MB | 948 / 765 MB (§5) |

Of broadcom's 242 MB of duplicates, the default mode links 214 MB. The official image links 202 of its 241 MB. The rest have matching content but different mtimes (§6).

## 4. End-to-end check on vs

**Method.**

- **Base image.** `sonic-vs.bin` from the 2026-08-23 from-zero build (`202605_resolute_sheldon.0-2957b9e3`).
- **Hardlink variant.** Made by repacking that file, not by rebuilding (`repack-bin.sh`):
  - extract the payload, untar `dockerfs.tar.gz` with `--numeric-owner`, run `hardlink`, re-tar with pigz and update `fs.zip`;
  - rewrite `payload_image_size` and `payload_sha1` in the sharch header.
- **Install.** Both images went through a real ONIE install with a local copy of `scripts/build_kvm_image.sh`. The copy drops the `apt-get` line and binds VNC and SSH forwarding to 127.0.0.1.
- **Health check.** Done by an injected one-shot systemd unit (`hlcheck.sh`). It writes its results to `/host` and powers the VM off. An interactive serial session stopped responding from the second command on first boot, on both images.

**Size.**

| | Unmodified | Hardlinked |
|---|---|---|
| `dockerfs.tar.gz` | 1025.6 MB | 742.1 MB (−27.6%) |
| `sonic-vs.bin` | 2663.9 MB | 2380.4 MB |
| installed `/host/image-*/docker` | 3356 MB | 2442 MB |
| used on the SONiC-OS partition | 4932 MB | 4017 MB |
| `sonic-vs.img.gz` | 2679.6 MB | 2395.6 MB |

**Content.** After install, all 52,090 regular files match in content, mode, owner and mtime. The only differences are the mtimes of 4,029 symlinks, a by-product of unpacking and repacking.

**Behaviour** (`result-a.txt` hardlinked, `result-b.txt` unmodified):

| Check | Both images |
|---|---|
| Containers | 14 running, same set (bgp, database, eventd, gbsyncd, gnmi, lldp, mgmt-framework, pmon, radv, snmp, swss, syncd, sysmgr, teamd) |
| ASIC_DB | 33 PORT, 69 ROUTE_ENTRY; 32 ports in PORT_TABLE, PortInitDone set |
| BGP | 32 neighbors configured |
| Failed units | `system-health` and `watchdog-control`, which fail on every vs image |
| Copy-up | `/usr/share/misc/pci.ids` is one inode with 5 links in the hardlinked image and 5 separate inodes in the other. Appending to it inside swss changes it only in swss; bgp, lldp, pmon, snmp and all five layer files are unchanged |
| `docker save` | layer sha256s equal `rootfs.diff_ids` for docker-orchagent, docker-syncd-vs and docker-fpm-frr |
| `systemctl restart swss`, then `config reload` | all 14 containers back, 33 ports, same failed units |
| syslog ERR lines | same messages on both |

**Removing images** (`hlcheck2.sh`, `result2-*.txt`):

- `docker rmi` of the six images whose features are disabled (dhcp-relay, macsec, nat, sflow, mux, sonic-otel) removed 2,731 layer files, 2,075 of them hardlinked.
- 4,098 remaining files had shared an inode with a removed file. All still have their original content.
- No remaining file changed. A `config reload` afterwards came back with the same ports, routes and BGP neighbors.

## 5. The rock vs image

`sonic-vs-rock-260929.img.gz` contains 28 images: 14 packed with rockcraft and 14 still built from Dockerfiles. The rocks, identified by `umoci` in their history and `/usr/bin/pebble` as entrypoint, are:

> database, eventd, fpm-frr, iccpd, lldp, macsec, nat, platform-monitor, router-advertiser, sflow, snmp, sonic-gnmi, sonic-mgmt-framework, teamd

**Layer shape.** A rock has five layers:

- L0: the `ubuntu:26.04` base, 100 MB, shared by 13 of the rocks.
- L1: `/.rock/metadata.yaml`.
- L2: one fat layer holding every part, 117–327 MB.
- L3: the pebble layer YAML.
- L4: `metadata.yaml` again.

docker-database has only three layers and does not use the shared base; it carries 62 MB of base content itself.

**Why duplication is so high.** Rocks have no parent–child relation between each other. Each fat layer stages its own full runtime, which the Dockerfile images get once from config-engine and swss-layer. Of the 3266 MB duplicated, 2286 MB sits in rock fat layers. 105 MB of content (the full python3.14 tree, swsscommon, redis-tools) is present in all 13 fat layers that use the shared base.

**The mix is inconsistent.** One image runs two packaging models side by side:

- two base chains that cannot share layers with each other;
- two process supervisors, pebble in the rocks and supervisord elsewhere.

**Repack in place** (`repack-img.sh`: hardlink on the mounted SONiC-OS partition, `fstrim`, convert back to qcow2, gzip). The baseline is the unmodified disk sent through the same convert-and-gzip pipeline.

| | Unmodified | `hardlink` default | `hardlink -t` |
|---|---|---|---|
| `img.gz` | 3523.7 MB | 2596.0 MB (−26%) | 2412.3 MB (−32%) |
| `dockerfs.tar.gz` equivalent | 1877 MB | 948 MB | 765 MB |
| docker directory on disk | 5842 MB | 3133 MB | 2511 MB |

This image has not been booted, before or after.

**Rock vs Dockerfile after hardlinking.** Linking removes most of the gap between the two packaging models, but only if mtimes agree:

| docker directory | Unlinked | Default | `-t` |
|---|---|---|---|
| Dockerfile-only vs (08-27) | 3366 MB | 2436 MB | 2397 MB |
| rock vs (09-26) | 5843 MB | 3133 MB | 2511 MB |

With `-t` the two differ by 114 MB:

- 45 MB of real content difference: the rock image adds iccpd and is a month newer.
- About 56 MB of directory overhead: the rock image has 13,700 more directories, because every fat layer carries a whole directory tree, and directories cannot be hardlinked.

With the default mode they differ by 700 MB. Almost all of that is Python packages that pip installed into each rock's site-packages at different times.

## 6. mtime and reproducible builds

Files with identical content fail the default mtime check for two reasons:

1. **Build-time installs.** Files written during the build carry the time they were written: pip installs, dpkg and debconf state, buildinfo. The fix is to clamp every mtime newer than `SOURCE_DATE_EPOCH` down to it.
2. **Version drift.** Different images installed different versions of the same package. The fix is to pin package versions.

How much each step recovers:

| | Default mode | After clamping | Upper bound (`-t`) |
|---|---|---|---|
| resolute broadcom 09-17 | 214 MB | 226 MB | 242 MB |
| resolute broadcom 08-23 from-zero | — | 224.8 MB | 225.6 MB |
| official 202605 broadcom (versions pinned) | 202 MB | 239 MB | 240 MB |
| rock vs 09-26 | 2669 MB | 3260 MB | 3266 MB |

Where clamping has to happen:

- **Dockerfile images: at BuildKit export.** That means the `SOURCE_DATE_EPOCH` build argument plus `rewrite-timestamp=true`; the slave has docker 29.6.1 and buildx 0.35. It must not happen in the builder stage before the rsync layer. `rsync` compares size and mtime, so a file changed without a size change would be silently skipped.
  - `Makefile.work:295-304` already defines `SOURCE_DATE_EPOCH` (added for SBOM) and exports it into the slave container.
  - `slave.mk` does not pass it to `docker build`.
- **Rocks: in `override-prime`.** Touching everything newer than `SOURCE_DATE_EPOCH` there covers the pip-installed packages that make up most of the rock gap.

Pinning: upstream has `versions-deb-trixie` files and `MIRROR_SNAPSHOT`. resolute has neither. The Ubuntu equivalent is snapshot.ubuntu.com, which fixes every apt operation to one point in time.

Clamping and pinning are not prerequisites for the hardlink change. They raise its yield and make the result independent of when each image happened to be built.

## 7. Not done

- The hardlink change is a local commit, not a PR.
- The rock image has not been booted, with or without links.
- No vs image has been built from the rock branch merged with the current `202605_resolute`, so there is no A/B for one yet.
- Clamping at export and `override-prime` are measured by simulation only (`report2.py`). Neither has been implemented.
- The broadcom numbers come from analysing the images. The broadcom image was not installed on hardware or in a VM with links.
